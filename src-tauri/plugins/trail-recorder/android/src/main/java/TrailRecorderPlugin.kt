package app.pania.trailrecorder

import android.Manifest
import android.app.Activity
import android.content.Intent
import androidx.core.content.ContextCompat
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.Permission
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSArray
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin

@InvokeArg
class StartOptions {
    var intervalMs: Long = 5_000

    /** Off-track alert settings for a tour (see [OffTrackGuard]); null when recording a trail. */
    var guardJson: String? = null

    /** Title, labels and starting numbers of the live stats (see [LiveStats]). */
    var liveJson: String? = null
}

@TauriPlugin(
    permissions = [
        // Needed on Android 13+ to show the recording notification. Recording works without it,
        // but the user would not see that it is running.
        Permission(strings = [Manifest.permission.POST_NOTIFICATIONS], alias = "notifications"),
    ],
)
class TrailRecorderPlugin(private val activity: Activity) : Plugin(activity) {
    private val context get() = activity.applicationContext

    @Command
    fun start(invoke: Invoke) {
        val options = invoke.parseArgs(StartOptions::class.java)
        PointBuffer.lastError = null
        // The trail can be thousands of points, too big for an Intent extra, so it goes via a file.
        val guardJson = options.guardJson
        val guarding = guardJson != null && OffTrackGuard.save(context, guardJson)
        if (!guarding) OffTrackGuard.clear(context)
        val intent = Intent(context, RecorderService::class.java)
            .putExtra(RecorderService.EXTRA_INTERVAL_MS, options.intervalMs)
            .putExtra(RecorderService.EXTRA_GUARD, guarding)
            .putExtra(RecorderService.EXTRA_LIVE, options.liveJson)
        try {
            ContextCompat.startForegroundService(context, intent)
            invoke.resolve()
        } catch (e: Exception) {
            invoke.reject("Could not start recording: ${e.message}")
        }
    }

    @Command
    fun stop(invoke: Invoke) {
        context.stopService(Intent(context, RecorderService::class.java))
        OffTrackGuard.clear(context)
        PointBuffer.running = false
        invoke.resolve()
    }

    @Command
    fun takePoints(invoke: Invoke) {
        val points = JSArray()
        for (p in PointBuffer.take(context)) points.put(p.toJson())
        val result = JSObject()
        result.put("points", points)
        result.put("running", PointBuffer.running)
        result.put("error", PointBuffer.lastError)
        invoke.resolve(result)
    }
}
