import AVFoundation
import Foundation

struct AudioSessionConfiguration: Equatable {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions

    static let measurementCapture = AudioSessionConfiguration(
        category: .record,
        mode: .measurement,
        options: []
    )
}

enum AudioSessionPlaybackPurpose: Equatable {
    case filePlayback
    case toneGenerator
    case maskingPreview

    var configuration: AudioSessionConfiguration {
        switch self {
        case .filePlayback:
            AudioSessionConfiguration(
                category: .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .mixWithOthers]
            )
        case .toneGenerator:
            AudioSessionConfiguration(
                category: .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .mixWithOthers]
            )
        case .maskingPreview:
            AudioSessionConfiguration(
                category: .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
        }
    }
}

protocol AudioSessionDriving: AnyObject {
    var configuration: AudioSessionConfiguration { get }
    func setConfiguration(_ configuration: AudioSessionConfiguration) throws
    func activate() throws
}

private final class AVAudioSessionDriver: AudioSessionDriving {
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }

    var configuration: AudioSessionConfiguration {
        AudioSessionConfiguration(
            category: session.category,
            mode: session.mode,
            options: session.categoryOptions
        )
    }

    func setConfiguration(_ configuration: AudioSessionConfiguration) throws {
        guard self.configuration != configuration else { return }
        try session.setCategory(
            configuration.category,
            mode: configuration.mode,
            options: configuration.options
        )
    }

    func activate() throws {
        try session.setActive(true)
    }
}

/// Serializes shared AVAudioSession configuration and owns the app's capture
/// and playback policies. Session operations are synchronous and never run on
/// an audio render callback.
final class AudioSessionCoordinator: @unchecked Sendable {
    static let shared = AudioSessionCoordinator()

    private let lock = NSLock()
    private let driver: AudioSessionDriving

    convenience init() {
        self.init(driver: AVAudioSessionDriver())
    }

    init(driver: AudioSessionDriving) {
        self.driver = driver
    }

    func configureMeasurementCapture<T>(
        preferredIOBufferDuration: TimeInterval,
        setInputGainToMaximum: Bool = true,
        configureInput: (AVAudioSession) throws -> T
    ) throws -> T {
        try withSessionLock {
            let session = AVAudioSession.sharedInstance()
            try configureMeasurementCaptureLocked(
                session: session,
                preferredIOBufferDuration: preferredIOBufferDuration,
                setInputGainToMaximum: setInputGainToMaximum,
                configureInput: configureInput
            )
        }
    }

    func prewarmMeasurementCapture(preferredIOBufferDuration: TimeInterval) throws {
        try withSessionLock {
            let current = driver.configuration
            guard current != .measurementCapture,
                  current.category != .playAndRecord,
                  current.category != .playback else { return }

            try configureMeasurementCaptureLocked(
                session: AVAudioSession.sharedInstance(),
                preferredIOBufferDuration: preferredIOBufferDuration,
                setInputGainToMaximum: false,
                configureInput: { _ in () }
            )
        }
    }

    func activateMeasurementCapture() throws {
        try withSessionLock {
            try driver.setConfiguration(.measurementCapture)
            try driver.activate()
        }
    }

    func selectInputDataSource(_ dataSource: AVAudioSessionDataSourceDescription) throws {
        try withSessionLock {
            try AVAudioSession.sharedInstance().setInputDataSource(dataSource)
        }
    }

    func setPreferredPolarPattern(
        _ pattern: AVAudioSession.PolarPattern,
        for dataSource: AVAudioSessionDataSourceDescription
    ) throws {
        try withSessionLock {
            try dataSource.setPreferredPolarPattern(pattern)
        }
    }

    func activatePlayback(for purpose: AudioSessionPlaybackPurpose) throws {
        try withSessionLock {
            let current = driver.configuration
            let configuration = purpose.configuration

            switch purpose {
            case .toneGenerator:
                // Tone output may coexist with a live measurement. Keep a
                // compatible active category instead of changing its mode.
                if current.category != .playAndRecord && current.category != .playback {
                    try driver.setConfiguration(configuration)
                }
            case .filePlayback:
                let needsConfiguration = (current.category != .playAndRecord && current.category != .playback)
                    || current.mode == .measurement
                    || (current.category == .playAndRecord
                        && !current.options.contains(.defaultToSpeaker))
                if needsConfiguration {
                    try driver.setConfiguration(configuration)
                }
            case .maskingPreview:
                if current != configuration {
                    try driver.setConfiguration(configuration)
                }
            }

            try driver.activate()
        }
    }

    private func withSessionLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func configureMeasurementCaptureLocked<T>(
        session: AVAudioSession,
        preferredIOBufferDuration: TimeInterval,
        setInputGainToMaximum: Bool,
        configureInput: (AVAudioSession) throws -> T
    ) throws -> T {
        try driver.setConfiguration(.measurementCapture)
        try session.setPreferredIOBufferDuration(preferredIOBufferDuration)
        if setInputGainToMaximum, session.isInputGainSettable {
            try session.setInputGain(1.0)
        }
        try driver.activate()
        return try configureInput(session)
    }
}
