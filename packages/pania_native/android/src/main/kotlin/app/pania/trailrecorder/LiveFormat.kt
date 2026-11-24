package app.pania.trailrecorder

import java.text.DateFormat
import java.util.Date

/** Number formatting shared by the notification and the widget. */
object LiveFormat {
    fun distance(m: Double): String = if (m < 1000) "${Math.round(m)} m" else String.format("%.1f km", m / 1000)
    fun climb(m: Double): String = "${Math.round(m)} m"
    fun clock(ms: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))
}
