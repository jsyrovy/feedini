import Foundation
import Observation

/// Tells whether a newer Feedini has been released: on demand (`checkNow()`) and, when switched on (`setDaily(_:)`),
/// right away and then once a day. It only reports what it found; installing is up to the user.
@MainActor
@Observable
final class UpdateChecker {
    static let interval = Duration.seconds(24 * 60 * 60)

    enum State: Equatable {
        /// Not checked yet.
        case unchecked
        case checking
        /// The running version is the latest.
        case upToDate(AppVersion)
        case available(LatestRelease)
        case failed(String)
    }

    private(set) var state = State.unchecked

    /// The newer release found by the last check, if any.
    var available: LatestRelease? {
        guard case .available(let release) = state else { return nil }
        return release
    }

    private let currentVersion: AppVersion?

    @ObservationIgnored private let fetch: @Sendable () async throws -> LatestRelease
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var checksDaily = false
    /// The latest daily loop; once cancelled, it may still be ending.
    @ObservationIgnored private var daily: Task<Void, Never>?

    /// `fetch` and `sleep` are replaced in tests.
    init(
        currentVersion: AppVersion? = .current,
        fetch: @escaping @Sendable () async throws -> LatestRelease = { try await LatestRelease.fetch() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.currentVersion = currentVersion
        self.fetch = fetch
        self.sleep = sleep
    }

    /// Checks right away; does nothing while a check runs.
    func checkNow() async {
        guard state != .checking else { return }
        let previous = state
        state = .checking
        do {
            let release = try await fetch()
            if let currentVersion, release.version <= currentVersion {
                state = .upToDate(currentVersion)
            } else {
                state = .available(release)
            }
            Log.updates.info("Latest release: \(release.version, privacy: .public)")
        } catch is CancellationError {
            state = previous
        } catch {
            state = .failed("\(error)")
            Log.updates.error("Checking for updates failed: \(error, privacy: .public)")
        }
    }

    /// Starts or stops checking once a day. Starting checks right away; stopping cancels a check of the loop. A started
    /// loop waits for a stopped one, so its check isn't skipped as one already running.
    func setDaily(_ on: Bool) {
        guard on != checksDaily else { return }
        checksDaily = on
        let previous = daily
        previous?.cancel()
        guard on else { return }
        daily = Task { [weak self, sleep] in
            await previous?.value
            while !Task.isCancelled {
                await self?.checkNow()
                do {
                    try await sleep(Self.interval)
                } catch {
                    return
                }
            }
        }
    }
}
