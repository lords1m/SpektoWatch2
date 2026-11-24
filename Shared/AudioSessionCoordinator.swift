import Foundation
import AVFoundation
import Combine
import OSLog

/// The subset of `AVAudioSession` the coordinator drives. Lets tests inject a
/// fake session and assert the resulting category/mode.
protocol AudioSessionConfiguring: AnyObject {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: AudioSessionConfiguring {}

/// M22 task-4 (AS-1 / AS-3 / AS-4 / AS-6): the single owner of the shared
/// `AVAudioSession` category, mode and activation on each platform.
///
/// Every consumer — live capture, the tone generators, recording playback and
/// the masking preview — holds a **lease**. The coordinator derives one
/// combined configuration from the set of active leases, re-applies it when a
/// lease is acquired or released (so ending a tone restores pure measurement
/// capture, and starting capture never kills a running tone), and republishes
/// interruption / route-change / media-services-reset notifications as
/// `events`.
///
/// Thread-safe: capture configures the session from a background queue.
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    enum Client: String, Hashable, CaseIterable {
        case capture
        case tone
        case playback
        case maskingPreview

        var producesOutput: Bool { self != .capture }
    }

    struct Lease: Hashable {
        let id: UUID
        let client: Client
    }

    struct Configuration: Equatable {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    enum SessionEvent: Equatable {
        case interruptionBegan
        /// `shouldResume` mirrors `AVAudioSession.InterruptionOptions.shouldResume`.
        case interruptionEnded(shouldResume: Bool)
        case routeChanged(reason: UInt)
        case mediaServicesReset
    }

    private let session: AudioSessionConfiguring
    private let lock = NSLock()
    private var leases: [UUID: Client] = [:]
    private var appliedConfiguration: Configuration?
    private var isActive = false
    private let subject = PassthroughSubject<SessionEvent, Never>()
    private var observers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: "com.spektowatch", category: "audio.session")

    /// Interruption / route / media-reset events. Delivered on the main queue.
    var events: AnyPublisher<SessionEvent, Never> { subject.eraseToAnyPublisher() }

    init(session: AudioSessionConfiguring = AVAudioSession.sharedInstance(), observeSystemNotifications: Bool = true) {
        self.session = session
        if observeSystemNotifications {
            installObservers()
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Configuration table

    /// Combined configuration for a set of active clients (`nil` = no lease,
    /// session can be deactivated).
    ///
    /// - capture only → `.record` / `.measurement`
    /// - capture + any output → `.playAndRecord` / `.measurement`
    ///   (+ `.defaultToSpeaker` on iOS) — measurement mode keeps AGC and
    ///   voice processing off while a tone plays (AS-3).
    /// - output only → `.playback` / `.default`
    static func configuration(for clients: Set<Client>) -> Configuration? {
        guard !clients.isEmpty else { return nil }
        let hasCapture = clients.contains(.capture)
        let hasOutput = clients.contains { $0.producesOutput }
        if hasCapture && hasOutput {
            #if os(iOS)
            return Configuration(category: .playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            #else
            return Configuration(category: .playAndRecord, mode: .measurement, options: [.mixWithOthers])
            #endif
        }
        if hasCapture {
            return Configuration(category: .record, mode: .measurement, options: [])
        }
        return Configuration(category: .playback, mode: .default, options: [.mixWithOthers])
    }

    // MARK: - Leases

    /// Registers `client` and applies the resulting configuration. Throws (and
    /// registers nothing) if the session rejects the configuration.
    func acquire(_ client: Client) throws -> Lease {
        lock.lock()
        defer { lock.unlock() }
        let lease = Lease(id: UUID(), client: client)
        leases[lease.id] = client
        do {
            try applyLocked()
        } catch {
            leases[lease.id] = nil
            try? applyLocked()
            throw error
        }
        return lease
    }

    /// Ends a lease and restores the configuration of the remaining leases
    /// (deactivating the session when none remain). Idempotent.
    func release(_ lease: Lease) {
        lock.lock()
        defer { lock.unlock() }
        guard leases.removeValue(forKey: lease.id) != nil else { return }
        do {
            try applyLocked()
        } catch {
            log.error("Audio session restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-applies the current configuration (after an interruption or a media
    /// services reset, where the system dropped our session state).
    func reapply() throws {
        lock.lock()
        defer { lock.unlock() }
        appliedConfiguration = nil
        isActive = false
        try applyLocked()
    }

    /// Clients that currently hold a lease.
    var activeClients: Set<Client> {
        lock.lock()
        defer { lock.unlock() }
        return Set(leases.values)
    }

    /// Configuration last applied to the session (`nil` when inactive).
    var currentConfiguration: Configuration? {
        lock.lock()
        defer { lock.unlock() }
        return isActive ? appliedConfiguration : nil
    }

    private func applyLocked() throws {
        guard let target = Self.configuration(for: Set(leases.values)) else {
            if isActive {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                isActive = false
            }
            appliedConfiguration = nil
            return
        }
        if target != appliedConfiguration {
            try session.setCategory(target.category, mode: target.mode, options: target.options)
            appliedConfiguration = target
        }
        if !isActive {
            try session.setActive(true, options: [])
            isActive = true
        }
    }

    // MARK: - System notifications (AS-1)

    private func installObservers() {
        let center = NotificationCenter.default
        let main = OperationQueue.main
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.lock.lock(); self.isActive = false; self.lock.unlock()
                self.subject.send(.interruptionBegan)
            case .ended:
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                self.subject.send(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
            @unknown default:
                break
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            self?.subject.send(.routeChanged(reason: reason))
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: main) { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.appliedConfiguration = nil; self.isActive = false; self.lock.unlock()
            self.subject.send(.mediaServicesReset)
        })
    }
}
