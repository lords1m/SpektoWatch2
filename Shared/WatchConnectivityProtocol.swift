import Foundation

enum WatchConnectivityProtocol {
    enum MessageType: String, CaseIterable {
        case startRecording
        case stopRecording
        case gain
        case microphoneSource
        case frequencyWeighting
        case watchDashboardConfig
        /// JSON `WatchMeterLayoutConfig` under `Key.config` (M21 meter face).
        case watchMeterLayoutConfig
        /// `WatchMeasurementSourcePreference.rawValue` under `Key.value`.
        case watchMeasurementSourcePreference
        /// Envelope of non-audio app state (preset, recording flag,
        /// accent, theme, tone state). Added in M13 task-7. Payload is
        /// a JSON-encoded `WatchAppState` blob under
        /// `WatchConnectivityProtocol.Key.value`.
        case appStateUpdate
        /// Tag on a `transferFile` metadata dictionary for a standalone watch
        /// recording's audio or `.swr` file (M21 task-5). NOT a live stream —
        /// these are OS-queued deferred file transfers.
        case recordingFileTransfer
        /// Phone → watch acknowledgement (sent via `transferUserInfo`, which is
        /// queued and guaranteed) that a recording was ingested. Lets the watch
        /// mark the catalog entry `.synced`. Carries the recording id.
        case recordingSynced
    }

    /// Which file of a recording a `transferFile` is carrying.
    enum RecordingFileKind: String {
        case audio
        case measurement
    }

    enum BinaryPacketKind: UInt8 {
        case spectrogram = 0x01
    }

    enum BinaryPayload {
        case spectrogram(SpectrogramData)
    }

    enum Key {
        static let type = "type"
        static let value = "value"
        static let source = "source"
        static let config = "config"
        static let recordingId = "recordingId"
        static let fileKind = "fileKind"
        static let recordingMetadata = "recordingMetadata"
        /// Wire protocol version (UInt16). Absent on legacy peers / messages ⇒ 0.
        static let protocolVersion = "protocolVersion"
    }

    // MARK: - Protocol version (Phase 6, task 6.1)

    /// Current control-message / application-context protocol version.
    static let protocolVersion: UInt16 = 1
    /// Peers omitting `Key.protocolVersion` are pre-versioning builds.
    static let legacyProtocolVersion: UInt16 = 0

    static func protocolVersion(from message: [String: Any]) -> UInt16 {
        protocolVersionValue(from: message[Key.protocolVersion])
    }

    static func peerProtocolVersion(from applicationContext: [String: Any]) -> UInt16 {
        protocolVersionValue(from: applicationContext[Key.protocolVersion])
    }

    private static func protocolVersionValue(from raw: Any?) -> UInt16 {
        guard let raw else { return legacyProtocolVersion }
        if let version = raw as? UInt16 { return version }
        if let version = raw as? Int, version >= 0 { return UInt16(version) }
        if let version = raw as? NSNumber { return version.uint16Value }
        return legacyProtocolVersion
    }

    /// Stamps `Key.protocolVersion` onto an outgoing control message.
    static func stampedMessage(_ message: [String: Any]) -> [String: Any] {
        var stamped = message
        stamped[Key.protocolVersion] = NSNumber(value: protocolVersion)
        return stamped
    }

    /// Merges `Key.protocolVersion` into an `updateApplicationContext` payload.
    static func mergingProtocolVersion(into context: [String: Any]) -> [String: Any] {
        var context = context
        context[Key.protocolVersion] = NSNumber(value: protocolVersion)
        return context
    }

    // Watch live display data should remain fresher than one second in both
    // companion and wearable-source mode. Current adaptive intervals stay well
    // below this ceiling, including critical thermal state.
    static let maximumLiveDataAgeSeconds: TimeInterval = 1.0
    static let normalSpectrogramSendInterval: TimeInterval = 0.1
    static let fairThermalSpectrogramSendInterval: TimeInterval = 0.2
    static let lowPowerSpectrogramSendInterval: TimeInterval = 0.25
    static let seriousThermalSpectrogramSendInterval: TimeInterval = 0.33
    static let criticalThermalSpectrogramSendInterval: TimeInterval = 0.5

    static func makeRecordingStartMessage(source: MicrophoneSource? = nil) -> [String: Any] {
        var message: [String: Any] = [Key.type: MessageType.startRecording.rawValue]
        if let source {
            message[Key.source] = source.rawValue
        }
        return stampedMessage(message)
    }

    static func makeRecordingStopMessage(source: MicrophoneSource? = nil) -> [String: Any] {
        var message: [String: Any] = [Key.type: MessageType.stopRecording.rawValue]
        if let source {
            message[Key.source] = source.rawValue
        }
        return stampedMessage(message)
    }

    static func makeGainMessage(_ gain: Float) -> [String: Any] {
        stampedMessage([Key.type: MessageType.gain.rawValue, Key.value: gain])
    }

    static func makeMicrophoneSourceMessage(_ source: MicrophoneSource) -> [String: Any] {
        stampedMessage([Key.type: MessageType.microphoneSource.rawValue, Key.source: source.rawValue])
    }

    static func makeFrequencyWeightingMessage(_ weighting: String) -> [String: Any] {
        stampedMessage([Key.type: MessageType.frequencyWeighting.rawValue, Key.value: weighting])
    }

    static func makeWatchDashboardConfigMessage(_ configString: String) -> [String: Any] {
        stampedMessage([Key.type: MessageType.watchDashboardConfig.rawValue, Key.config: configString])
    }

    static func makeWatchMeterLayoutConfigMessage(_ configString: String) -> [String: Any] {
        stampedMessage([Key.type: MessageType.watchMeterLayoutConfig.rawValue, Key.config: configString])
    }

    static func makeWatchMeasurementSourcePreferenceMessage(_ preference: WatchMeasurementSourcePreference) -> [String: Any] {
        stampedMessage([
            Key.type: MessageType.watchMeasurementSourcePreference.rawValue,
            Key.value: preference.rawValue
        ])
    }

    static func measurementSourcePreference(from message: [String: Any]) -> WatchMeasurementSourcePreference? {
        guard let raw = message[Key.value] as? String else { return nil }
        return WatchMeasurementSourcePreference(rawValue: raw)
    }

    /// Build an appStateUpdate message envelope from a
    /// `WatchAppState` blob. Returns nil if the envelope fails to
    /// JSON-encode (shouldn't happen in practice — Codable values
    /// are all primitive).
    static func makeAppStateUpdateMessage(_ state: WatchAppState) -> [String: Any]? {
        guard let data = try? state.encode() else { return nil }
        return stampedMessage([Key.type: MessageType.appStateUpdate.rawValue, Key.value: data])
    }

    /// Decode an appStateUpdate message envelope. Returns nil for
    /// unknown schema versions (handled inside `WatchAppState.decode`)
    /// or malformed payloads.
    static func appStateUpdate(from message: [String: Any]) -> WatchAppState? {
        guard let data = message[Key.value] as? Data else { return nil }
        return WatchAppState.decode(data)
    }

    static func messageType(from message: [String: Any]) -> MessageType? {
        guard let type = message[Key.type] as? String else { return nil }
        return MessageType(rawValue: type)
    }

    static func gain(from message: [String: Any]) -> Float? {
        if let gain = message[Key.value] as? Float {
            return gain
        }
        if let number = message[Key.value] as? NSNumber {
            return number.floatValue
        }
        return nil
    }

    static func microphoneSource(from message: [String: Any]) -> MicrophoneSource? {
        guard let sourceString = message[Key.source] as? String else { return nil }
        return MicrophoneSource(rawValue: sourceString)
    }

    static func recordingSource(from message: [String: Any]) -> MicrophoneSource? {
        microphoneSource(from: message)
    }

    static func frequencyWeighting(from message: [String: Any]) -> String? {
        message[Key.value] as? String
    }

    static func dashboardConfigString(from message: [String: Any]) -> String? {
        message[Key.config] as? String
    }

    // MARK: - Standalone recording sync-back (M21 task-5)

    /// Metadata dictionary attached to a `transferFile` for one recording file.
    /// Carries the full `WatchRecordingMetadata` (JSON) on every transfer so the
    /// phone can build the catalog entry from whichever file arrives first.
    static func makeRecordingFileTransferMetadata(
        id: UUID,
        kind: RecordingFileKind,
        metadata: Data
    ) -> [String: Any] {
        stampedMessage([
            Key.type: MessageType.recordingFileTransfer.rawValue,
            Key.recordingId: id.uuidString,
            Key.fileKind: kind.rawValue,
            Key.recordingMetadata: metadata
        ])
    }

    static func recordingFileKind(fromTransfer metadata: [String: Any]) -> RecordingFileKind? {
        guard let raw = metadata[Key.fileKind] as? String else { return nil }
        return RecordingFileKind(rawValue: raw)
    }

    static func recordingId(fromTransfer metadata: [String: Any]) -> UUID? {
        guard let raw = metadata[Key.recordingId] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    static func recordingMetadata(fromTransfer metadata: [String: Any]) -> WatchRecordingMetadata? {
        guard let data = metadata[Key.recordingMetadata] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchRecordingMetadata.self, from: data)
    }

    /// Phone → watch "ingested, mark synced" acknowledgement payload.
    static func makeRecordingSyncedUserInfo(id: UUID) -> [String: Any] {
        stampedMessage([
            Key.type: MessageType.recordingSynced.rawValue,
            Key.recordingId: id.uuidString
        ])
    }

    static func syncedRecordingId(fromUserInfo userInfo: [String: Any]) -> UUID? {
        guard (userInfo[Key.type] as? String) == MessageType.recordingSynced.rawValue,
              let raw = userInfo[Key.recordingId] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    static func makeSpectrogramPacket(_ data: SpectrogramData) -> Data {
        var packet = Data([BinaryPacketKind.spectrogram.rawValue])
        packet.append(data.toBinaryData())
        return packet
    }

    static func decodeBinaryPayload(_ packet: Data) -> BinaryPayload? {
        guard let header = packet.first,
              let kind = BinaryPacketKind(rawValue: header) else {
            return nil
        }

        let payload = Data(packet.dropFirst())
        switch kind {
        case .spectrogram:
            guard let data = SpectrogramData.fromBinaryData(payload) else { return nil }
            return .spectrogram(data)
        }
    }
}
