package com.c12n.prayerappandroid.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.ScalingLazyColumn
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import androidx.wear.compose.material.rememberScalingLazyListState
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.delay

// Prayer YEG for Wear OS - standalone: prayer times for Edmonton are
// computed on the watch itself, no phone pairing required.

private val DeepGreen = Color(0xFF0B3D2E)
private val Gold = Color(0xFFD4AF37)
private val DimWhite = Color(0xFFBDBDBD)

private val WearColors = Colors(
    primary = Gold,
    primaryVariant = Color(0xFF9C7C1E),
    secondary = DeepGreen,
    secondaryVariant = Color(0xFF072A20),
    background = Color.Black,
    surface = DeepGreen,
    error = Color(0xFFCF6679),
    onPrimary = Color.Black,
    onSecondary = Color.White,
    onBackground = Color.White,
    onSurface = Color.White,
    onError = Color.Black,
    onSurfaceVariant = DimWhite,
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { PrayerYegWearApp() }
    }
}

/** A clock that ticks once per second while the app is in the foreground. */
@Composable
private fun rememberNow(): Instant {
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = Instant.now()
            delay(1000)
        }
    }
    return now
}

@Composable
fun PrayerYegWearApp() {
    MaterialTheme(colors = WearColors) {
        val navController = rememberSwipeDismissableNavController()
        SwipeDismissableNavHost(navController = navController, startDestination = "now") {
            composable("now") {
                NowScreen(
                    onOpenToday = { navController.navigate("today") },
                    onOpenAbout = { navController.navigate("about") },
                )
            }
            composable("today") { TodayScreen() }
            composable("about") { AboutScreen() }
        }
    }
}

@Composable
private fun NowScreen(onOpenToday: () -> Unit, onOpenAbout: () -> Unit) {
    val now = rememberNow()
    // The snapshot only changes when the minute rolls over.
    val minuteKey = now.epochSecond / 60
    val snapshot = remember(minuteKey) { PrayerProvider.snapshot(now) }
    val next = snapshot.next
    val listState = rememberScalingLazyListState()

    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 24.dp),
        ) {
            item {
                Text(
                    text = "NEXT PRAYER",
                    style = MaterialTheme.typography.caption2,
                    color = Gold,
                    textAlign = TextAlign.Center,
                )
            }
            item {
                Text(
                    text = next.name,
                    style = MaterialTheme.typography.title1,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                )
            }
            item {
                Text(
                    text = PrayerFormat.countdown(Duration.between(now, next.adhan)),
                    style = MaterialTheme.typography.display2,
                    fontWeight = FontWeight.Bold,
                    color = Gold,
                    textAlign = TextAlign.Center,
                )
            }
            item {
                Text(
                    text = "Adhan ${PrayerFormat.time(next.adhan)}",
                    style = MaterialTheme.typography.body1,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                )
            }
            if (next.iqamah != null) {
                item {
                    Text(
                        text = "${next.iqamahLabel} ${PrayerFormat.time(next.iqamah)}",
                        style = MaterialTheme.typography.body2,
                        color = DimWhite,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            item {
                Text(
                    text = snapshot.day.hijriDate,
                    style = MaterialTheme.typography.caption1,
                    color = DimWhite,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
            item {
                Chip(
                    onClick = onOpenToday,
                    label = { Text("Today's times") },
                    colors = ChipDefaults.chipColors(backgroundColor = DeepGreen),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 10.dp),
                )
            }
            item {
                Chip(
                    onClick = onOpenAbout,
                    label = { Text("About") },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun TodayScreen() {
    val now = rememberNow()
    val minuteKey = now.epochSecond / 60
    val today = remember(minuteKey) {
        PrayerProvider.computeDay(Edmonton.localDate(now))
    }
    val snapshot = remember(minuteKey) { PrayerProvider.snapshot(now) }
    val listState = rememberScalingLazyListState()

    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 24.dp),
        ) {
            item {
                Text(
                    text = "Today",
                    style = MaterialTheme.typography.title2,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                )
            }
            item {
                Text(
                    text = today.hijriDate,
                    style = MaterialTheme.typography.caption1,
                    color = Gold,
                    textAlign = TextAlign.Center,
                )
            }
            for (slot in today.slots) {
                item {
                    val isNext = !snapshot.isShowingTomorrow && snapshot.isNext(slot)
                    val isPast = !isNext && slot.adhan.isBefore(now)
                    val nameColor = when {
                        isNext -> Gold
                        isPast -> DimWhite
                        else -> Color.White
                    }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 2.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = if (isNext) "${slot.name}  •  next" else slot.name,
                            style = MaterialTheme.typography.title3,
                            fontWeight = if (isNext) FontWeight.Bold else FontWeight.Normal,
                            color = nameColor,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            text = if (slot.iqamah != null) {
                                "${PrayerFormat.time(slot.adhan)}  •  ${slot.iqamahLabel} ${PrayerFormat.time(slot.iqamah)}"
                            } else {
                                PrayerFormat.time(slot.adhan)
                            },
                            style = MaterialTheme.typography.body2,
                            color = if (isPast && !isNext) DimWhite else Color.White,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AboutScreen() {
    val listState = rememberScalingLazyListState()
    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 24.dp),
        ) {
            item {
                Text(
                    text = "Prayer YEG",
                    style = MaterialTheme.typography.title1,
                    fontWeight = FontWeight.Bold,
                    color = Gold,
                    textAlign = TextAlign.Center,
                )
            }
            item {
                Text(
                    text = "Prayer times for Edmonton, computed on this watch. No phone needed.",
                    style = MaterialTheme.typography.body2,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                )
            }
            item {
                Text(
                    text = "Prayer time data is publicly accessible from the Al Rashid Mosque website.",
                    style = MaterialTheme.typography.caption1,
                    color = DimWhite,
                    textAlign = TextAlign.Center,
                )
            }
            item {
                Text(
                    text = "Version 1.0.0",
                    style = MaterialTheme.typography.caption2,
                    color = DimWhite,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
