package app.pania.trailrecorder

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/** Shares the downloaded APK with the installer, under an authority of its own. */
class UpdateFileProvider : FileProvider()

/**
 * The Android-only half of in-app updates: the install permission, the folder the installer may
 * read from, and the installer screen. The download itself is done in Rust (`updater/download.rs`),
 * which also validates the address and where redirects go.
 *
 * Android still asks the user to confirm the install and only installs an APK signed with the
 * same key as the installed app.
 */
class AppInstaller(private val context: Context, private val activity: () -> Activity?) {
    private val updateDir get() = File(context.cacheDir, "updates")

    fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    fun openSettings() {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    /** The folder Rust downloads into. Created, and emptied so only the latest download is kept. */
    fun prepareUpdateDir(): String {
        val dir = updateDir.apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        return dir.absolutePath
    }

    fun install(path: String) {
        val apk = File(path).canonicalFile
        // Only ever install something from the update folder.
        check(apk.parentFile == updateDir.canonicalFile && apk.isFile) { "unexpected file" }
        checkIsThisApp(apk)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        (activity() ?: context).startActivity(intent)
    }

    @Suppress("DEPRECATION")
    private fun checkIsThisApp(apk: File) {
        val info = context.packageManager.getPackageArchiveInfo(apk.path, 0)
        checkNotNull(info) { "the download is not a valid APK" }
        check(info.packageName == context.packageName) { "the download is a different app" }
    }
}
