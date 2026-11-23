package app.pania.trailrecorder

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Foreground service that receives GPS fixes and stores them in [PointBuffer].
 * A foreground service of type "location" keeps getting fixes while the screen is off
 * or the app is in the background, as long as its notification is shown.
 */
class RecorderService : Service() {
    companion object {
        const val EXTRA_INTERVAL_MS = "intervalMs"
        /** True when the start request came with off-track settings for a tour. */
        const val EXTRA_GUARD = "guard"
        /** JSON with the title, labels and starting numbers for the live stats (see [LiveStats]). */
        const val EXTRA_LIVE = "live"
        private const val ALERT_CHANNEL_ID = "tour_off_track"
        private const val NOTIFICATION_ID = 4711
        private const val ALERT_NOTIFICATION_ID = 4712
        /** The notification and widget are redrawn at most this often. */
        private const val NOTIFICATION_REFRESH_MS = 2_000L
        private const val WIDGET_REFRESH_MS = 5_000L
    }

    /** Set while a tour is running; null while recording a trail. */
    @Volatile private var guard: OffTrackGuard? = null

    private val client by lazy { LocationServices.getFusedLocationProviderClient(this) }
    private var updatesActive = false
    private var lastNotificationAt = 0L
    private var lastWidgetAt = 0L

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (location in result.locations) {
                PointBuffer.add(
                    applicationContext,
                    RecordedPoint(
                        latitude = location.latitude,
                        longitude = location.longitude,
                        altitude = if (location.hasAltitude()) location.altitude else null,
                        accuracy = if (location.hasAccuracy()) location.accuracy else null,
                        time = location.time,
                    ),
                )
                guard?.let { checkOffTrack(it, location) }
                val snapshot = LiveStats.onFix(
                    applicationContext,
                    location.latitude,
                    location.longitude,
                    if (location.hasAltitude()) location.altitude else null,
                    if (location.hasAccuracy()) location.accuracy else null,
                    location.time,
                )
                refreshLiveViews(snapshot)
            }
            PointBuffer.lastError = null
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val interval = intent?.getLongExtra(EXTRA_INTERVAL_MS, 5_000L) ?: 5_000L
        guard = if (intent?.getBooleanExtra(EXTRA_GUARD, false) == true) OffTrackGuard.load(this) else null
        val liveSnapshot = LiveStats.begin(this, intent?.getStringExtra(EXTRA_LIVE), guard)

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) {
            PointBuffer.lastError = "Location permission was denied."
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            } else {
                0
            }
            ServiceCompat.startForeground(this, NOTIFICATION_ID, LiveNotification.build(this, liveSnapshot), type)
            LiveWidgetProvider.refresh(this)
        } catch (e: Exception) {
            // Android refuses a location foreground service started while the app is in the background.
            PointBuffer.lastError = "Could not start background recording: ${e.message}"
            LiveStats.end(this)
            stopSelf()
            return START_NOT_STICKY
        }

        if (updatesActive) client.removeLocationUpdates(callback)
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, interval)
            .setMinUpdateIntervalMillis(interval)
            .setWaitForAccurateLocation(false)
            .build()
        try {
            client.requestLocationUpdates(request, callback, Looper.getMainLooper())
            updatesActive = true
            PointBuffer.running = true
        } catch (e: SecurityException) {
            PointBuffer.lastError = "Location permission was denied."
            stopSelf()
        }

        // Not sticky: a restart by the system would happen in the background, where Android
        // does not allow starting a location service. The app restarts it when reopened.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (updatesActive) client.removeLocationUpdates(callback)
        updatesActive = false
        if (guard != null) getSystemService(NotificationManager::class.java).cancel(ALERT_NOTIFICATION_ID)
        guard = null
        PointBuffer.running = false
        LiveStats.end(this)
        LiveWidgetProvider.refresh(this)
        super.onDestroy()
    }

    /** Keeps the status notification and the widget in step with the latest numbers. */
    private fun refreshLiveViews(snapshot: LiveStats.Snapshot) {
        val now = System.currentTimeMillis()
        if (now - lastNotificationAt >= NOTIFICATION_REFRESH_MS) {
            lastNotificationAt = now
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, LiveNotification.build(this, snapshot))
        }
        if (now - lastWidgetAt >= WIDGET_REFRESH_MS) {
            lastWidgetAt = now
            LiveWidgetProvider.refresh(this)
        }
    }

    private fun checkOffTrack(guard: OffTrackGuard, location: android.location.Location) {
        val (verdict, distance) = guard.onFix(
            location.latitude,
            location.longitude,
            if (location.hasAccuracy()) location.accuracy else null,
            System.currentTimeMillis(),
        )
        when (verdict) {
            OffTrackGuard.Verdict.OFF_TRACK, OffTrackGuard.Verdict.STILL_OFF_TRACK -> showOffTrackAlert(guard, distance)
            OffTrackGuard.Verdict.BACK_ON_TRACK ->
                getSystemService(NotificationManager::class.java).cancel(ALERT_NOTIFICATION_ID)
            OffTrackGuard.Verdict.NONE -> Unit
        }
    }

    /** A loud notification, unlike the quiet "recording" one, so the person notices it in a pocket. */
    private fun showOffTrackAlert(guard: OffTrackGuard, distanceM: Double) {
        // Without the notification permission (Android 13+) Android drops the notification anyway.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(ALERT_CHANNEL_ID, "Off-track alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Shown when you leave the trail you are following"
                    enableVibration(true)
                    setShowBadge(false)
                },
            )
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val tap = launch?.let {
            PendingIntent.getActivity(this, 1, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val text = guard.text(distanceM)
        manager.notify(
            ALERT_NOTIFICATION_ID,
            NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setContentTitle(guard.title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .setContentIntent(tap)
                .build(),
        )
    }
}
