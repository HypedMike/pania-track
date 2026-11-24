package app.pania.trailrecorder

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews

/**
 * Widget with the live stats of the recording or tour in progress.
 *
 * It is a plain AppWidget: the service pushes an update on every few GPS fixes, and the elapsed
 * time ticks by itself (a Chronometer inside RemoteViews), so it needs no timer of its own.
 */
class LiveWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, manager, appWidgetIds)
    }

    companion object {
        /** Redraws every placed widget from the latest [LiveStats] snapshot. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, LiveWidgetProvider::class.java))
            if (ids.isNotEmpty()) render(context, manager, ids)
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val views = RemoteViews(context.packageName, R.layout.pania_widget_live)
            val snapshot = LiveStats.read(context)

            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                it.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                views.setOnClickPendingIntent(
                    R.id.pania_w_root,
                    PendingIntent.getActivity(context, 2, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
                )
            }

            if (snapshot == null) {
                views.setTextViewText(R.id.pania_w_title, "Pania")
                views.setTextViewText(R.id.pania_w_idle, context.getString(R.string.pania_widget_idle))
                views.setViewVisibility(R.id.pania_w_idle, View.VISIBLE)
                views.setViewVisibility(R.id.pania_w_cells, View.GONE)
                views.setViewVisibility(R.id.pania_w_progress, View.GONE)
            } else {
                views.setViewVisibility(R.id.pania_w_idle, View.GONE)
                views.setViewVisibility(R.id.pania_w_cells, View.VISIBLE)
                bind(views, snapshot)
            }
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun bind(views: RemoteViews, s: LiveStats.Snapshot) {
            views.setTextViewText(R.id.pania_w_title, (if (s.offTrack) "⚠ " else "") + s.title)
            val chronoBase = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - s.startedAtMs)

            if (s.isTour) {
                views.setTextViewText(R.id.pania_w_label1, s.label("left", "Left"))
                views.setTextViewText(R.id.pania_w_value1, LiveFormat.distance(maxOf(0.0, s.remainingM)))
                views.setTextViewText(R.id.pania_w_label2, s.label("arrival", "Arrival"))
                views.setTextViewText(R.id.pania_w_value2, if (s.etaMs > 0) LiveFormat.clock(s.etaMs) else "–")
                views.setViewVisibility(R.id.pania_w_value2, View.VISIBLE)
                views.setViewVisibility(R.id.pania_w_chrono2, View.GONE)
                views.setTextViewText(R.id.pania_w_label3, s.label("done", "Done"))
                views.setTextViewText(R.id.pania_w_value3, "${s.progressPct}%")
                views.setViewVisibility(R.id.pania_w_progress, View.VISIBLE)
                views.setProgressBar(R.id.pania_w_progress, 100, maxOf(0, s.progressPct), false)
            } else {
                views.setTextViewText(R.id.pania_w_label1, s.label("distance", "Distance"))
                views.setTextViewText(R.id.pania_w_value1, LiveFormat.distance(s.distanceM))
                views.setTextViewText(R.id.pania_w_label2, s.label("time", "Time"))
                views.setViewVisibility(R.id.pania_w_value2, View.GONE)
                views.setViewVisibility(R.id.pania_w_chrono2, View.VISIBLE)
                views.setChronometer(R.id.pania_w_chrono2, chronoBase, null, true)
                views.setTextViewText(R.id.pania_w_label3, s.label("climb", "Climb"))
                views.setTextViewText(R.id.pania_w_value3, LiveFormat.climb(s.ascentM))
                views.setViewVisibility(R.id.pania_w_progress, View.GONE)
            }
        }
    }
}
