package com.c12n.alrashidwidget

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.atan2

/// MainActivity with the Qibla compass heading channel (v1.1.0).
/// Streams the device azimuth (degrees clockwise from MAGNETIC north)
/// computed from the accelerometer + magnetometer with light smoothing.
/// No location permission is involved; the Dart side adds Edmonton's
/// magnetic declination to get true north. This file replaces the
/// flutter-create generated MainActivity via the overlay copy step.
///
/// v1.5 adds two MethodChannels: 'alrashid/alerts' (the Adhan
/// notification plan — see Alerts.kt) and 'alrashid/share' (the daily
/// verse share sheet).
class MainActivity : FlutterActivity(), SensorEventListener {
    private var sensorManager: SensorManager? = null
    private var headingSink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private var pickResult: MethodChannel.Result? = null

    private val gravity = FloatArray(3)
    private val geomagnetic = FloatArray(3)
    private var hasGravity = false
    private var hasGeomagnetic = false
    private var lastAzimuth = Double.NaN

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "alrashid/heading")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    headingSink = events
                    startSensors()
                }

                override fun onCancel(arguments: Any?) {
                    headingSink = null
                    stopSensors()
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alrashid/alerts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val raw = call.argument<List<Map<*, *>>>("items")
                            ?: emptyList()
                        AlertStore.save(this, raw.map { AlertItem.fromChannelMap(it) })
                        AlertArmer.rearm(this)
                        result.success(null)
                    }
                    "cancelAll" -> {
                        AlertStore.clear(this)
                        AlertArmer.cancel(this)
                        result.success(null)
                    }
                    "requestPermission" -> requestNotificationPermission(result)
                    // Alerts health check (v2.3.0): status snapshot,
                    // an immediate test alert on the real channel,
                    // and the two system screens that fix the
                    // Android-only failure modes (exact alarms,
                    // battery optimization).
                    "alertStatus" -> result.success(alertStatus())
                    // Sound picker preview (build 34): hear a sound
                    // without selecting it or scheduling anything.
                    "previewSound" -> {
                        previewSound(call.argument<String>("sound") ?: "")
                        result.success(null)
                    }
                    "testAlert" -> {
                        AdhanNotifier.post(
                            this,
                            AlertItem(
                                id = (System.currentTimeMillis() / 1000).toInt(),
                                epochMillis = System.currentTimeMillis(),
                                title = call.argument<String>("title") ?: "",
                                body = call.argument<String>("body") ?: "",
                                sound = call.argument<String>("sound") ?: "default"
                            )
                        )
                        result.success(null)
                    }
                    "openExactAlarmSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:$packageName")
                            )
                        } else {
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")
                            )
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "openBatterySettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alrashid/backup")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "driveBackup" -> DriveBackup.run(
                        this, "driveBackup", call.argument<String>("json"), result)
                    "driveRestore" -> DriveBackup.run(
                        this, "driveRestore", null, result)
                    "driveLastBackup" -> {
                        val millis = DriveBackup.lastBackupMillis(this)
                        result.success(if (millis > 0) millis else null)
                    }
                    "pickFile" -> {
                        pickResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                        }
                        startActivityForResult(intent, FILE_PICK_REQUEST)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alrashid/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "share" -> {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                        }
                        startActivity(Intent.createChooser(send, null))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// The sound picker's preview player (build 34): one at a time,
    /// released on completion or when another preview starts.
    private var previewPlayer: android.media.MediaPlayer? = null

    private fun previewSound(sound: String) {
        previewPlayer?.release()
        previewPlayer = null
        val resId = when (sound) {
            "chime" -> R.raw.adhan_chime
            "bell" -> R.raw.adhan_bell
            "makkah" -> R.raw.adhan_makkah
            "fajr" -> R.raw.adhan_fajr
            "classic" -> R.raw.adhan_classic
            else -> return
        }
        previewPlayer = android.media.MediaPlayer.create(this, resId)?.apply {
            setOnCompletionListener {
                it.release()
                if (previewPlayer === it) previewPlayer = null
            }
            start()
        }
    }

    /// Alerts health check snapshot (v2.3.0): everything the Dart
    /// health page shows, read live from the system. nextEpochMillis
    /// is 0 when nothing is armed.
    private fun alertStatus(): Map<String, Any> {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notificationsOn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            nm.areNotificationsEnabled()
        }
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val exactAlarms = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            am.canScheduleExactAlarms()
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val batteryExempt = pm.isIgnoringBatteryOptimizations(packageName)
        val now = System.currentTimeMillis()
        val pending = AlertStore.load(this).filter { it.epochMillis > now }
        return mapOf(
            "notificationsOn" to notificationsOn,
            "exactAlarms" to exactAlarms,
            "batteryExempt" to batteryExempt,
            "scheduledCount" to pending.size,
            "nextEpochMillis" to (pending.minByOrNull { it.epochMillis }?.epochMillis ?: 0L)
        )
    }

    /// POST_NOTIFICATIONS runtime permission (Android 13+). The Dart
    /// side gets the outcome via the stored channel result, completed
    /// in onRequestPermissionsResult.
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        permissionResult?.success(false)
        permissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST
        )
    }

    // Assistant / Bixby deep links (v2.0.0, feature 7): shortcuts.xml
    // and App Actions land here with a "prayer" extra ('next' or a
    // prayer name). The query is parked in the Flutter preferences;
    // the Dart home page answers it in a dialog when it surfaces.
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        captureAssistantQuery(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureAssistantQuery(intent)
    }

    private fun captureAssistantQuery(intent: Intent?) {
        val prayer = intent?.getStringExtra("prayer") ?: return
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .edit()
            .putString("flutter.assistant.queryPrayer", prayer)
            .putLong("flutter.assistant.queryAt", System.currentTimeMillis())
            .apply()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (DriveBackup.onActivityResult(this, requestCode, data)) return
        if (requestCode == FILE_PICK_REQUEST) {
            val result = pickResult
            pickResult = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                result?.success(null)
                return
            }
            try {
                val text = contentResolver.openInputStream(uri)
                    ?.bufferedReader()?.readText()
                result?.success(text)
            } catch (e: Exception) {
                result?.success(null)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST = 0xAD11
        private const val FILE_PICK_REQUEST = 0xDB02
    }

    private fun startSensors() {
        val sm = sensorManager ?: return
        sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let {
            sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
        sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.let {
            sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
    }

    private fun stopSensors() {
        sensorManager?.unregisterListener(this)
        hasGravity = false
        hasGeomagnetic = false
        lastAzimuth = Double.NaN
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        val alpha = 0.12f
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                for (i in 0..2) gravity[i] += alpha * (event.values[i] - gravity[i])
                hasGravity = true
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                for (i in 0..2) geomagnetic[i] += alpha * (event.values[i] - geomagnetic[i])
                hasGeomagnetic = true
            }
            else -> return
        }
        if (!hasGravity || !hasGeomagnetic) return
        val rotation = FloatArray(9)
        if (!SensorManager.getRotationMatrix(rotation, null, gravity, geomagnetic)) return
        val orientation = FloatArray(3)
        SensorManager.getOrientation(rotation, orientation)
        var azimuth = Math.toDegrees(orientation[0].toDouble())
        if (azimuth < 0) azimuth += 360.0
        // Circular smoothing so the dial does not jitter around 0/360.
        if (lastAzimuth.isNaN()) {
            lastAzimuth = azimuth
        } else {
            val a = Math.toRadians(lastAzimuth)
            val b = Math.toRadians(azimuth)
            val x = kotlin.math.cos(a) * 0.75 + kotlin.math.cos(b) * 0.25
            val y = kotlin.math.sin(a) * 0.75 + kotlin.math.sin(b) * 0.25
            lastAzimuth = (Math.toDegrees(atan2(y, x)) + 360.0) % 360.0
        }
        headingSink?.success(lastAzimuth)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
