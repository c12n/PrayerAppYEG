package com.c12n.alrashidwidget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.time.DayOfWeek
import java.time.Duration
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/// Shared data builder for the home-screen widgets: computes today's
/// (and tomorrow's) schedule with the same calibrated calculator as the
/// app and finds the next prayer, mirroring the app's snapshot logic.
object WidgetData {
    data class Row(
        val name: String,
        val adhan: ZonedDateTime,
        val iqamah: ZonedDateTime?,
        val isNext: Boolean,
        val dimmed: Boolean
    )

    data class Model(
        val hijri: String,
        val nextName: String,
        val nextTime: String,
        val nextIqamahText: String?,
        val countdownText: String,
        val showingTomorrow: Boolean,
        val rows: List<Row>,
        val isFriday: Boolean,
        /// Epoch millis of the next Adhan — the rollover alarm target.
        val nextAdhanMillis: Long
    )

    private val timeFmt = DateTimeFormatter.ofPattern("h:mm a", Locale.US)

    fun formatTime(t: ZonedDateTime): String = timeFmt.format(t)

    private fun iqamahOffset(name: String): Int? = when (name) {
        "Fajr" -> 20
        "Dhuhr" -> 10
        "Asr" -> 10
        "Maghrib" -> 5
        "Isha" -> 10
        else -> null
    }

    private class DaySchedule(
        val date: LocalDate,
        val times: PrayerCalculator.Times,
        val isFriday: Boolean
    ) {
        val khutbah: ZonedDateTime? = if (isFriday) {
            ZonedDateTime.of(date.atTime(13, 30), PrayerCalculator.ZONE)
        } else null

        fun adhan(name: String): ZonedDateTime = when (name) {
            "Fajr" -> times.fajr
            "Sunrise" -> times.sunrise
            "Dhuhr" -> times.dhuhr
            "Asr" -> times.asr
            "Maghrib" -> times.maghrib
            else -> times.isha
        }

        fun iqamah(name: String): ZonedDateTime? {
            if (name == "Dhuhr" && isFriday) return khutbah
            val offset = iqamahOffset(name) ?: return null
            return adhan(name).plusMinutes(offset.toLong())
        }
    }

    private val allNames = listOf("Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha")
    private val prayerNames = listOf("Fajr", "Dhuhr", "Asr", "Maghrib", "Isha")

    fun current(now: ZonedDateTime = ZonedDateTime.now(PrayerCalculator.ZONE)): Model {
        val today = now.toLocalDate()
        val days = (-1..2).map { offset ->
            val date = today.plusDays(offset.toLong())
            DaySchedule(
                date,
                PrayerCalculator.timesFor(date),
                date.dayOfWeek == DayOfWeek.FRIDAY
            )
        }

        // Next prayer = first prayer Adhan strictly after now.
        var nextDay = days.last()
        var nextName = "Fajr"
        var found = false
        for (day in days) {
            for (name in prayerNames) {
                if (day.adhan(name).isAfter(now)) {
                    nextDay = day
                    nextName = name
                    found = true
                    break
                }
            }
            if (found) break
        }

        val displayName =
            if (nextDay.isFriday && nextName == "Dhuhr") "Jumu'ah" else nextName
        val nextAdhan = nextDay.adhan(nextName)
        val nextIqamah = nextDay.iqamah(nextName)
        val iqamahLabel = if (nextDay.isFriday && nextName == "Dhuhr") "Khutbah" else "Iqamah"

        val rows = allNames.map { name ->
            val jumuah = nextDay.isFriday && name == "Dhuhr"
            Row(
                name = if (jumuah) "Jumu'ah" else name,
                adhan = nextDay.adhan(name),
                iqamah = nextDay.iqamah(name),
                isNext = name == nextName,
                dimmed = name == "Sunrise"
            )
        }

        return Model(
            hijri = UmmAlQuraCalendar.hijriString(
                nextDay.date.year, nextDay.date.monthValue, nextDay.date.dayOfMonth
            ),
            nextName = displayName,
            nextTime = formatTime(nextAdhan),
            nextIqamahText = nextIqamah?.let { "$iqamahLabel at ${formatTime(it)}" },
            countdownText = countdownText(now, nextAdhan),
            showingTomorrow = nextDay.date.isAfter(today),
            rows = rows,
            isFriday = nextDay.isFriday,
            nextAdhanMillis = nextAdhan.toInstant().toEpochMilli()
        )
    }

    private fun countdownText(now: ZonedDateTime, target: ZonedDateTime): String {
        val d = Duration.between(now, target)
        if (d.isNegative || d.toMinutes() == 0L) return "now"
        val h = d.toHours()
        val m = d.toMinutes() % 60
        return when {
            h > 0 && m > 0 -> "in ${h}h ${m}m"
            h > 0 -> "in ${h}h"
            else -> "in ${m}m"
        }
    }
}

abstract class BaseWidgetProvider : AppWidgetProvider() {
    abstract fun layoutId(): Int
    abstract fun buildViews(context: Context, model: WidgetData.Model): RemoteViews

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val model = WidgetData.current()
        for (id in appWidgetIds) {
            val views = buildViews(context, model)
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pending = PendingIntent.getActivity(
                context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            appWidgetManager.updateAppWidget(id, views)
        }
        scheduleRollover(context, model.nextAdhanMillis)
    }

    /// Automatic rollover (v1.0.4): chain an alarm to just after the next
    /// Adhan so the widgets swap to the following prayer on their own —
    /// Dhuhr hands over to Asr without the app being opened. Each update
    /// re-arms the alarm for the following Adhan. setAndAllowWhileIdle is
    /// inexact (Doze can delay it a few minutes) and needs no exact-alarm
    /// permission; the 30-minute updatePeriodMillis remains the backstop.
    private fun scheduleRollover(context: Context, nextAdhanMillis: Long) {
        val component = ComponentName(context, javaClass)
        val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(component)
        if (ids.isEmpty()) return
        val intent = Intent(context, javaClass).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        val pending = PendingIntent.getBroadcast(
            context, javaClass.name.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC, nextAdhanMillis + 15_000, pending
        )
    }
}

/// Small widget: next prayer with countdown.
class NextPrayerWidgetProvider : BaseWidgetProvider() {
    override fun layoutId() = R.layout.widget_next

    override fun buildViews(context: Context, model: WidgetData.Model): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId())
        views.setTextViewText(R.id.widget_caption,
            if (model.showingTomorrow) "NEXT · TOMORROW" else "NEXT PRAYER")
        views.setTextViewText(R.id.widget_next_name, model.nextName)
        views.setTextViewText(R.id.widget_next_time, model.nextTime)
        views.setTextViewText(R.id.widget_countdown, model.countdownText)
        views.setTextViewText(R.id.widget_iqamah, model.nextIqamahText ?: "")
        return views
    }
}

/// Medium widget: next prayer header + full day table.
class ScheduleWidgetProvider : BaseWidgetProvider() {
    override fun layoutId() = R.layout.widget_schedule

    override fun buildViews(context: Context, model: WidgetData.Model): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId())
        views.setTextViewText(R.id.widget_header_next,
            "${model.nextName} · ${model.nextTime}")
        views.setTextViewText(R.id.widget_header_countdown, model.countdownText)
        fillRows(context, views, model)
        return views
    }

    companion object {
        /// Row colors come from values/widget_colors.xml (+ values-night),
        /// so the table follows Light/Dark Mode like the layouts do.
        fun fillRows(context: Context, views: RemoteViews, model: WidgetData.Model) {
            val accent = context.getColor(R.color.widget_accent)
            val primary = context.getColor(R.color.widget_primary)
            val muted = context.getColor(R.color.widget_muted)
            val nameIds = intArrayOf(
                R.id.row0_name, R.id.row1_name, R.id.row2_name,
                R.id.row3_name, R.id.row4_name, R.id.row5_name
            )
            val adhanIds = intArrayOf(
                R.id.row0_adhan, R.id.row1_adhan, R.id.row2_adhan,
                R.id.row3_adhan, R.id.row4_adhan, R.id.row5_adhan
            )
            val iqamahIds = intArrayOf(
                R.id.row0_iqamah, R.id.row1_iqamah, R.id.row2_iqamah,
                R.id.row3_iqamah, R.id.row4_iqamah, R.id.row5_iqamah
            )
            model.rows.forEachIndexed { i, row ->
                val color = when {
                    row.isNext -> accent
                    row.dimmed -> muted
                    else -> primary
                }
                views.setTextViewText(nameIds[i], row.name)
                views.setTextViewText(adhanIds[i], WidgetData.formatTime(row.adhan))
                views.setTextViewText(
                    iqamahIds[i],
                    row.iqamah?.let { WidgetData.formatTime(it) } ?: "—"
                )
                views.setTextColor(nameIds[i], color)
                views.setTextColor(adhanIds[i], color)
                views.setTextColor(iqamahIds[i], color)
            }
        }
    }
}

/// Large widget: mosque header + next prayer + full day table.
class LargeScheduleWidgetProvider : BaseWidgetProvider() {
    override fun layoutId() = R.layout.widget_large

    override fun buildViews(context: Context, model: WidgetData.Model): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId())
        views.setTextViewText(R.id.widget_hijri, model.hijri)
        views.setTextViewText(R.id.widget_next_label,
            if (model.showingTomorrow) "Next prayer · Tomorrow" else "Next prayer")
        views.setTextViewText(R.id.widget_next_name, model.nextName)
        views.setTextViewText(R.id.widget_next_time, model.nextTime)
        views.setTextViewText(R.id.widget_countdown, model.countdownText)
        views.setTextViewText(R.id.widget_iqamah, model.nextIqamahText ?: "")
        ScheduleWidgetProvider.fillRows(context, views, model)
        return views
    }
}
