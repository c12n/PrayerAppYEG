package com.c12n.alrashidwidget

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import kotlin.math.atan2

/// MainActivity with the Qibla compass heading channel (v1.1.0).
/// Streams the device azimuth (degrees clockwise from MAGNETIC north)
/// computed from the accelerometer + magnetometer with light smoothing.
/// No location permission is involved; the Dart side adds Edmonton's
/// magnetic declination to get true north. This file replaces the
/// flutter-create generated MainActivity via the overlay copy step.
class MainActivity : FlutterActivity(), SensorEventListener {
    private var sensorManager: SensorManager? = null
    private var headingSink: EventChannel.EventSink? = null

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
