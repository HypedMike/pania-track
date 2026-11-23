package app.pania.trailrecorder

import android.content.Context
import org.json.JSONObject
import java.io.File
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * Watches the GPS fixes of a tour and tells when the person has wandered off the trail.
 *
 * It lives in the recording service so that it keeps working with the screen off, where the
 * webview is not running. The webview hands over the trail once, as a JSON file:
 *
 *     {
 *       "thresholdM": 50,
 *       "track": [[lat, lon], ...],
 *       "title": "You left the trail",
 *       "text": "You are {m} m from the trail. Tap to open the map.",
 *     }
 */
class OffTrackGuard private constructor(
    private val lat: DoubleArray,
    private val lon: DoubleArray,
    private val thresholdM: Double,
    val title: String,
    private val textTemplate: String,
) {
    enum class Verdict { NONE, OFF_TRACK, STILL_OFF_TRACK, BACK_ON_TRACK }

    private var consecutiveOff = 0
    private var offTrack = false
    private var lastAlertAt = 0L

    /** Distance in meters from a position to the nearest point of the trail. */
    fun distanceToTrail(latitude: Double, longitude: Double): Double {
        if (lat.isEmpty()) return Double.MAX_VALUE
        // Flat projection around the position: far more than accurate enough over a few km.
        val ky = METERS_PER_DEGREE
        val kx = METERS_PER_DEGREE * cos(Math.toRadians(latitude))
        var best = Double.MAX_VALUE
        for (i in 0 until lat.size - 1) {
            val ax = (lon[i] - longitude) * kx
            val ay = (lat[i] - latitude) * ky
            val bx = (lon[i + 1] - longitude) * kx
            val by = (lat[i + 1] - latitude) * ky
            val dx = bx - ax
            val dy = by - ay
            val len2 = dx * dx + dy * dy
            val f = if (len2 > 0) max(0.0, min(1.0, -(ax * dx + ay * dy) / len2)) else 0.0
            best = min(best, hypot(ax + dx * f, ay + dy * f))
        }
        if (lat.size == 1) best = hypot((lon[0] - longitude) * kx, (lat[0] - latitude) * ky)
        return best
    }

    /**
     * Takes one fix and says whether to raise or clear the alert. A single stray fix does not
     * count: two in a row beyond the threshold do. A fix less accurate than the threshold says
     * nothing either way, and once alerted the person must come well back (70%) to be cleared.
     */
    fun onFix(latitude: Double, longitude: Double, accuracyM: Float?, nowMs: Long): Pair<Verdict, Double> {
        val distance = distanceToTrail(latitude, longitude)
        if (accuracyM != null && accuracyM > thresholdM) return Verdict.NONE to distance

        if (distance > thresholdM) {
            consecutiveOff++
            if (consecutiveOff < 2) return Verdict.NONE to distance
            if (!offTrack) {
                offTrack = true
                lastAlertAt = nowMs
                return Verdict.OFF_TRACK to distance
            }
            if (nowMs - lastAlertAt >= REPEAT_MS) {
                lastAlertAt = nowMs
                return Verdict.STILL_OFF_TRACK to distance
            }
        } else if (distance < thresholdM * 0.7) {
            consecutiveOff = 0
            if (offTrack) {
                offTrack = false
                return Verdict.BACK_ON_TRACK to distance
            }
        }
        return Verdict.NONE to distance
    }

    fun text(distanceM: Double): String = textTemplate.replace("{m}", (Math.round(distanceM / 5.0) * 5).toString())

    companion object {
        private const val FILE_NAME = "tour_guard.json"
        private const val METERS_PER_DEGREE = 111_195.0
        /** While still off the trail, remind every two minutes. */
        private const val REPEAT_MS = 120_000L

        /** Stores the guard settings for the service to read. Returns false if they are unusable. */
        fun save(context: Context, json: String): Boolean = try {
            parse(json)
            File(context.filesDir, FILE_NAME).writeText(json)
            true
        } catch (e: Exception) {
            false
        }

        fun clear(context: Context) {
            runCatching { File(context.filesDir, FILE_NAME).delete() }
        }

        fun load(context: Context): OffTrackGuard? = try {
            parse(File(context.filesDir, FILE_NAME).readText())
        } catch (e: Exception) {
            null
        }

        private fun parse(json: String): OffTrackGuard {
            val o = JSONObject(json)
            val track = o.getJSONArray("track")
            require(track.length() > 0) { "Empty trail" }
            val lat = DoubleArray(track.length())
            val lon = DoubleArray(track.length())
            for (i in 0 until track.length()) {
                val p = track.getJSONArray(i)
                lat[i] = p.getDouble(0)
                lon[i] = p.getDouble(1)
            }
            return OffTrackGuard(
                lat,
                lon,
                o.getDouble("thresholdM"),
                o.optString("title", "You left the trail"),
                o.optString("text", "You are {m} m from the trail."),
            )
        }
    }
}
