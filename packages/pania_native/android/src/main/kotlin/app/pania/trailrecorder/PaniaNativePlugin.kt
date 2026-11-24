package app.pania.trailrecorder

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * The Android half of Pania, exposed to Dart over one method channel (`pania/native`).
 *
 * - `recorder.*`: the foreground service that records GPS with the screen off, plus the live
 *   stats notification and widget (see [RecorderService]).
 * - `secrets.*`: Keystore-backed secret storage (see [SecretStore]). Only Rust asks for secrets.
 * - `installer.*`: the Android-only part of in-app updates (see [AppInstaller]). The download
 *   itself happens in Rust.
 */
class PaniaNativePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null

    private val secrets by lazy { SecretStore(context) }
    private val installer by lazy { AppInstaller(context) { activity } }

    override fun onAttachedToEngine(flutter: FlutterPlugin.FlutterPluginBinding) {
        context = flutter.applicationContext
        channel = MethodChannel(flutter.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutter: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) {
        activity = b.activity
        binding = b
        b.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = onAttachedToActivity(b)

    override fun onDetachedFromActivity() {
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "recorder.start" -> startRecorder(call, result)
                "recorder.stop" -> {
                    context.stopService(Intent(context, RecorderService::class.java))
                    OffTrackGuard.clear(context)
                    PointBuffer.running = false
                    result.success(null)
                }
                "recorder.takePoints" -> result.success(
                    mapOf(
                        "points" to PointBuffer.take(context).map { it.toMap() },
                        "running" to PointBuffer.running,
                        "error" to PointBuffer.lastError,
                    ),
                )
                "recorder.requestPermissions" -> requestNotificationPermission(result)
                "recorder.liveUpdateStatus" -> result.success(liveUpdateStatus())
                "recorder.openLiveUpdateSettings" -> openLiveUpdateSettings(result)

                "secrets.get" -> result.success(secrets.get(call.argument<String>("key")!!))
                "secrets.set" -> {
                    secrets.set(call.argument<String>("key")!!, call.argument<String>("value")!!)
                    result.success(null)
                }
                "secrets.delete" -> {
                    secrets.delete(call.argument<String>("key")!!)
                    result.success(null)
                }

                "installer.canInstall" -> result.success(installer.canInstall())
                "installer.openSettings" -> {
                    installer.openSettings()
                    result.success(null)
                }
                "installer.updateDir" -> result.success(installer.prepareUpdateDir())
                "installer.install" -> {
                    installer.install(call.argument<String>("path")!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("pania_native", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun startRecorder(call: MethodCall, result: MethodChannel.Result) {
        PointBuffer.lastError = null
        val intervalMs = (call.argument<Number>("intervalMs") ?: 5_000).toLong()
        val guardJson = call.argument<String>("guardJson")
        val liveJson = call.argument<String>("liveJson")
        // The trail can be thousands of points, too big for an Intent extra, so it goes via a file.
        val guarding = guardJson != null && OffTrackGuard.save(context, guardJson)
        if (!guarding) OffTrackGuard.clear(context)
        val intent = Intent(context, RecorderService::class.java)
            .putExtra(RecorderService.EXTRA_INTERVAL_MS, intervalMs)
            .putExtra(RecorderService.EXTRA_GUARD, guarding)
            .putExtra(RecorderService.EXTRA_LIVE, liveJson)
        ContextCompat.startForegroundService(context, intent)
        result.success(null)
    }

    /** Needed on Android 13+ to show the recording notification; recording works without it. */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        val act = activity
        val granted = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted || act == null || pendingPermission != null) {
            result.success(granted)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(act, arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_CODE)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray): Boolean {
        if (code != PERMISSION_CODE) return false
        pendingPermission?.success(results.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pendingPermission = null
        return true
    }

    /**
     * Whether this Android has Live Updates (16+) and whether the person left them on for Pania.
     * Without them the status notification still shows the stats, just not as a Live Update.
     */
    private fun liveUpdateStatus(): Map<String, Boolean> {
        val supported = Build.VERSION.SDK_INT >= 36
        // `canPostPromotedNotifications` is new: look it up so an older build of Android 16 cannot crash us.
        val enabled = supported && runCatching {
            val manager = context.getSystemService(NotificationManager::class.java)
            NotificationManager::class.java.getMethod("canPostPromotedNotifications").invoke(manager) as Boolean
        }.getOrDefault(true)
        return mapOf("supported" to supported, "enabled" to enabled)
    }

    /** Opens the system screen where Live Updates are turned on for Pania (or its notification settings). */
    private fun openLiveUpdateSettings(result: MethodChannel.Result) {
        val action = runCatching {
            Settings::class.java.getField("ACTION_MANAGE_APP_PROMOTED_NOTIFICATIONS").get(null) as String
        }.getOrNull()
        val promoted = action?.let { Intent(it).setData(Uri.fromParts("package", context.packageName, null)) }
        val fallback = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        for (intent in listOfNotNull(promoted, fallback)) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
                return
            } catch (e: Exception) {
                // Try the next screen.
            }
        }
        result.error("pania_native", "Could not open the settings.", null)
    }

    private companion object {
        const val CHANNEL = "pania/native"
        const val PERMISSION_CODE = 7301
    }
}
