package com.c12n.alrashidwidget

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat

/// Ongoing countdown notification (v3.0.0): the Android stand-in
/// for the iOS Live Activity. A silent, persistent notification
/// showing the next prayer and its countdown, refreshed once a
/// minute by a chained inexact alarm while enabled. The opt-in
/// lives in the Flutter settings ('ongoing.enabled'); the native
/// copy here is what re-posts after a reboot or process kill.
/// Default OFF, exactly like iOS.
object OngoingNotification {
    private const val CHANNEL_ID = "prayer_ongoing"
    private const val NOTIF_ID = 9001
    private const val PREFS = "alrashid_alerts"
    private const val KEY = "ongoing_enabled"
    private const val TICK_REQUEST = 0x0901

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY, enabled).apply()
        if (enabled) {
            refresh(context)
        } else {
            (context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager).cancel(NOTIF_ID)
            cancelTick(context)
        }
    }

    /// (Re)posts the notification with the current next prayer and
    /// re-arms the minute tick. No-op when the user has it off.
    fun refresh(context: Context) {
        if (!isEnabled(context)) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        ensureChannel(context, nm)
        val model = WidgetData.current(context)
        val title = "${model.nextName} ${model.nextTime}"
        val body = buildString {
            append(model.countdownText)
            val iqamah = model.nextIqamahText
            if (!iqamah.isNullOrEmpty()) {
                append(" · ")
                append(iqamah)
            }
        }
        val tap = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(tap)
            .build()
        nm.notify(NOTIF_ID, notification)
        scheduleTick(context)
    }

    private fun ensureChannel(context: Context, nm: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, "Prayer countdown", NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Persistent next prayer and countdown"
            setSound(null, null)
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun tickIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context, TICK_REQUEST,
            Intent(context, OngoingTickReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun scheduleTick(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // Inexact on purpose: the countdown is minute-granular and
        // this must never fight the exactness budget of the adhans.
        am.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + 60_000L,
            tickIntent(context)
        )
    }

    private fun cancelTick(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(tickIntent(context))
    }
}

/// The minute tick: re-posts the ongoing notification (which
/// re-arms the next tick) while the opt-in is on.
class OngoingTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        OngoingNotification.refresh(context)
    }
}
