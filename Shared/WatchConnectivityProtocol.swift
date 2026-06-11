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
        WatchConnectivityMessageCodec.encode(
            WatchConnectivityMessageCodec.RecordingControlPayload(source: source),
            type: .startRecording
        )
    }

    static func makeRecordingStopMessage(source: MicrophoneSource? = nil) -> [String: Any] {
        WatchConnectivityMessageCodec.encode(
            WatchConnectivityMessageCodec.RecordingControlPayload(source: source),
            type: .stopRecording
        )
    }

    static func makeGainMessage(_ gain: Float) -> [String: Any] {
        WatchConnectivityMessageCodec.encode(WatchConnectivityMessageCodec.GainPayload(gain: gain))
    }

    static func makeMicrophoneSourceMessage(_ source: MicrophoneSource) -> [String: Any] {
        WatchConnectivityMessageCodec.encode(WatchConnectivityMessageCodec.MicrophoneSourcePayload(source: source))
    }

    static func makeFrequencyWeightingMessage(_ weighting: String) -> [String: Any] {
        WatchConnectivityMessageCodec.encode(WatchConnectivityMessageCodec.FrequencyWeightingPayload(weighting: weighting))
    }

    static func makeWatchDashboardConfigMessage(_ configString: String) -> [String: Any] {
        WatchConnectivityMessageCodec.encode(
            WatchConnectivityMessageCodec.ConfigStringPayload(config: configString),
            type: .watchDashboardConfig
        )
    }

    static func makeWatchMeterLayoutConfigMessage(_ configString: String) -> [String: Any] {
        WatchConnectivityMessageCodec.encode(
            WatchConnectivityMessageCodec.ConfigStringPayload(config: configString),
            type: .watchMeterLayoutConfig
        )
    }

    static func makeWatchMeasurementSourcePreferenceMessage(_ preference: WatchMeasurementSourcePreference) -> [String: Any] {
        WatchConnectivityMessageCodec.encode(
            WatchConnectivityMessageCodec.MeasurementSourcePreferencePayload(preference: preference)
        )
    }

    static func measurementSourcePreference(from message: [String: Any]) -> WatchMeasurementSourcePreference? {
        WatchConnectivityMessageCodec.decodeMeasurementSourcePreference(from: message)?.preference
    }

    /// Build an appStateUpdate message envelope from a
    /// `WatchAppState` blob. Returns nil if the envelope fails to
    /// JSON-encode (shouldn't happen in practice — Codable values
    /// are all primitive).
    static func makeAppStateUpdateMessage(_ state: WatchAppState) -> [String: Any]? {
        WatchConnectivityMessageCodec.encode(WatchConnectivityMessageCodec.AppStateUpdatePayload(state: state))
    }

    /// Decode an appStateUpdate message envelope. Returns nil for
    /// unknown schema versions (handled inside `WatchAppState.decode`)
    /// or malformed payloads.
    static func appStateUpdate(from message: [String: Any]) -> WatchAppState? {
        WatchConnectivityMessageCodec.decodeAppStateUpdate(from: message)?.state
    }

    static func messageType(from message: [String: Any]) -> MessageType? {
        guard let type = message[Key.type] as? String else { return nil }
        return MessageType(rawValue: type)
    }

    static func gain(from message: [String: Any]) -> Float? {
        WatchConnectivityMessageCodec.decodeGain(from: message)?.gain
    }

    static func microphoneSource(from message: [String: Any]) -> MicrophoneSource? {
        WatchConnectivityMessageCodec.decodeMicrophoneSource(from: message)?.source
    }

    static func recordingSource(from message: [String: Any]) -> MicrophoneSource? {
        if let control = WatchConnectivityMessageCodec.decodeRecordingControl(from: message, type: .startRecording)
            ?? WatchConnectivityMessageCodec.decodeRecordingControl(from: message, type: .stopRecording) {
            return control.source
        }
        return microphoneSource(from: message)
    }

    static func frequencyWeighting(from message: [String: Any]) -> String? {
        WatchConnectivityMessageCodec.decodeFrequencyWeighting(from: message)?.weighting
    }

    static func dashboardConfigString(from message: [String: Any]) -> String? {
        WatchConnectivityMessageCodec.decodeConfigString(from: message, type: .watchDashboardConfig)?.config
            ?? WatchConnectivityMessageCodec.decodeConfigString(from: message, type: .watchMeterLayoutConfig)?.config
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
        WatchConnectivityMessageCodec.encode(
            WatchConnectivityMessageCodec.RecordingFileTransferPayload(id: id, kind: kind, metadata: metadata)
        )
    }

    static func recordingFileKind(fromTransfer metadata: [String: Any]) -> RecordingFileKind? {
        WatchConnectivityMessageCodec.decodeRecordingFileTransfer(from: metadata)?.kind
    }

    static func recordingId(fromTransfer metadata: [String: Any]) -> UUID? {
        WatchConnectivityMessageCodec.decodeRecordingFileTransfer(from: metadata)?.id
            ?? WatchConnectivityMessageCodec.decodeRecordingSynced(from: metadata)?.id
    }

    static func recordingMetadata(fromTransfer metadata: [String: Any]) -> WatchRecordingMetadata? {
        guard let data = WatchConnectivityMessageCodec.decodeRecordingFileTransfer(from: metadata)?.metadata else {
            return nil
        }
        return try? JSONDecoder().decode(WatchRecordingMetadata.self, from: data)
    }

    /// Phone → watch "ingested, mark synced" acknowledgement payload.
    static func makeRecordingSyncedUserInfo(id: UUID) -> [String: Any] {
        WatchConnectivityMessageCodec.encode(WatchConnectivityMessageCodec.RecordingSyncedPayload(id: id))
    }

    static func syncedRecordingId(fromUserInfo userInfo: [String: Any]) -> UUID? {
        WatchConnectivityMessageCodec.decodeRecordingSynced(from: userInfo)?.id
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
