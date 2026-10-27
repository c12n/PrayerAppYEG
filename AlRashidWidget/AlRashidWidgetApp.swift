//
//  AlRashidWidgetApp.swift
//  AlRashid Prayer Widget
//
//  App target: AlRashidWidget (com.c12n.alrashidwidget), iOS 17.0+
//  Target Membership: AlRashidWidget only.
//  Shared files (also in this target): PrayerCalculator.swift, PrayerModels.swift
//  Capability: App Groups -> group.com.c12n.alrashidwidget
//

import SwiftUI

@main
struct AlRashidWidgetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.gold)
        }
    }
}
