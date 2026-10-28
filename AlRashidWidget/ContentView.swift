//
//  ContentView.swift
//  AlRashid Prayer Widget
//
//  Target Membership: AlRashidWidget only.
//

import SwiftUI
import UIKit
import WidgetKit

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// The user's Light/Dark choice from Settings (App Group, shared with
    /// the widgets). Applied with preferredColorScheme below — this is
    /// what makes the whole UI actually follow the in-app setting.
    @AppStorage(AppAppearance.modeKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var modeRaw: String = AppAppearance.Mode.system.rawValue
    @State private var showSettings = false
    private let provider = PrayerProvider.standard

    var body: some View {
        TimelineView(.everyMinute) { context in
            let snapshot = provider.snapshot(at: context.date)
            let todaySchedule = provider.day(for: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HeaderView(today: todaySchedule, now: context.date) {
                        showSettings = true
                    }
                    NextPrayerCard(snapshot: snapshot)
                    ScheduleCard(snapshot: snapshot)
                    AlertsCard()
                    #if !PRIVACY_BUILD
                    actionButtons
                    #endif
                    FooterView()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background { AppBackground() }
        .preferredColorScheme(AppAppearance.Mode(rawValue: modeRaw)?.colorScheme)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear { refreshWidgets() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { refreshWidgets() }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                openURL(MosqueInfo.directionsURL)
            } label: {
                Label("Directions", systemImage: "car.fill")
            }
            .buttonStyle(ThemeButtonStyle(prominent: true))

            Button {
                openURL(MosqueInfo.websiteURL)
            } label: {
                Label("Website", systemImage: "globe")
            }
            .buttonStyle(ThemeButtonStyle(prominent: false))
        }
    }

    private func refreshWidgets() {
        provider.refreshCache()
        WidgetCenter.shared.reloadAllTimelines()
        AppServices.refresh()
    }
}

// MARK: - Header

private struct HeaderView: View {
    let today: PrayerDay
    let now: Date
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.adaptiveGold)
                    Text("Assalamu Alaikum")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(MosqueInfo.name)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                Text(today.hijriDate)
                    .font(.headline)
                    .foregroundStyle(Theme.adaptiveGold)
                Text(PrayerFormat.longDate(now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Next prayer card

private struct NextPrayerCard: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        let next = snapshot.next
        let caption = snapshot.isShowingTomorrow ? "Next prayer · Tomorrow" : "Next prayer"
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(caption, systemImage: next.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.adaptiveGold)
                Spacer()
                if next.isJumuah {
                    Text("JUMU'AH")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.adaptiveGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.adaptiveGold.opacity(0.25), in: Capsule())
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(next.name)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text(PrayerFormat.time(next.adhan))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
            }
            if let iqamah = next.iqamah {
                Label("\(next.iqamahLabel) at \(PrayerFormat.time(iqamah))", systemImage: "person.3.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.onSurfaceSecondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(timerInterval: snapshot.countdownRange, countsDown: true)
                    .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.adaptiveGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                GoldProgressBar(range: snapshot.progressRange)
                Text("until \(next.name) Adhan")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.onSurfaceMuted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(cornerRadius: 26)
    }
}

// MARK: - Schedule card

private struct ScheduleCard: View {
    let snapshot: PrayerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.isShowingTomorrow ? "Tomorrow's Prayer Times" : "Today's Prayer Times")
                    .font(.headline)
                    .foregroundStyle(Theme.onSurface)
                Spacer(minLength: 8)
                Text(PrayerFormat.shortDate(snapshot.day.date))
                    .font(.subheadline)
                    .foregroundStyle(Theme.onSurfaceSecondary)
            }
            HStack(spacing: 8) {
                Text("PRAYER").frame(maxWidth: .infinity, alignment: .leading)
                Text("ADHAN").frame(width: 86, alignment: .trailing)
                Text("IQAMAH").frame(width: 86, alignment: .trailing)
            }
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Theme.onSurfaceMuted)
            .padding(.horizontal, 12)
            VStack(spacing: 4) {
                ForEach(snapshot.day.slots) { slot in
                    ScheduleRow(slot: slot, isNext: snapshot.isNext(slot))
                }
            }
            if snapshot.day.isFriday {
                Label("Jumu'ah replaces Dhuhr · Khutbah at \(PrayerFormat.khutbahTime(on: snapshot.day.date))", systemImage: "building.columns.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.adaptiveGold)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(cornerRadius: 26)
    }
}

private struct ScheduleRow: View {
    let slot: PrayerSlot
    let isNext: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: slot.symbolName)
                    .font(.body.weight(.semibold))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.name)
                        .font(.body.weight(isNext ? .bold : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if slot.isJumuah {
                        Text("Khutbah time shown")
                            .font(.caption2)
                            .foregroundStyle(Theme.onSurfaceMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(PrayerFormat.time(slot.adhan))
                .frame(width: 86, alignment: .trailing)
            Text(slot.iqamah.map { PrayerFormat.time($0) } ?? "—")
                .frame(width: 86, alignment: .trailing)
        }
        .font(.body.weight(isNext ? .bold : .regular).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(rowColor)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            if isNext {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.adaptiveGold.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.adaptiveGold.opacity(0.65), lineWidth: 1)
                    }
            }
        }
    }

    private var rowColor: Color {
        if isNext { return Theme.adaptiveGold }
        return slot.prayer == .sunrise ? Theme.onSurfaceMuted : Theme.onSurface
    }
}

// MARK: - Footer

private struct FooterView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(MosqueInfo.address, systemImage: "mappin.and.ellipse")
            Label("Jumu'ah Khutbah every Friday at \(PrayerFormat.khutbahTime(on: .now))", systemImage: "building.columns")
            #if PRIVACY_BUILD
            Label("Private build — no external links, no tracking, nothing leaves this device.", systemImage: "lock.shield.fill")
            #endif
            Text("Adhan times are calculated on-device and calibrated to Al Rashid Mosque's published timetable. Iqamah times are fixed offsets from Adhan — please confirm with the mosque's official timetable.")
                .font(.caption)
                .padding(.top, 4)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Styling

/// Page background (v1.0.5, per the user's request): stays PURE BLACK in
/// Dark Mode and PURE WHITE in Light Mode, with only a faint wash of the
/// main theme color at the top so the page still feels like the app.
private struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            colorScheme == .dark ? Color.black : Color.white
            LinearGradient(
                colors: [Theme.primary.opacity(colorScheme == .dark ? 0.35 : 0.07), Color.clear],
                startPoint: .top, endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

private struct ThemeButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(prominent ? Theme.primaryDeep : Theme.onPrimaryText)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent
                        ? AnyShapeStyle(LinearGradient(colors: [Theme.lightGold, Theme.gold], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(LinearGradient(colors: [Theme.primaryBright, Theme.primary, Theme.primaryDeep], startPoint: .top, endPoint: .bottom)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.adaptiveGold.opacity(prominent ? 0 : 0.6), lineWidth: 1)
            }
            .shadow(color: Theme.primaryDeep.opacity(0.25), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Card surface (v1.0.5): a gradient of the user's main theme color in
/// Dark Mode, a clean white card with a main-color hairline in Light
/// Mode. Text on it uses the Theme.onSurface* colors, which flip with
/// the appearance and pass a contrast guard to stay readable in both.
private struct AdaptiveCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                CardSurfaceBackground()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Theme.adaptiveGold.opacity(0.45), Color.white.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(Theme.primary.opacity(0.25)),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: colorScheme == .dark ? Theme.primaryDeep.opacity(0.35) : Color.black.opacity(0.10),
                radius: 16, x: 0, y: 8
            )
    }
}

private extension View {
    func adaptiveCard(cornerRadius: CGFloat) -> some View {
        modifier(AdaptiveCardModifier(cornerRadius: cornerRadius))
    }
}

#Preview {
    ContentView()
}

// MARK: - Alerts settings

private struct AlertsCard: View {
    @AppStorage(AlertSettings.notificationsKey) private var notificationsOn = true
    @AppStorage(AlertSettings.liveActivityKey) private var liveActivityOn = true
    @State private var notificationsDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Alerts", systemImage: "bell.badge.fill")
                .font(.headline)
                .foregroundStyle(Theme.onSurface)

            Toggle(isOn: $notificationsOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adhan notifications")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.onSurface)
                    Text("A notification with sound at every prayer time, scheduled 7 days ahead and refreshed whenever you open the app.")
                        .font(.caption)
                        .foregroundStyle(Theme.onSurfaceSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.adaptiveGold)
            .onChange(of: notificationsOn) { _, isOn in
                AppServices.notificationsToggled(on: isOn)
                refreshDeniedState()
            }

            if notificationsOn && notificationsDenied {
                Label("Notifications are turned off for this app in iOS Settings — enable them there to hear the Adhan alerts.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.adaptiveGold)
            }

            Divider().overlay(Theme.hairline)

            Toggle(isOn: $liveActivityOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Activity")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.onSurface)
                    Text("A live countdown to the next prayer on your Lock Screen and Dynamic Island. It moves on to the following prayer by itself when a prayer time arrives, and also refreshes whenever you open the app.")
                        .font(.caption)
                        .foregroundStyle(Theme.onSurfaceSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.adaptiveGold)
            .onChange(of: liveActivityOn) { _, isOn in
                AppServices.liveActivityToggled(on: isOn)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(cornerRadius: 26)
        .task { refreshDeniedState() }
    }

    private func refreshDeniedState() {
        Task { notificationsDenied = await AdhanNotifications.authorizationDenied() }
    }
}

// MARK: - Settings (v1.0.5)

/// The dedicated Settings page: appearance (System/Light/Dark), theme
/// colors (main color, accent, text — each with preset swatches and a
/// full color picker), curated themes, save-your-own themes, the app
/// icon picker, per-prayer alert toggles (including Sunrise), privacy
/// notes, and Reset to Defaults. Everything is stored in the App Group,
/// so the Home Screen widgets and the Live Activity follow along.
private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private static var suite: UserDefaults {
        UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard
    }

    @AppStorage(AppAppearance.modeKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var modeRaw: String = AppAppearance.Mode.system.rawValue
    @AppStorage(AppAppearance.primaryKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var primaryHex: Int = Int(AppAppearance.defaultPrimaryHex)
    @AppStorage(AppAppearance.accentKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var accentHex: Int = Int(AppAppearance.defaultAccentHex)
    @AppStorage(AppAppearance.textKey, store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier))
    private var textHex: Int = Int(AppAppearance.defaultTextHex)

    @State private var savedThemes: [AppAppearance.ThemeChoice] = AppAppearance.savedThemes
    @State private var showSaveTheme = false
    @State private var newThemeName = ""
    @State private var currentIconName: String? = nil
    @State private var iconError: String? = nil
    @State private var showResetConfirm = false
    @State private var resetGeneration = 0

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                colorsSection
                themesSection
                iconSection
                prayerAlertsSection
                privacySection
                resetSection
            }
            .id(resetGeneration)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(AppAppearance.Mode(rawValue: modeRaw)?.colorScheme)
            .onAppear { currentIconName = UIApplication.shared.alternateIconName }
            .onChange(of: modeRaw) { _, _ in settingsChanged() }
            .onChange(of: primaryHex) { _, _ in settingsChanged() }
            .onChange(of: accentHex) { _, _ in settingsChanged() }
            .onChange(of: textHex) { _, _ in settingsChanged() }
            .alert("Save Theme", isPresented: $showSaveTheme) {
                TextField("Theme name", text: $newThemeName)
                Button("Save") { saveCurrentTheme() }
                Button("Cancel", role: .cancel) { newThemeName = "" }
            } message: {
                Text("Save the current colors as a theme you can re-apply any time.")
            }
            .confirmationDialog(
                "Reset all appearance and alert settings to the defaults?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset to Defaults", role: .destructive) { resetToDefaults() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: Sections

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $modeRaw) {
                ForEach(AppAppearance.Mode.allCases, id: \.rawValue) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows your iPhone's Light/Dark setting. Light keeps the background white; Dark keeps it black. The app icon follows too when your Home Screen icons are set to Auto.")
        }
    }

    private var colorsSection: some View {
        Section {
            ColorSettingRow(title: "Main color", caption: "Cards and buttons (the green)",
                            presets: AppAppearance.primaryPresets, hexValue: $primaryHex)
            ColorSettingRow(title: "Accent color", caption: "Countdowns and highlights (the gold)",
                            presets: AppAppearance.presets, hexValue: $accentHex)
            ColorSettingRow(title: "Text color", caption: "Text on the colored cards",
                            presets: AppAppearance.textPresets, hexValue: $textHex)
        } header: {
            Text("Theme Colors")
        } footer: {
            Text("Tap a circle for a preset, or use the color wheel on the right for any color. Text is automatically adjusted when needed so it always stays easy to read. The widgets use the same colors.")
        }
    }

    private var themesSection: some View {
        Section {
            ForEach(AppAppearance.presetThemes) { theme in
                ThemeChoiceRow(theme: theme, isSaved: false) { apply(theme) }
            }
            if !savedThemes.isEmpty {
                ForEach(savedThemes) { theme in
                    ThemeChoiceRow(theme: theme, isSaved: true) { apply(theme) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleteSavedTheme(theme) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            Button {
                newThemeName = ""
                showSaveTheme = true
            } label: {
                Label("Save current colors as a theme", systemImage: "bookmark.fill")
            }
        } header: {
            Text("Themes")
        } footer: {
            Text("Themes are ready-made color sets designed to look good together — main color, accent and text in one tap.")
        }
    }

    private var iconSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(Self.iconOptions) { option in
                    Button { setIcon(option) } label: {
                        VStack(spacing: 6) {
                            Image(option.previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            currentIconName == option.alternateName ? Color.accentColor : Color.primary.opacity(0.15),
                                            lineWidth: currentIconName == option.alternateName ? 2.5 : 1
                                        )
                                }
                            Text(option.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            if let iconError {
                Text(iconError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("App Icon")
        } footer: {
            Text("Pick the icon you like best. Changing the icon needs an installer that supports alternate icons.")
        }
    }

    private var prayerAlertsSection: some View {
        Section {
            ForEach(Prayer.allCases) { prayer in
                PrayerAlertRow(prayer: prayer) { settingsChanged() }
            }
        } header: {
            Text("Prayer Alerts")
        } footer: {
            Text("Choose which times play an alert. Sunrise is off by default — turn it on if you want a marker for the end of Fajr time. These work together with the Adhan notifications switch on the main screen.")
        }
    }

    private var privacySection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No data collected")
                    Text("No accounts, no tracking, no ads, no analytics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "hand.raised.fill")
            }
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Everything stays on this device")
                    Text("Prayer times are calculated on your iPhone. The app makes no network connections of its own, and your settings never leave the device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
            }
            #if PRIVACY_BUILD
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Private build")
                    Text("This build removes the Directions and Website buttons, so nothing opens outside the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "eye.slash.fill")
            }
            #endif
        } header: {
            Text("Privacy")
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("Restores the original appearance, colors, icon and prayer alerts. Your saved themes are kept.")
        }
    }

    // MARK: Actions

    private func settingsChanged() {
        PrayerProvider.standard.refreshCache()
        WidgetCenter.shared.reloadAllTimelines()
        AppServices.refresh()
    }

    private func apply(_ theme: AppAppearance.ThemeChoice) {
        modeRaw = theme.modeRaw
        primaryHex = Int(theme.primaryHex)
        accentHex = Int(theme.accentHex)
        textHex = Int(theme.textHex)
        settingsChanged()
    }

    private func saveCurrentTheme() {
        let name = newThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var theme = AppAppearance.ThemeChoice(
            id: UUID().uuidString, name: name,
            primaryHex: UInt32(primaryHex), accentHex: UInt32(accentHex),
            textHex: UInt32(textHex), modeRaw: modeRaw
        )
        theme.name = name
        savedThemes.append(theme)
        AppAppearance.savedThemes = savedThemes
        newThemeName = ""
    }

    private func deleteSavedTheme(_ theme: AppAppearance.ThemeChoice) {
        savedThemes.removeAll { $0.id == theme.id }
        AppAppearance.savedThemes = savedThemes
    }

    private func setIcon(_ option: IconOption) {
        iconError = nil
        guard UIApplication.shared.supportsAlternateIcons else {
            iconError = "This install doesn't support alternate icons."
            return
        }
        UIApplication.shared.setAlternateIconName(option.alternateName) { error in
            if let error {
                iconError = "Couldn't change the icon: \(error.localizedDescription)"
            } else {
                currentIconName = option.alternateName
            }
        }
    }

    private func resetToDefaults() {
        AppAppearance.resetToDefaults()
        PrayerAlertSettings.reset()
        UIApplication.shared.setAlternateIconName(nil)
        currentIconName = nil
        modeRaw = AppAppearance.Mode.system.rawValue
        primaryHex = Int(AppAppearance.defaultPrimaryHex)
        accentHex = Int(AppAppearance.defaultAccentHex)
        textHex = Int(AppAppearance.defaultTextHex)
        resetGeneration += 1
        settingsChanged()
    }

    // MARK: Icon options

    private struct IconOption: Identifiable {
        let alternateName: String?
        let displayName: String
        let previewImage: String
        var id: String { alternateName ?? "default" }
    }

    private static let iconOptions: [IconOption] = [
        IconOption(alternateName: nil, displayName: "Classic", previewImage: "IconPreviewDefault"),
        IconOption(alternateName: "AppIconMidnight", displayName: "Midnight", previewImage: "IconPreviewMidnight"),
        IconOption(alternateName: "AppIconDesert", displayName: "Desert", previewImage: "IconPreviewDesert"),
        IconOption(alternateName: "AppIconRose", displayName: "Rose", previewImage: "IconPreviewRose"),
        IconOption(alternateName: "AppIconRoyal", displayName: "Royal", previewImage: "IconPreviewRoyal"),
    ]
}

/// One color setting: preset swatches plus the system color picker.
private struct ColorSettingRow: View {
    let title: String
    let caption: String
    let presets: [(name: String, hex: UInt32)]
    @Binding var hexValue: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ColorPicker("Pick a custom \(title.lowercased())", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(presets, id: \.hex) { preset in
                        Button {
                            hexValue = Int(preset.hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                                }
                                .overlay {
                                    if UInt32(hexValue) == preset.hex {
                                        Circle()
                                            .strokeBorder(Color.accentColor, lineWidth: 3)
                                            .frame(width: 44, height: 44)
                                    }
                                }
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: UInt32(hexValue)) },
            set: { hexValue = Int($0.hexValue) }
        )
    }
}

/// A theme row: preview chip in the theme's own colors + name.
private struct ThemeChoiceRow: View {
    let theme: AppAppearance.ThemeChoice
    let isSaved: Bool
    let onApply: () -> Void

    var body: some View {
        Button(action: onApply) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(hex: theme.primaryHex).opacity(0.75), Color(hex: theme.primaryHex)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    Text("Aa")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(hex: theme.textHex))
                    Circle()
                        .fill(Color(hex: theme.accentHex))
                        .frame(width: 12, height: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(4)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(isSaved ? "Your saved theme · \(theme.mode.label)" : "Designed theme · \(theme.mode.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// One prayer's alert toggle, backed directly by the App Group setting.
private struct PrayerAlertRow: View {
    let prayer: Prayer
    let onToggle: () -> Void
    @AppStorage private var isOn: Bool

    init(prayer: Prayer, onToggle: @escaping () -> Void) {
        self.prayer = prayer
        self.onToggle = onToggle
        _isOn = AppStorage(
            wrappedValue: prayer != .sunrise,
            PrayerAlertSettings.key(for: prayer),
            store: UserDefaults(suiteName: PrayerProvider.appGroupIdentifier) ?? .standard
        )
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(prayer == .dhuhr ? "Dhuhr (Jumu'ah on Fridays)" : prayer.displayName)
            } icon: {
                Image(systemName: prayer.symbolName)
            }
        }
        .onChange(of: isOn) { _, _ in onToggle() }
    }
}
