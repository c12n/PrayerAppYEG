package com.c12n.prayerappandroid.wear

import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import java.time.Instant

/** Watch-face complication (SHORT_TEXT): the next Edmonton prayer's
 *  name, with its adhan time as the title. Computed on the watch from
 *  the same calculator as the phone apps. */
class NextPrayerComplicationService : ComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        if (type != ComplicationType.SHORT_TEXT) return null
        return buildData("Dhuhr", "1:19 PM")
    }

    override fun onComplicationRequest(
        request: ComplicationRequest,
        listener: ComplicationRequestListener,
    ) {
        val snapshot = PrayerProvider.snapshot(Instant.now())
        listener.onComplicationData(
            buildData(snapshot.next.name, PrayerFormat.time(snapshot.next.adhan))
        )
    }

    private fun buildData(name: String, time: String): ComplicationData =
        ShortTextComplicationData.Builder(
            text = PlainComplicationText.Builder(name).build(),
            contentDescription = PlainComplicationText
                .Builder("Next prayer: $name at $time").build(),
        )
            .setTitle(PlainComplicationText.Builder(time).build())
            .build()
}
