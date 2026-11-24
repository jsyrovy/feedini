import CloudKit
import Foundation

/// Turns syncing on and off as the platform's setting says, the same way on the Mac and the iPhone: starts it unless
/// it can't run here (then the status says why), stops it forgetting the sync state (turning it on again merges),
/// starts it after signing in to iCloud, and turns the setting off when syncing turned off by itself.
@MainActor
final class SyncSwitch {
    let controller: SyncController
    private let isOn: @MainActor () -> Bool
    /// Why syncing can't start now (the entitlement, the iCloud account); `nil` when it can.
    private let problem: @MainActor () async -> String?
    /// The latest start or stop; each waits for the previous one (awaited by tests).
    private(set) var task: Task<Void, Never>?

    init(
        controller: SyncController, isOn: @escaping @MainActor () -> Bool,
        turnOff: @escaping @MainActor () -> Void, problem: @escaping @MainActor () async -> String?
    ) {
        self.controller = controller
        self.isOn = isOn
        self.problem = problem
        controller.onTurnedOff = turnOff
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOn(), !self.controller.isRunning else { return }
                self.apply()
            }
        }
    }

    /// Starts or stops syncing as the setting says now (after the library is loaded, and after the setting changed).
    func apply() {
        task = Task { [previous = task] in
            await previous?.value
            await applyNow()
        }
    }

    private func applyNow() async {
        guard isOn() else {
            // Off already, or turned off by itself (the zone was deleted): stopped, and the status says why.
            let isStopped: Bool =
                switch controller.status {
                case .off, .failed: !controller.isRunning
                default: false
                }
            if !isStopped {
                await controller.stop(forgetting: true)
            }
            return
        }
        guard !controller.isRunning else { return }
        if let problem = await problem() {
            controller.setUnavailable(problem)
            return
        }
        await controller.start { [unowned controller] state in
            CloudSyncEngine(state: state, controller: controller)
        }
    }
}
