package com.c12n.alrashidwidget

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/// Quick Settings tile (v2.0.0, feature 7 — Android leg): the
/// Control Center equivalent. One tap silences ONLY the next Adhan
/// alert: it writes the same one-shot flag the Dart scheduler honors
/// ('flutter.alerts.silenceNextEpoch', epoch seconds) AND drops that
/// one item from the native alert plan immediately, so the tile
/// works even if the app is never opened. Tapping again clears the
/// flag; an already-dropped item returns at the app's next plan
/// rebuild (every launch / resume), like the iOS control.
class SilenceNextTileService : TileService() {

    private fun flutterPrefs() =
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)

    private fun silencedEpoch(): Long =
        flutterPrefs().getLong("flutter.alerts.silenceNextEpoch", 0L)

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        val nextMillis = WidgetData.current(this).nextAdhanMillis
        val nextSeconds = nextMillis / 1000
        if (silencedEpoch() == nextSeconds) {
            flutterPrefs().edit()
                .remove("flutter.alerts.silenceNextEpoch").apply()
        } else {
            flutterPrefs().edit()
                .putLong("flutter.alerts.silenceNextEpoch", nextSeconds)
                .apply()
            // Drop exactly the Adhan item (its id is the Adhan's
            // epoch seconds; reminders carry a large offset and are
            // untouched) and re-arm the chain on what remains.
            val kept = AlertStore.load(this)
                .filter { it.id.toLong() != nextSeconds }
            AlertStore.save(this, kept)
            AlertArmer.rearm(this)
        }
        refreshTile()
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val nextMillis = WidgetData.current(this).nextAdhanMillis
        val active = silencedEpoch() == nextMillis / 1000
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Silence Next Alert"
        tile.updateTile()
    }
}
