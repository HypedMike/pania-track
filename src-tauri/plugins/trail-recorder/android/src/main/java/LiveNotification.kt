package app.pania.trailrecorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import java.text.DateFormat
import java.util.Date

/** Number formatting shared by the notification and the widget. */
object LiveFormat {
    fun distance(m: Double): String = if (m < 1000) "${Math.round(m)} m" else String.format("%.1f km", m / 1000)
    fun climb(m: Double): String = "${Math.round(m)} m"
    fun clock(ms: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))
}

/**
 * The persistent status notification with live stats.
 *
 * It is public on the lock screen, so the numbers show without unlocking. On Android 16 it asks
 * to be promoted to a Live Update (status bar chip, lock screen and always-on display); older
 * versions simply show it as an ongoing notification.
 */
object LiveNotification {
    /** A new channel: the lock screen visibility of an existing one cannot be changed. */
    const val CHANNEL_ID = "trail_live"

    private class Content(
        val title: String,
        val text: String,
        val bigText: String,
        /** -1 when there is no progress to show. */
        val progressPct: Int,
        /** Short text for the Android 16 status bar chip. */
        val chip: String,
        val startedAtMs: Long,
    )

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Trail status", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Live stats of the trail being recorded or followed"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
    }

    fun build(context: Context, snapshot: LiveStats.Snapshot?): Notification {
        ensureChannel(context)
        val content = content(snapshot)
        val tap = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            it.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        if (Build.VERSION.SDK_INT >= 36) {
            // The Live Update API is new and not on every build: never lose the notification over it.
            try {
                return Promoted.build(context, content, tap)
            } catch (e: Throwable) {
                // Fall through to the standard notification.
            }
        }
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(content.title)
            .setContentText(content.text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content.bigText))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setWhen(content.startedAtMs)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(tap)
        if (content.progressPct >= 0) builder.setProgress(100, content.progressPct, false)
        return builder.build()
    }

    private fun content(s: LiveStats.Snapshot?): Content {
        if (s == null) {
            return Content("Recording trail", "Pania is saving your track. Tap to open.", "Pania is saving your track. Tap to open.", -1, "", System.currentTimeMillis())
        }
        val warn = if (s.offTrack) "⚠ " else ""
        if (!s.isTour) {
            val distance = LiveFormat.distance(s.distanceM)
            val climb = "${s.label("climb", "Climb")} ${LiveFormat.climb(s.ascentM)}"
            return Content(
                title = s.title,
                text = "$distance · $climb",
                bigText = "${s.label("distance", "Distance")}: $distance\n$climb",
                progressPct = -1,
                chip = distance.replace(" ", ""),
                startedAtMs = s.startedAtMs,
            )
        }
        val left = LiveFormat.distance(maxOf(0.0, s.remainingM))
        val arrival = if (s.etaMs > 0) LiveFormat.clock(s.etaMs) else "–"
        val text = "$warn$left ${s.label("left", "left").lowercase()} · ${s.progressPct}%"
        return Content(
            title = s.title,
            text = text,
            bigText = "$warn${s.label("left", "Left")}: $left\n${s.label("arrival", "Arrival")}: $arrival\n${s.label("done", "Done")}: ${s.progressPct}%",
            progressPct = s.progressPct,
            chip = "${s.progressPct}%",
            startedAtMs = s.startedAtMs,
        )
    }

    /**
     * Asks for promotion to a Live Update. The guide names both `Builder.setRequestPromotedOngoing` and
     * the `EXTRA_REQUEST_PROMOTED_ONGOING` extra; which one a given build has is not certain, so
     * try the method first and fall back to the extra. Reflection keeps the build from breaking.
     */
    private fun requestPromotion(builder: Notification.Builder) {
        if (callIfPresent(builder, "setRequestPromotedOngoing", Boolean::class.javaPrimitiveType!!, true)) return
        val key = runCatching { Notification::class.java.getField("EXTRA_REQUEST_PROMOTED_ONGOING").get(null) as String }
            .getOrDefault("android.requestPromotedOngoing")
        builder.addExtras(Bundle().apply { putBoolean(key, true) })
    }

    private fun callIfPresent(builder: Notification.Builder, name: String, type: Class<*>, value: Any): Boolean =
        try {
            Notification.Builder::class.java.getMethod(name, type).invoke(builder, value)
            true
        } catch (e: Exception) {
            false
        }

    /** Android 16 (API 36) Live Update: a progress-style notification that asks to be promoted. */
    private object Promoted {
        fun build(context: Context, c: Content, tap: PendingIntent?): Notification {
            val style = Notification.ProgressStyle()
            if (c.progressPct >= 0) {
                style.setProgress(c.progressPct)
                style.setProgressSegments(listOf(Notification.ProgressStyle.Segment(100)))
            } else {
                style.setProgressIndeterminate(true)
            }
            val builder = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle(c.title)
                .setContentText(c.text)
                .setStyle(style)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setWhen(c.startedAtMs)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setContentIntent(tap)
            requestPromotion(builder)
            // Compact "chip" text; the guide suggests at most 7 characters.
            if (c.chip.isNotEmpty()) callIfPresent(builder, "setShortCriticalText", String::class.java, c.chip)
            return builder.build()
        }
    }
}
