package app.pania.trailrecorder

import android.Manifest
import android.app.Notification
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
        private const val CHANNEL_ID = "trail_recording"
        private const val NOTIFICATION_ID = 4711
    }

    private val client by lazy { LocationServices.getFusedLocationProviderClient(this) }
    private var updatesActive = false

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
            }
            PointBuffer.lastError = null
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val interval = intent?.getLongExtra(EXTRA_INTERVAL_MS, 5_000L) ?: 5_000L

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
            ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(), type)
        } catch (e: Exception) {
            // Android refuses a location foreground service started while the app is in the background.
            PointBuffer.lastError = "Could not start background recording: ${e.message}"
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
        PointBuffer.running = false
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Trail recording", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while a trail is being recorded"
                    setShowBadge(false)
                },
            )
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val tap = launch?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Recording trail")
            .setContentText("pania is saving your track. Tap to open.")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(tap)
            .build()
    }
}
