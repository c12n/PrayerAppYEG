package com.c12n.alrashidwidget

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/// Adhan notification engine (v1.5) — the native half of the Dart
/// scheduler in lib/alerts.dart. Dart computes the next 7 days of
/// alerts and sends the plan over the 'alrashid/alerts' channel; this
/// side persists it (so it survives reboots and the app being closed),
/// chains one AlarmManager alarm for the next pending item, posts the
/// notification when it fires, and re-arms the following item.

/// One item of the alert plan computed by the Dart scheduler.
data class AlertItem(
    val id: Int,
    val epochMillis: Long,
    val title: String,
    val body: String
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("epochMillis", epochMillis)
        .put("title", title)
        .put("body", body)

    companion object {
        fun fromJson(o: JSONObject): AlertItem = AlertItem(
            o.getInt("id"),
            o.getLong("epochMillis"),
            o.optString("title"),
            o.optString("body")
        )

        fun fromChannelMap(m: Map<*, *>): AlertItem = AlertItem(
            (m["id"] as Number).toInt(),
            (m["epochMillis"] as Number).toLong(),
            m["title"] as? String ?: "",
            m["body"] as? String ?: ""
        )
    }
}

/// Persists the plan in its own SharedPreferences file
/// ("alrashid_alerts"), separate from the Flutter preferences.
object AlertStore {
    private const val PREFS = "alrashid_alerts"
    private const val KEY_PLAN = "plan"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(context: Context, items: List<AlertItem>) {
        val array = JSONArray()
        items.forEach { array.put(it.toJson()) }
        prefs(context).edit().putString(KEY_PLAN, array.toString()).apply()
    }

    fun load(context: Context): List<AlertItem> {
        val raw = prefs(context).getString(KEY_PLAN, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map {
                AlertItem.fromJson(array.getJSONObject(it))
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_PLAN).apply()
    }

    fun nextPending(context: Context, nowMillis: Long): AlertItem? =
        load(context)
            .filter { it.epochMillis > nowMillis }
            .minByOrNull { it.epochMillis }
}

/// Arms a single chained alarm for the next pending item; each firing
/// re-arms the following one, so the whole plan runs off one
/// AlarmManager slot. Exact alarms are used when the user has granted
/// the exact-alarm permission, inexact (Doze-tolerant) otherwise.
object AlertArmer {
    private const val REQUEST_CODE = 0xA1E57

    private fun pendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context, REQUEST_CODE,
            Intent(context, AdhanAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntent(context))
    }

    fun rearm(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(context)
        am.cancel(pi)
        val next = AlertStore.nextPending(context, System.currentTimeMillis())
            ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            am.canScheduleExactAlarms()
        ) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.epochMillis, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.epochMillis, pi)
        }
    }
}

/// Posts alert notifications on the 'adhan_alerts' channel
/// (IMPORTANCE_HIGH, default notification sound, app icon).
object AdhanNotifier {
    const val CHANNEL_ID = "adhan_alerts"

    fun ensureChannel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, "Adhan Alerts", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description =
                "Adhan alerts, pre-prayer reminders and the Jumu'ah reminder"
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
        }
        nm.createNotificationChannel(channel)
    }

    fun post(context: Context, item: AlertItem) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return
        ensureChannel(context)
        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context, item.id, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(item.title)
            .setContentText(item.body)
            .setStyle(Notification.BigTextStyle().bigText(item.body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setDefaults(Notification.DEFAULT_SOUND)
            .build()
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        nm.notify(item.id, notification)
    }
}

/// Fires when the chained alarm goes off: posts the due item (the
/// most recent one, if it is still fresh — a phone that was off for
/// hours should not burst stale alerts), drops everything due from
/// the stored plan, and re-arms the next pending item.
class AdhanAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val now = System.currentTimeMillis()
        val plan = AlertStore.load(context)
        val due = plan.filter { it.epochMillis <= now }
        val future = plan.filter { it.epochMillis > now }
        val latest = due.maxByOrNull { it.epochMillis }
        if (latest != null && now - latest.epochMillis <= STALE_TOLERANCE_MS) {
            AdhanNotifier.post(context, latest)
        }
        AlertStore.save(context, future)
        AlertArmer.rearm(context)
    }

    companion object {
        private const val STALE_TOLERANCE_MS = 15 * 60 * 1000L
    }
}

/// Re-arms the alert chain after a reboot from the persisted plan.
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            AlertArmer.rearm(context)
        }
    }
}
