package app.pania.trailrecorder

import android.content.Context
import org.json.JSONObject
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Live numbers of the recording or tour in progress, for the status notification, the Android 16
 * Live Update and the home / lock screen widget.
 *
 * They are computed here, next to the GPS fixes, because with the screen off the webview is not
 * running. The last state is also written to SharedPreferences so the widget can read it.
 *
 * The webview hands over the starting context once, as JSON (see `LiveInfo` in background_recorder.ts):
 *
 *     {
 *       "mode": "recording" | "tour",
 *       "title": "Recording trail" | "<trail name>",
 *       "labels": { "distance": "Distance", "time": "Time", "climb": "Climb", "left": "Left", "arrival": "Arrival", "done": "Done" },
 *       "baseDistanceM": 0, "baseAscentM": 0, "baseElapsedMs": 0   // what a resumed recording already has
 *     }
 */
object LiveStats {
    private const val PREFS = "pania_live"
    private const val KEY = "snapshot"
    /** A snapshot not updated for this long belongs to a service that died without cleaning up. */
    const val STALE_MS = 10 * 60_000L

    data class Snapshot(
        /** "recording" or "tour". */
        val mode: String,
        val title: String,
        val labels: JSONObject,
        val distanceM: Double,
        val ascentM: Double,
        /** Wall-clock time at which the elapsed time would have been zero; elapsed = now - this. */
        val startedAtMs: Long,
        /** Tour only; -1 otherwise. */
        val remainingM: Double,
        val progressPct: Int,
        val etaMs: Long,
        val offTrack: Boolean,
        val updatedAtMs: Long,
    ) {
        val isTour get() = mode == "tour"
        fun label(key: String, fallback: String): String = labels.optString(key, fallback).ifEmpty { fallback }

        fun toJson(): String = JSONObject().apply {
            put("mode", mode)
            put("title", title)
            put("labels", labels)
            put("distanceM", distanceM)
            put("ascentM", ascentM)
            put("startedAtMs", startedAtMs)
            put("remainingM", remainingM)
            put("progressPct", progressPct)
            put("etaMs", etaMs)
            put("offTrack", offTrack)
            put("updatedAtMs", updatedAtMs)
        }.toString()

        companion object {
            fun fromJson(json: String): Snapshot {
                val o = JSONObject(json)
                return Snapshot(
                    mode = o.getString("mode"),
                    title = o.getString("title"),
                    labels = o.optJSONObject("labels") ?: JSONObject(),
                    distanceM = o.getDouble("distanceM"),
                    ascentM = o.getDouble("ascentM"),
                    startedAtMs = o.getLong("startedAtMs"),
                    remainingM = o.getDouble("remainingM"),
                    progressPct = o.getInt("progressPct"),
                    etaMs = o.getLong("etaMs"),
                    offTrack = o.getBoolean("offTrack"),
                    updatedAtMs = o.getLong("updatedAtMs"),
                )
            }
        }
    }

    private val session = LiveSession()

    /** Starts a session. Returns the first snapshot (nothing recorded yet). */
    @Synchronized
    fun begin(context: Context, liveJson: String?, guard: OffTrackGuard?): Snapshot =
        save(context, session.begin(liveJson, guard, System.currentTimeMillis()))

    /** Takes in one GPS fix and returns the updated snapshot. */
    @Synchronized
    fun onFix(context: Context, latitude: Double, longitude: Double, altitude: Double?, accuracy: Float?, timeMs: Long): Snapshot =
        save(context, session.onFix(latitude, longitude, altitude, accuracy, timeMs, System.currentTimeMillis()))

    /** Ends the session; widgets go back to their idle state. */
    @Synchronized
    fun end(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY).apply()
    }

    /** The current state, or null when nothing is being recorded or followed. */
    fun read(context: Context): Snapshot? {
        val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return null
        val snapshot = runCatching { Snapshot.fromJson(json) }.getOrNull() ?: return null
        return if (System.currentTimeMillis() - snapshot.updatedAtMs > STALE_MS) null else snapshot
    }

    private fun save(context: Context, snapshot: Snapshot): Snapshot {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, snapshot.toJson()).apply()
        return snapshot
    }
}

/**
 * The numbers of one recording or tour session, computed from GPS fixes. No Android types, so it
 * is unit tested on the JVM; [LiveStats] adds the persistence. Times are passed in, never read here.
 */
class LiveSession {
    private companion object {
        const val EARTH_RADIUS_M = 6_371_000.0
        /** Altitude changes below this are GPS noise (same rule as the app's trail stats). */
        const val ELEVATION_NOISE_M = 3.0
        /** Steps shorter than this are GPS jitter while standing still. */
        const val MIN_STEP_M = 2.0
        const val MAX_ACCURACY_M = 50f
        const val SPEED_WINDOW_MS = 10 * 60_000L
        const val MIN_SPEED_SPAN_MS = 60_000L
        /** Slower than this (m/s) counts as standing still: no arrival time. */
        const val MIN_SPEED_MS = 0.1
    }

    private var mode = "recording"
    private var title = ""
    private var labels = JSONObject()
    private var guard: OffTrackGuard? = null
    private var distanceM = 0.0
    private var ascentM = 0.0
    private var startedAtMs = 0L
    private var lastLat: Double? = null
    private var lastLon: Double? = null
    private var refAltitude: Double? = null
    private var remainingM = -1.0
    private var progressPct = -1
    private var etaMs = -1L
    private var offTrack = false
    private val progressSamples = ArrayDeque<Pair<Long, Double>>()

    fun begin(liveJson: String?, guard: OffTrackGuard?, nowMs: Long): LiveStats.Snapshot {
        val info = runCatching { JSONObject(liveJson ?: "") }.getOrNull() ?: JSONObject()
        this.guard = guard
        mode = if (guard != null) "tour" else info.optString("mode", "recording")
        title = info.optString("title", "").ifEmpty { guard?.title ?: "Pania" }
        labels = info.optJSONObject("labels") ?: JSONObject()
        distanceM = info.optDouble("baseDistanceM", 0.0)
        ascentM = info.optDouble("baseAscentM", 0.0)
        startedAtMs = nowMs - info.optLong("baseElapsedMs", 0L)
        lastLat = null
        lastLon = null
        refAltitude = null
        progressSamples.clear()
        offTrack = false
        if (guard != null) {
            remainingM = guard.totalLengthM
            progressPct = 0
        } else {
            remainingM = -1.0
            progressPct = -1
        }
        etaMs = -1L
        return snapshot(nowMs)
    }

    fun onFix(latitude: Double, longitude: Double, altitude: Double?, accuracy: Float?, timeMs: Long, nowMs: Long): LiveStats.Snapshot {
        val accurate = accuracy == null || accuracy <= MAX_ACCURACY_M
        if (accurate) {
            val la = lastLat
            val lo = lastLon
            if (la == null || lo == null) {
                lastLat = latitude
                lastLon = longitude
            } else {
                val step = haversine(la, lo, latitude, longitude)
                if (step >= MIN_STEP_M) {
                    distanceM += step
                    lastLat = latitude
                    lastLon = longitude
                }
            }
            if (altitude != null) {
                val ref = refAltitude
                if (ref == null) {
                    refAltitude = altitude
                } else if (altitude - ref >= ELEVATION_NOISE_M) {
                    ascentM += altitude - ref
                    refAltitude = altitude
                } else if (ref - altitude >= ELEVATION_NOISE_M) {
                    refAltitude = altitude
                }
            }
        }
        guard?.let { g ->
            val (offM, alongM) = g.project(latitude, longitude)
            val total = g.totalLengthM
            if (total > 0) {
                remainingM = max(0.0, total - alongM)
                progressPct = min(100, max(0, Math.round(alongM / total * 100).toInt()))
            }
            if (accurate) offTrack = offM > g.thresholdM
            // Pace only from time spent on the trail: progress while lost says nothing about it.
            if (accurate && offM <= g.thresholdM) {
                progressSamples.addLast(timeMs to alongM)
                while (progressSamples.size > 1 && timeMs - progressSamples.first().first > SPEED_WINDOW_MS) {
                    progressSamples.removeFirst()
                }
            }
            etaMs = estimateArrival(remainingM, nowMs)
        }
        return snapshot(nowMs)
    }

    private fun estimateArrival(remaining: Double, nowMs: Long): Long {
        val first = progressSamples.firstOrNull() ?: return -1L
        val last = progressSamples.last()
        val span = last.first - first.first
        if (span < MIN_SPEED_SPAN_MS) return -1L
        val speed = (last.second - first.second) / (span / 1000.0)
        if (speed < MIN_SPEED_MS) return -1L
        return nowMs + (remaining / speed * 1000).toLong()
    }

    private fun snapshot(nowMs: Long) = LiveStats.Snapshot(
        mode = mode,
        title = title,
        labels = labels,
        distanceM = distanceM,
        ascentM = ascentM,
        startedAtMs = startedAtMs,
        remainingM = remainingM,
        progressPct = progressPct,
        etaMs = etaMs,
        offTrack = offTrack,
        updatedAtMs = nowMs,
    )

    private fun haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val h = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * EARTH_RADIUS_M * asin(sqrt(h))
    }
}
