import Foundation
import Observation

/// Syncing on the iPhone: on by default when signed in to iCloud (the Mac's is off by default), started after the
/// library is loaded (`SyncSwitch`). Builds without the iCloud entitlement (`SIGNING=none`, no `CLOUDKIT` condition)
/// don't sync.
@MainActor
@Observable
final class MobileSync {
    private static let key = "syncsWithICloud"

    let controller: SyncController
    var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: Self.key)
            syncSwitch.apply()
        }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var syncSwitch: SyncSwitch!

    init(model: AppModel, defaults: UserDefaults = .standard) {
        controller = SyncController(model: model)
        self.defaults = defaults
        isOn = defaults.object(forKey: Self.key) as? Bool ?? true
        syncSwitch = SyncSwitch(
            controller: controller, isOn: { [unowned self] in isOn }, turnOff: { [unowned self] in isOn = false },
            problem: {
                #if CLOUDKIT
                    await CloudSyncEngine.accountProblem()
                #else
                    SyncController.notInThisBuild
                #endif
            })
    }

    /// Starts or stops syncing as the setting says.
    func apply() {
        syncSwitch.apply()
    }

    /// Sends the changes made here and writes the sync state (before iOS suspends the app).
    func sendAndFlush() async {
        await controller.send()
        await controller.flush()
    }
}
