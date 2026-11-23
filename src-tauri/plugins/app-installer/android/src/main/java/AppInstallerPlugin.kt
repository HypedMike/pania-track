package app.pania.appinstaller

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class UpdateFileProvider : FileProvider()

@InvokeArg
class DownloadArgs {
    lateinit var url: String
}

/**
 * Downloads a release APK into the app cache and opens Android's installer on it.
 *
 * The address was already checked in Rust (`url.rs`); this re-checks where redirects end up,
 * and that the file really is an APK of this app. Android itself still asks the user to confirm
 * and only installs an APK signed with the same key as the installed app.
 */
@TauriPlugin
class AppInstallerPlugin(private val activity: Activity) : Plugin(activity) {
    private val context get() = activity.applicationContext

    @Command
    fun canInstall(invoke: Invoke) {
        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            context.packageManager.canRequestPackageInstalls()
        val result = JSObject()
        result.put("allowed", allowed)
        invoke.resolve(result)
    }

    @Command
    fun openInstallSettings(invoke: Invoke) {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}"),
            )
            activity.runOnUiThread { activity.startActivity(intent) }
            invoke.resolve()
        } catch (e: Exception) {
            invoke.reject("Could not open the settings: ${e.message}")
        }
    }

    @Command
    fun downloadAndInstall(invoke: Invoke) {
        val args = invoke.parseArgs(DownloadArgs::class.java)
        // Off the main thread: the download can take a while.
        Thread {
            try {
                val apk = download(args.url)
                checkIsThisApp(apk)
                install(apk)
                invoke.resolve()
            } catch (e: Exception) {
                invoke.reject("Update failed: ${e.message}")
            }
        }.start()
    }

    private fun download(address: String): File {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() } // only ever keep the latest download
        val target = File(dir, "pania-update.apk")

        val connection = URL(address).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.instanceFollowRedirects = true
        try {
            connection.connect()
            check(connection.responseCode == HttpURLConnection.HTTP_OK) { "server answered ${connection.responseCode}" }
            // Redirects must stay on GitHub over https (release assets are served from its CDN).
            val finalUrl = connection.url
            val host = finalUrl.host
            check(finalUrl.protocol == "https" && (host == "github.com" || host.endsWith(".githubusercontent.com"))) {
                "unexpected download host"
            }
            var total = 0L
            connection.inputStream.use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        total += n
                        check(total <= MAX_APK_BYTES) { "file is larger than expected" }
                        output.write(buffer, 0, n)
                    }
                }
            }
            check(total > 0) { "empty download" }
        } catch (e: Exception) {
            target.delete()
            throw e
        } finally {
            connection.disconnect()
        }
        return target
    }

    @Suppress("DEPRECATION")
    private fun checkIsThisApp(apk: File) {
        val info = context.packageManager.getPackageArchiveInfo(apk.path, 0)
        checkNotNull(info) { "the download is not a valid APK" }
        check(info.packageName == context.packageName) { "the download is a different app" }
    }

    private fun install(apk: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.runOnUiThread { activity.startActivity(intent) }
    }

    private companion object {
        const val MAX_APK_BYTES = 200L * 1024 * 1024
    }
}
