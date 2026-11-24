package app.pania.trailrecorder

import android.content.Context
import org.json.JSONObject
import java.io.File

data class RecordedPoint(
    val latitude: Double,
    val longitude: Double,
    val altitude: Double?,
    val accuracy: Float?,
    val time: Long,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("latitude", latitude)
        put("longitude", longitude)
        put("altitude", altitude ?: JSONObject.NULL)
        put("accuracy", accuracy?.toDouble() ?: JSONObject.NULL)
        put("time", time)
    }

    /** The shape sent to Dart over the method channel. */
    fun toMap(): Map<String, Any?> = mapOf(
        "latitude" to latitude,
        "longitude" to longitude,
        "altitude" to altitude,
        "accuracy" to accuracy?.toDouble(),
        "time" to time,
    )

    companion object {
        fun fromJson(o: JSONObject) = RecordedPoint(
            latitude = o.getDouble("latitude"),
            longitude = o.getDouble("longitude"),
            altitude = if (o.isNull("altitude")) null else o.getDouble("altitude"),
            accuracy = if (o.isNull("accuracy")) null else o.getDouble("accuracy").toFloat(),
            time = o.getLong("time"),
        )
    }
}

/**
 * Points recorded by [RecorderService] that the app has not collected yet.
 *
 * Every point is also appended to a file, so points survive if Android kills the process
 * (or the Flutter engine is recreated) before the app collects them.
 */
object PointBuffer {
    private const val FILE_NAME = "trail_recorder_buffer.jsonl"
    private val points = mutableListOf<RecordedPoint>()
    private var file: File? = null

    @Volatile var running = false
    @Volatile var lastError: String? = null

    @Synchronized
    private fun ensureLoaded(context: Context) {
        if (file != null) return
        val f = File(context.filesDir, FILE_NAME)
        file = f
        if (f.exists()) {
            f.forEachLine { line ->
                runCatching { points.add(RecordedPoint.fromJson(JSONObject(line))) }
            }
        }
    }

    @Synchronized
    fun add(context: Context, point: RecordedPoint) {
        ensureLoaded(context)
        points.add(point)
        runCatching { file?.appendText(point.toJson().toString() + "\n") }
    }

    /** Returns every buffered point and clears the buffer. */
    @Synchronized
    fun take(context: Context): List<RecordedPoint> {
        ensureLoaded(context)
        val taken = points.toList()
        points.clear()
        runCatching { file?.writeText("") }
        return taken
    }
}
