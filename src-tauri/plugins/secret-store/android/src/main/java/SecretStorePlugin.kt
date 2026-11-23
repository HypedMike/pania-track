package app.pania.secretstore

import android.app.Activity
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

@InvokeArg
class KeyArgs {
    lateinit var key: String
}

@InvokeArg
class SetArgs {
    lateinit var key: String
    lateinit var value: String
}

/**
 * Secrets are encrypted with an AES-256-GCM key that never leaves the Android Keystore; only
 * `base64(iv ‖ ciphertext)` is written to private SharedPreferences. A secret whose Keystore
 * key is gone (app data restored from a backup onto another device, say) reads as absent.
 */
@TauriPlugin
class SecretStorePlugin(private val activity: Activity) : Plugin(activity) {
    private val prefs
        get() = activity.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    @Command
    fun getSecret(invoke: Invoke) {
        val args = invoke.parseArgs(KeyArgs::class.java)
        val stored = prefs.getString(args.key, null)
        val value = stored?.let { decrypt(it) }
        val result = JSObject()
        // JSObject.put(String, Object) with null would store JSON null, which is what we want.
        result.put("value", value)
        invoke.resolve(result)
    }

    @Command
    fun setSecret(invoke: Invoke) {
        val args = invoke.parseArgs(SetArgs::class.java)
        try {
            // commit(), not apply(): the caller must know the secret is durable before it
            // shows the user a "profile created" screen.
            if (!prefs.edit().putString(args.key, encrypt(args.value)).commit()) {
                invoke.reject("Could not save the secret.")
                return
            }
            invoke.resolve()
        } catch (e: Exception) {
            invoke.reject("Could not save the secret: ${e.message}")
        }
    }

    @Command
    fun deleteSecret(invoke: Invoke) {
        val args = invoke.parseArgs(KeyArgs::class.java)
        prefs.edit().remove(args.key).commit()
        invoke.resolve()
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val ciphertext = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv + ciphertext, Base64.NO_WRAP)
    }

    private fun decrypt(stored: String): String? = try {
        val bytes = Base64.decode(stored, Base64.NO_WRAP)
        val iv = bytes.copyOfRange(0, GCM_IV_BYTES)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        String(cipher.doFinal(bytes, GCM_IV_BYTES, bytes.size - GCM_IV_BYTES), Charsets.UTF_8)
    } catch (e: Exception) {
        null
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "pania_secret_store"
        const val PREFS = "pania_secrets"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_IV_BYTES = 12
        const val GCM_TAG_BITS = 128
    }
}
