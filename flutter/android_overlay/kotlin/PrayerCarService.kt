package com.c12n.alrashidwidget

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator

/// Android Auto (v2.0.0, workstream 8): a read-only ListTemplate —
/// next prayer + countdown, then today's remaining times with
/// Iqamah. Driving-distraction-safe: no actions, no input.
///
/// SIDELOAD NOTE: Android Auto only shows apps from unknown sources
/// after enabling "Unknown sources" in Android Auto's developer
/// settings — expected for a sideload build and noted in the
/// release notes. The all-hosts validator below is what lets the
/// service run in that developer context; a Play-distributed build
/// would use the default allowlist validator instead.
class PrayerCarService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session = PrayerCarSession()
}

class PrayerCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen = PrayerCarScreen(carContext)
}

class PrayerCarScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val model = WidgetData.current(carContext)
        val list = ItemList.Builder()
        list.addItem(
            Row.Builder()
                .setTitle("${model.nextName} — ${model.nextTime}")
                .addText("Next prayer · in ${model.countdownText}")
                .build()
        )
        for (row in model.rows) {
            val adhan = WidgetData.formatTime(row.adhan)
            val detail = row.iqamah?.let {
                "Adhan $adhan · Iqamah ${WidgetData.formatTime(it)}"
            } ?: "Adhan $adhan"
            list.addItem(
                Row.Builder().setTitle(row.name).addText(detail).build()
            )
        }
        return ListTemplate.Builder()
            .setSingleList(list.build())
            .setTitle("Al Rashid Prayer")
            .build()
    }
}
