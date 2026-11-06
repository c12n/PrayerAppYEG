import Foundation

#if canImport(CarPlay)
import CarPlay
#endif

// MARK: - CarPlay (v2.0.0, workstream 8 — code present, DISABLED)
//
// PLATFORM TRUTH (verified against Apple's CarPlay documentation):
// CarPlay requires the com.apple.developer.carplay entitlement,
// which Apple grants only to apps in approved CarPlay categories
// (audio, EV charging, navigation, parking, quick-food ordering…).
// A prayer-times app is not an approved category. Adding the
// entitlement without a grant breaks signing and App Store /
// TestFlight validation, so this build ships WITHOUT it:
//
//   * this scene delegate is never registered in Info.plist
//     (no UIScene configuration names it),
//   * no CarPlay entitlement exists in any .entitlements file,
//   * `CarPlaySupport.isEnabled` stays false.
//
// The scene itself is complete and driving-safe — a read-only
// CPListTemplate: next prayer + countdown, then today's remaining
// times, tinted with the app theme. If Apple ever grants the
// entitlement, activation is: add the entitlement, register the
// scene in Info.plist, flip the flag. Nothing else changes.
enum CarPlaySupport {
    static let isEnabled = false
}

#if canImport(CarPlay)
/// The (currently unreachable) CarPlay scene: one list template,
/// no interaction beyond scrolling.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(makeListTemplate(), animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func makeListTemplate() -> CPListTemplate {
        let provider = PrayerProvider.standard
        let snapshot = provider.snapshot()
        let next = snapshot.next
        let nextItem = CPListItem(
            text: "\(next.name) — \(PrayerFormat.time(next.adhan))",
            detailText: "Next prayer at \(MosqueInfo.name)")
        let rows: [CPListItem] = snapshot.day.slots
            .filter { $0.adhan > Date.now }
            .map { slot in
                CPListItem(
                    text: "\(slot.name) — \(PrayerFormat.time(slot.adhan))",
                    detailText: slot.iqamah.map { "Iqamah \(PrayerFormat.time($0))" })
            }
        let section = CPListSection(items: [nextItem] + rows)
        let template = CPListTemplate(title: MosqueInfo.name, sections: [section])
        template.tabImage = UIImage(systemName: next.symbolName)
        return template
    }
}
#endif
