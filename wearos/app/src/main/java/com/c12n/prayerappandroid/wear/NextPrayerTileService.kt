package com.c12n.prayerappandroid.wear

import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.time.Duration
import java.time.Instant

/** Wear Tile: the next Edmonton prayer and a compact countdown.
 *  Everything is computed on the watch from the same calculator as the
 *  phone apps; the system refreshes the tile periodically and the tile
 *  asks for a refresh every 15 minutes. */
class NextPrayerTileService : TileService() {

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> {
        val now = Instant.now()
        val snapshot = PrayerProvider.snapshot(now)
        val next = snapshot.next
        val countdown = PrayerFormat.countdownShort(Duration.between(now, next.adhan))

        val column = LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(textLine("NEXT PRAYER", 11f, GOLD, bold = false))
            .addSpacer(2f)
            .addContent(textLine(next.name, 24f, WHITE, bold = true))
            .addSpacer(2f)
            .addContent(textLine(PrayerFormat.time(next.adhan), 18f, WHITE, bold = false))
            .addSpacer(2f)
            .addContent(textLine("in $countdown", 13f, GOLD, bold = false))
            .build()

        val root = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHeight(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(ColorBuilders.argb(DEEP_GREEN))
                            .build()
                    )
                    .build()
            )
            .addContent(column)
            .build()

        val layout = LayoutElementBuilders.Layout.Builder().setRoot(root).build()
        val timeline = TimelineBuilders.Timeline.Builder()
            .addTimelineEntry(
                TimelineBuilders.TimelineEntry.Builder().setLayout(layout).build()
            )
            .build()
        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setTileTimeline(timeline)
            .setFreshnessIntervalMillis(15 * 60 * 1000L)
            .build()
        return Futures.immediateFuture(tile)
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> {
        val resources = ResourceBuilders.Resources.Builder()
            .setVersion(RESOURCES_VERSION)
            .build()
        return Futures.immediateFuture(resources)
    }

    private fun textLine(
        text: String,
        sizeSp: Float,
        color: Int,
        bold: Boolean,
    ): LayoutElementBuilders.Text {
        val fontStyle = LayoutElementBuilders.FontStyle.Builder()
            .setSize(DimensionBuilders.sp(sizeSp))
            .setColor(ColorBuilders.argb(color))
        if (bold) {
            fontStyle.setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
        }
        return LayoutElementBuilders.Text.Builder()
            .setText(text)
            .setFontStyle(fontStyle.build())
            .setMaxLines(1)
            .build()
    }

    companion object {
        private const val RESOURCES_VERSION = "1"
        private const val DEEP_GREEN = 0xFF0B3D2E.toInt()
        private const val GOLD = 0xFFD4AF37.toInt()
        private const val WHITE = 0xFFFFFFFF.toInt()
    }
}

private fun LayoutElementBuilders.Column.Builder.addSpacer(heightDp: Float) = addContent(
    LayoutElementBuilders.Spacer.Builder()
        .setHeight(DimensionBuilders.dp(heightDp))
        .build()
)
