import CloudKit
import Foundation
import Observation

/// Syncing on the iPhone: on by default when signed in to iCloud (the Mac's is off by default), started after the
/// library is loaded. Builds without the iCloud entitlement (`SIGNING=none`, no `CLOUDKIT` condition) don't sync.
@MainActor
@Observable
final class MobileSync {
    private static let key = "syncsWithICloud"
    static let notInThisBuild = "Sync isn't available in this build."

    let controller: SyncController
    var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: Self.key)
            Task { await apply() }
        }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(model: AppModel, defaults: UserDefaults = .standard) {
        controller = SyncController(model: model)
        self.defaults = defaults
        isOn = defaults.object(forKey: Self.key) as? Bool ?? true
        controller.onTurnedOff = { [weak self] _ in self?.isOn = false }
        // Signing in to iCloud later starts it.
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOn, !self.controller.isRunning else { return }
                Task { await self.apply() }
            }
        }
    }

    /// Starts or stops syncing as the setting says.
    func apply() async {
        guard isOn else {
            await controller.stop(forgetting: true)
            return
        }
        guard !controller.isRunning else { return }
        #if CLOUDKIT
            if let problem = await CloudSyncEngine.accountProblem() {
                controller.setUnavailable(problem)
                return
            }
            await controller.start { [unowned self] state in
                CloudSyncEngine(state: state, controller: self.controller)
            }
        #else
            controller.setUnavailable(Self.notInThisBuild)
        #endif
    }
}
