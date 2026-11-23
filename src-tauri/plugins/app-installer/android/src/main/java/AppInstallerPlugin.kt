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

class UpdateFileProvider : FileProvider()

@InvokeArg
class InstallArgs {
    lateinit var path: String
}

/**
 * The Android-only half of in-app updates: the install permission, the folder the installer may
 * read from, and the installer screen. The download itself is done in Rust (`download.rs`), which
 * also validates the address and where redirects go.
 *
 * Android still asks the user to confirm the install and only installs an APK signed with the
 * same key as the installed app.
 */
@TauriPlugin
class AppInstallerPlugin(private val activity: Activity) : Plugin(activity) {
    private val context get() = activity.applicationContext
    private val updateDir get() = File(context.cacheDir, "updates")

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

    /** The folder Rust downloads into. Created, and emptied so only the latest download is kept. */
    @Command
    fun updateDir(invoke: Invoke) {
        try {
            val dir = updateDir.apply { mkdirs() }
            dir.listFiles()?.forEach { it.delete() }
            val result = JSObject()
            result.put("path", dir.absolutePath)
            invoke.resolve(result)
        } catch (e: Exception) {
            invoke.reject("Could not prepare the update folder: ${e.message}")
        }
    }

    @Command
    fun install(invoke: Invoke) {
        try {
            val args = invoke.parseArgs(InstallArgs::class.java)
            val apk = File(args.path).canonicalFile
            // Only ever install something from the update folder.
            check(apk.parentFile == updateDir.canonicalFile && apk.isFile) { "unexpected file" }
            checkIsThisApp(apk)
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.runOnUiThread { activity.startActivity(intent) }
            invoke.resolve()
        } catch (e: Exception) {
            invoke.reject("Could not start the installer: ${e.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun checkIsThisApp(apk: File) {
        val info = context.packageManager.getPackageArchiveInfo(apk.path, 0)
        checkNotNull(info) { "the download is not a valid APK" }
        check(info.packageName == context.packageName) { "the download is a different app" }
    }
}
