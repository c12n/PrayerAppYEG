package com.c12n.alrashidwidget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.util.TypedValue
import android.widget.RemoteViews
import java.time.DayOfWeek
import java.time.Duration
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/// User settings written by the Flutter app (shared_preferences), read
/// back here so the widgets follow the same choices. shared_preferences
/// stores into "FlutterSharedPreferences" with a "flutter." key prefix;
/// ints land as Long, booleans as Boolean.
object WidgetPrefs {
    private fun prefs(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /// Whether the countdown should move to this prayer (Settings →
    /// Widget Countdown). The five prayers default on, Sunrise off.
    fun countdownEnabled(context: Context, name: String): Boolean =
        prefs(context).getBoolean("flutter.alerts.${name.lowercase()}", name != "Sunrise")

    /// The user's accent color (Settings → Theme Colors), adjusted for
    /// the current appearance the same way the apps do it: brightened on
    /// dark surfaces, deepened on light ones. Null = not picked yet.
    /// The app's language (Settings → Language), "en"/"ar"/"fr".
    fun language(context: Context): String =
        prefs(context).getString("flutter.language.code", null) ?: "en"

    /// The Hijri date adjustment (v1.5, Settings → Hijri Date):
    /// −1..+1 days. shared_preferences stores Dart ints as Long.
    fun hijriOffsetDays(context: Context): Int =
        prefs(context).getLong("flutter.hijri.offsetDays", 0L)
            .toInt().coerceIn(-1, 1)

    /// Widget text scale (v1.8.0, Settings → Text Size): the widgets
    /// follow the app's text-size choice with gentler factors than
    /// the in-app scale, so the fixed widget layouts don't overflow
    /// (the same factors the iOS widgets use).
    fun textScaleFactor(context: Context): Float =
        when (prefs(context).getString("flutter.appearance.textSize", null)) {
            "large" -> 1.12f
            "extraLarge" -> 1.25f
            else -> 1.0f
        }

    /// Widget colors mode (v1.9.0): "separate" = the home widgets
    /// have their own theme (flat keys written by the Flutter app);
    /// anything else = match the app theme.
    fun widgetColorSeparate(context: Context): Boolean =
        prefs(context).getString("flutter.appearance.widgetColorMode", null) == "separate"

    /// Minimal Mode (v2.0.0): widgets are already plain time lists;
    /// Minimal only drops the Ramadan hero naming below.
    fun minimalMode(context: Context): Boolean =
        prefs(context).getBoolean("flutter.appearance.minimalMode", false)

    private fun rawHex(context: Context, separateKey: String, appKey: String, default: Long): Long {
        val key = if (widgetColorSeparate(context)) separateKey else appKey
        val v = prefs(context).getLong(key, -1L)
        return if (v >= 0) v else default
    }

    /// Effective widget theme raws (v1.9.0) — defaults are the
    /// signature green / gold / white, so widgets are colored even
    /// before Settings is ever opened.
    fun effectivePrimaryRaw(context: Context): Long = rawHex(context,
        "flutter.appearance.widgetTheme.home.primaryHex",
        "flutter.appearance.primaryHex", 0x0B3D2EL)
    fun effectiveAccentRaw(context: Context): Long = rawHex(context,
        "flutter.appearance.widgetTheme.home.accentHex",
        "flutter.appearance.accentHex", 0xD4AF37L)
    fun effectiveTextRaw(context: Context): Long = rawHex(context,
        "flutter.appearance.widgetTheme.home.textHex",
        "flutter.appearance.textHex", 0xFFFFFFL)

    /// The widgets' accent color (v1.9.0): the effective accent,
    /// brightened for the (always deep) colored widget surface the
    /// same way the apps brighten for dark surfaces. Never null now:
    /// the signature gold is the fallback.
    fun accentColor(context: Context): Int {
        val raw = effectiveAccentRaw(context)
        val hsv = FloatArray(3)
        Color.colorToHSV((0xFF000000 or raw).toInt(), hsv)
        hsv[1] = minOf(hsv[1], 0.9f)
        hsv[2] = maxOf(hsv[2], 0.82f)
        return Color.HSVToColor(hsv)
    }

}


/// Widget surface colors (v1.9.0): paints the colored gradient
/// background bitmap and provides the palette text colors that the
/// providers stamp over the layouts' Light/Dark resource defaults —
/// the widgets are full-color surfaces now, like the iOS ones.
object WidgetColors {
    fun primary(context: Context): Int =
        (0xFF000000 or WidgetPrefs.effectivePrimaryRaw(context)).toInt()

    fun text(context: Context): Int =
        (0xFF000000 or WidgetPrefs.effectiveTextRaw(context)).toInt()

    fun textSecondary(context: Context): Int = withAlpha(text(context), 0.85f)
    fun textMuted(context: Context): Int = withAlpha(text(context), 0.72f)

    private fun withAlpha(color: Int, alpha: Float): Int =
        Color.argb((alpha * 255).toInt(), Color.red(color), Color.green(color), Color.blue(color))

    private fun shade(color: Int, factor: Float): Int {
        val hsv = FloatArray(3)
        Color.colorToHSV(color, hsv)
        hsv[2] = (hsv[2] * factor).coerceIn(0f, 1f)
        if (factor > 1f) hsv[1] = hsv[1] * 0.9f
        return Color.HSVToColor(hsv)
    }

    /// Rounded gradient (bright -> primary -> deep) as a bitmap for
    /// the layouts' background ImageView; RemoteViews cannot attach a
    /// generated drawable, so a bitmap is the portable route.
    fun applyBackground(context: Context, views: RemoteViews) {
        val size = 880
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val base = primary(context)
        val shader = LinearGradient(
            0f, 0f, size.toFloat(), size.toFloat(),
            intArrayOf(shade(base, 1.35f), base, shade(base, 0.62f)),
            null, Shader.TileMode.CLAMP
        )
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = shader }
        canvas.drawRoundRect(RectF(0f, 0f, size.toFloat(), size.toFloat()), 72f, 72f, paint)
        views.setImageViewBitmap(R.id.widget_bg_image, bitmap)
    }

    /// Stamps palette colors onto the given id groups.
    fun paint(
        context: Context, views: RemoteViews,
        accentIds: IntArray = intArrayOf(),
        textIds: IntArray = intArrayOf(),
        secondaryIds: IntArray = intArrayOf(),
        mutedIds: IntArray = intArrayOf()
    ) {
        applyBackground(context, views)
        val accent = WidgetPrefs.accentColor(context)
        val text = text(context)
        val secondary = textSecondary(context)
        val muted = textMuted(context)
        for (id in accentIds) views.setTextColor(id, accent)
        for (id in textIds) views.setTextColor(id, text)
        for (id in secondaryIds) views.setTextColor(id, secondary)
        for (id in mutedIds) views.setTextColor(id, muted)
    }
}

/// Localized widget strings (v1.1.0). Internal logic keeps English
/// prayer keys; only display strings go through here.
object WidgetStrings {
    private fun arabicDigits(input: String): String {
        val digits = "٠١٢٣٤٥٦٧٨٩"
        return input.map { ch -> if (ch in '0'..'9') digits[ch - '0'] else ch }
            .joinToString("")
    }

    fun locale(language: String): Locale = when (language) {
        "ar" -> Locale("ar")
        "fr" -> Locale("fr")
        else -> Locale.US
    }

    fun prayerName(english: String, language: String): String = when (language) {
        "ar" -> when (english) {
            "Fajr" -> "الفجر"; "Sunrise" -> "الشروق"; "Dhuhr" -> "الظهر"
            "Asr" -> "العصر"; "Maghrib" -> "المغرب"; "Isha" -> "العشاء"
            else -> english
        }
        "fr" -> if (english == "Sunrise") "Lever du soleil" else english
        else -> english
    }

    fun jumuah(language: String): String =
        if (language == "ar") "الجمعة" else "Jumu'ah"

    fun iftar(language: String): String =
        if (language == "ar") "الإفطار" else "Iftar"

    fun suhoor(language: String): String =
        if (language == "ar") "السحور" else "Suhoor"

    fun iqamahLabel(isJumuah: Boolean, language: String): String = when {
        isJumuah && language == "ar" -> "الخطبة"
        isJumuah -> "Khutbah"
        language == "ar" -> "الإقامة"
        else -> "Iqamah"
    }

    fun at(language: String): String = when (language) {
        "ar" -> "في"; "fr" -> "à"; else -> "at"
    }

    fun nextCaption(tomorrow: Boolean, caps: Boolean, language: String): String =
        when (language) {
            "ar" -> if (tomorrow) "الصلاة التالية · غدًا" else "الصلاة التالية"
            "fr" -> if (caps) {
                if (tomorrow) "PROCHAINE · DEMAIN" else "PROCHAINE PRIÈRE"
            } else {
                if (tomorrow) "Prochaine prière · Demain" else "Prochaine prière"
            }
            else -> if (caps) {
                if (tomorrow) "NEXT · TOMORROW" else "NEXT PRAYER"
            } else {
                if (tomorrow) "Next prayer · Tomorrow" else "Next prayer"
            }
        }

    fun countdown(now: Boolean, h: Long, m: Long, language: String): String =
        when (language) {
            "ar" -> if (now) "الآن" else "متبقي " + arabicDigits("%d:%02d".format(h, m))
            "fr" -> if (now) "maintenant" else when {
                h > 0 && m > 0 -> "dans ${h}h ${m}m"
                h > 0 -> "dans ${h}h"
                else -> "dans ${m}m"
            }
            else -> if (now) "now" else when {
                h > 0 && m > 0 -> "in ${h}h ${m}m"
                h > 0 -> "in ${h}h"
                else -> "in ${m}m"
            }
        }
}

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
        /// Gregorian date of the displayed day, "Wed, Oct 28" (v1.0.5).
        val dateText: String,
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

    private fun timeFmt(language: String) =
        DateTimeFormatter.ofPattern("h:mm a", WidgetStrings.locale(language))
    private fun dateFmt(language: String) =
        DateTimeFormatter.ofPattern("EEE, MMM d", WidgetStrings.locale(language))

    fun formatTime(t: ZonedDateTime, language: String = "en"): String =
        timeFmt(language).format(t)

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

    fun current(
        context: Context,
        now: ZonedDateTime = ZonedDateTime.now(PrayerCalculator.ZONE)
    ): Model {
        val language = WidgetPrefs.language(context)
        // The countdown rotation honors the user's Widget Countdown
        // choices (v1.0.5): prayers they turned off are skipped, and
        // Sunrise joins the rotation when they turned it on. If they
        // turned everything off, fall back to the five prayers.
        val rotation = allNames.filter { WidgetPrefs.countdownEnabled(context, it) }
            .ifEmpty { prayerNames }
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
            for (name in rotation) {
                if (day.adhan(name).isAfter(now)) {
                    nextDay = day
                    nextName = name
                    found = true
                    break
                }
            }
            if (found) break
        }

        val isJumuahNext = nextDay.isFriday && nextName == "Dhuhr"
        // Ramadan (v1.9.0): widgets label Maghrib "Iftar" and Fajr
        // "Suhoor" in the hero line during Hijri month 9 (with the
        // user's Hijri offset applied, like the date line below).
        val ramadanGregorian =
            nextDay.date.plusDays(WidgetPrefs.hijriOffsetDays(context).toLong())
        val isRamadan = UmmAlQuraCalendar.hijri(
            ramadanGregorian.year, ramadanGregorian.monthValue,
            ramadanGregorian.dayOfMonth
        )?.month == 9
        val displayName =
            if (isJumuahNext) WidgetStrings.jumuah(language)
            else if (isRamadan && !WidgetPrefs.minimalMode(context) && nextName == "Maghrib") WidgetStrings.iftar(language)
            else if (isRamadan && !WidgetPrefs.minimalMode(context) && nextName == "Fajr") WidgetStrings.suhoor(language)
            else WidgetStrings.prayerName(nextName, language)
        val nextAdhan = nextDay.adhan(nextName)
        val nextIqamah = nextDay.iqamah(nextName)
        val iqamahLabel = WidgetStrings.iqamahLabel(isJumuahNext, language)

        val rows = allNames.map { name ->
            val jumuah = nextDay.isFriday && name == "Dhuhr"
            Row(
                name = if (jumuah) WidgetStrings.jumuah(language)
                       else WidgetStrings.prayerName(name, language),
                adhan = nextDay.adhan(name),
                iqamah = nextDay.iqamah(name),
                isNext = name == nextName,
                dimmed = name == "Sunrise"
            )
        }

        // The displayed Hijri date honors the user's ±1 day
        // adjustment (v1.5), applied to the Gregorian date before
        // conversion, exactly like the app.
        val hijriGregorian =
            nextDay.date.plusDays(WidgetPrefs.hijriOffsetDays(context).toLong())
        return Model(
            hijri = UmmAlQuraCalendar.hijriString(
                hijriGregorian.year, hijriGregorian.monthValue,
                hijriGregorian.dayOfMonth, language
            ),
            dateText = dateFmt(language).format(nextDay.date),
            nextName = displayName,
            nextTime = formatTime(nextAdhan, language),
            nextIqamahText = nextIqamah?.let {
                "$iqamahLabel ${WidgetStrings.at(language)} ${formatTime(it, language)}"
            },
            countdownText = countdownText(now, nextAdhan, language),
            showingTomorrow = nextDay.date.isAfter(today),
            rows = rows,
            isFriday = nextDay.isFriday,
            nextAdhanMillis = nextAdhan.toInstant().toEpochMilli()
        )
    }

    private fun countdownText(
        now: ZonedDateTime, target: ZonedDateTime, language: String
    ): String {
        val d = Duration.between(now, target)
        if (d.isNegative || d.toMinutes() == 0L) {
            return WidgetStrings.countdown(true, 0, 0, language)
        }
        return WidgetStrings.countdown(false, d.toHours(), d.toMinutes() % 60, language)
    }
}

abstract class BaseWidgetProvider : AppWidgetProvider() {
    abstract fun layoutId(): Int
    abstract fun buildViews(context: Context, model: WidgetData.Model): RemoteViews

    /// Applies the user's text-size factor (v1.8.0) to the given
    /// (view id → layout base size in sp) pairs. A standard-size
    /// choice leaves the layouts exactly as designed.
    protected fun applyTextScale(
        context: Context,
        views: RemoteViews,
        vararg sizes: Pair<Int, Float>
    ) {
        val factor = WidgetPrefs.textScaleFactor(context)
        if (factor == 1.0f) return
        for ((id, baseSp) in sizes) {
            views.setTextViewTextSize(
                id, TypedValue.COMPLEX_UNIT_SP, baseSp * factor)
        }
    }

    /// v1.9.0: colored surface + palette text for this widget.
    protected fun paintWidget(
        context: Context, views: RemoteViews,
        accentIds: IntArray = intArrayOf(),
        textIds: IntArray = intArrayOf(),
        secondaryIds: IntArray = intArrayOf(),
        mutedIds: IntArray = intArrayOf()
    ) = WidgetColors.paint(context, views, accentIds, textIds, secondaryIds, mutedIds)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val model = WidgetData.current(context)
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
            WidgetStrings.nextCaption(model.showingTomorrow, true, WidgetPrefs.language(context)))
        views.setTextViewText(R.id.widget_date, model.dateText)
        views.setTextViewText(R.id.widget_next_name, model.nextName)
        views.setTextViewText(R.id.widget_next_time, model.nextTime)
        views.setTextViewText(R.id.widget_countdown, model.countdownText)
        views.setTextViewText(R.id.widget_iqamah, model.nextIqamahText ?: "")
        paintWidget(context, views,
            accentIds = intArrayOf(R.id.widget_caption, R.id.widget_countdown),
            textIds = intArrayOf(R.id.widget_next_name),
            secondaryIds = intArrayOf(R.id.widget_next_time),
            mutedIds = intArrayOf(R.id.widget_date, R.id.widget_iqamah))
        applyTextScale(context, views,
            R.id.widget_caption to 12f, R.id.widget_date to 12f,
            R.id.widget_next_name to 28f, R.id.widget_next_time to 17f,
            R.id.widget_countdown to 24f, R.id.widget_iqamah to 13f)
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
        views.setTextViewText(R.id.widget_date, model.dateText)
        paintWidget(context, views,
            accentIds = intArrayOf(R.id.widget_header_countdown),
            textIds = intArrayOf(R.id.widget_header_next),
            mutedIds = intArrayOf(R.id.widget_date, R.id.widget_col_prayer,
                R.id.widget_col_adhan, R.id.widget_col_iqamah))
        applyTextScale(context, views,
            R.id.widget_header_next to 16f,
            R.id.widget_header_countdown to 16f,
            R.id.widget_date to 11f,
            R.id.widget_col_prayer to 10f,
            R.id.widget_col_adhan to 10f,
            R.id.widget_col_iqamah to 10f)
        fillRows(context, views, model)
        return views
    }

    companion object {
        /// Row colors come from values/widget_colors.xml (+ values-night),
        /// so the table follows Light/Dark Mode like the layouts do. The
        /// "next" row uses the user's picked accent color when set.
        /// [rowSp] is the layout's base row text size (14sp in the
        /// schedule widget, 16sp in the large one); rows scale with
        /// the user's text-size factor (v1.8.0).
        fun fillRows(
            context: Context,
            views: RemoteViews,
            model: WidgetData.Model,
            rowSp: Float = 14f
        ) {
            // v1.9.0: rows wear the widget palette (was Light/Dark
            // resource colors before the widgets went full-color).
            val accent = WidgetPrefs.accentColor(context)
            val primary = WidgetColors.text(context)
            val muted = WidgetColors.textMuted(context)
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
                val language = WidgetPrefs.language(context)
                views.setTextViewText(adhanIds[i], WidgetData.formatTime(row.adhan, language))
                views.setTextViewText(
                    iqamahIds[i],
                    row.iqamah?.let { WidgetData.formatTime(it, language) } ?: "—"
                )
                views.setTextColor(nameIds[i], color)
                views.setTextColor(adhanIds[i], color)
                views.setTextColor(iqamahIds[i], color)
            }
            val factor = WidgetPrefs.textScaleFactor(context)
            if (factor != 1.0f) {
                for (i in model.rows.indices) {
                    views.setTextViewTextSize(nameIds[i],
                        TypedValue.COMPLEX_UNIT_SP, rowSp * factor)
                    views.setTextViewTextSize(adhanIds[i],
                        TypedValue.COMPLEX_UNIT_SP, rowSp * factor)
                    views.setTextViewTextSize(iqamahIds[i],
                        TypedValue.COMPLEX_UNIT_SP, rowSp * factor)
                }
            }
        }
    }
}

/// Large widget: mosque header + next prayer + full day table.
class LargeScheduleWidgetProvider : BaseWidgetProvider() {
    override fun layoutId() = R.layout.widget_large

    override fun buildViews(context: Context, model: WidgetData.Model): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId())
        views.setTextViewText(R.id.widget_hijri, "${model.dateText} · ${model.hijri}")
        views.setTextViewText(R.id.widget_next_label,
            WidgetStrings.nextCaption(model.showingTomorrow, false, WidgetPrefs.language(context)))
        views.setTextViewText(R.id.widget_next_name, model.nextName)
        views.setTextViewText(R.id.widget_next_time, model.nextTime)
        views.setTextViewText(R.id.widget_countdown, model.countdownText)
        views.setTextViewText(R.id.widget_iqamah, model.nextIqamahText ?: "")
        paintWidget(context, views,
            accentIds = intArrayOf(R.id.widget_countdown, R.id.widget_next_label,
                R.id.widget_mosque),
            textIds = intArrayOf(R.id.widget_next_name, R.id.widget_verse),
            secondaryIds = intArrayOf(R.id.widget_next_time, R.id.widget_iqamah),
            mutedIds = intArrayOf(R.id.widget_hijri, R.id.widget_col_prayer,
                R.id.widget_col_adhan, R.id.widget_col_iqamah))
        applyTextScale(context, views,
            R.id.widget_mosque to 14f, R.id.widget_hijri to 13f,
            R.id.widget_next_label to 13f, R.id.widget_next_name to 32f,
            R.id.widget_next_time to 19f, R.id.widget_countdown to 28f,
            R.id.widget_iqamah to 14f,
            R.id.widget_col_prayer to 11f, R.id.widget_col_adhan to 11f,
            R.id.widget_col_iqamah to 11f,
            R.id.widget_verse to 14f, R.id.widget_verse_ref to 11f)
        ScheduleWidgetProvider.fillRows(context, views, model, rowSp = 16f)
        // Quran quote of the day under the schedule (v1.5), the same
        // verse the app shows today.
        val language = WidgetPrefs.language(context)
        val today = ZonedDateTime.now(PrayerCalculator.ZONE).toLocalDate()
        val verse = DailyVerses.verseFor(today)
        views.setTextViewText(R.id.widget_verse, verse.arabic)
        views.setTextViewText(
            R.id.widget_verse_ref, DailyVerses.reference(verse, language))
        views.setTextColor(R.id.widget_verse_ref, WidgetPrefs.accentColor(context))
        return views
    }
}
