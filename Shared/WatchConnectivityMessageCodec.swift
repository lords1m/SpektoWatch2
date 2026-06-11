import Foundation

/// Typed encode/decode for `WatchConnectivityProtocol` control messages.
///
/// Wire shape is unchanged from the legacy `[String: Any]` factories: flat
/// dictionaries with `type`, optional `value` / `source` / `config` / …, and
/// `protocolVersion`. Phase 6 task 6.2 — encoder and decoder live together so
/// they cannot drift.
enum WatchConnectivityMessageCodec {

    // MARK: - Payloads

    struct RecordingControlPayload: Equatable {
        var source: MicrophoneSource?
    }

    struct GainPayload: Equatable {
        var gain: Float
    }

    struct MicrophoneSourcePayload: Equatable {
        var source: MicrophoneSource
    }

    struct FrequencyWeightingPayload: Equatable {
        var weighting: String
    }

    struct ConfigStringPayload: Equatable {
        var config: String
    }

    struct MeasurementSourcePreferencePayload: Equatable {
        var preference: WatchMeasurementSourcePreference
    }

    struct AppStateUpdatePayload: Equatable {
        var state: WatchAppState
    }

    struct RecordingFileTransferPayload: Equatable {
        var id: UUID
        var kind: WatchConnectivityProtocol.RecordingFileKind
        var metadata: Data
    }

    struct RecordingSyncedPayload: Equatable {
        var id: UUID
    }

    // MARK: - Encode

    static func encode(
        _ payload: RecordingControlPayload,
        type: WatchConnectivityProtocol.MessageType
    ) -> [String: Any] {
        var message: [String: Any] = [WatchConnectivityProtocol.Key.type: type.rawValue]
        if let source = payload.source {
            message[WatchConnectivityProtocol.Key.source] = source.rawValue
        }
        return WatchConnectivityProtocol.stampedMessage(message)
    }

    static func encode(_ payload: GainPayload) -> [String: Any] {
        WatchConnectivityProtocol.stampedMessage([
            WatchConnectivityProtocol.Key.type: WatchConnectivityProtocol.MessageType.gain.rawValue,
            WatchConnectivityProtocol.Key.value: payload.gain
        ])
    }

    static func encode(_ payload: MicrophoneSourcePayload) -> [String: Any] {
        WatchConnectivityProtocol.stampedMessage([
            WatchConnectivityProtocol.Key.type: WatchConnectivityProtocol.MessageType.microphoneSource.rawValue,
            WatchConnectivityProtocol.Key.source: payload.source.rawValue
        ])
    }

    static func encode(_ payload: FrequencyWeightingPayload) -> [String: Any] {
        WatchConnectivityProtocol.stampedMessage([
            WatchConnectivityProtocol.Key.type: WatchConnectivityProtocol.MessageType.frequencyWeighting.rawValue,
            WatchConnectivityProtocol.Key.value: payload.weighting
        ])
    }

    static func encode(
        _ payload: ConfigStringPayload,
        type: WatchConnectivityProtocol.MessageType
    ) -> [String: Any] {
        WatchConnectivityProtocol.stampedMessage([
            WatchConnectivityProtocol.Key.type: type.rawValue,
            WatchConnectivityProtocol.Key.config: payload.config
        ])
    }

    static func encode(_ payload: MeasurementSourcePreferencePayload) -> [String: Any] {
        WatchConnectivityProtocol.stampedMessage([
            WatchConnectivityProtocol.Key.type: WatchConnectivityProtocol.MessageType.watchMeasurementSourcePreference.rawValue,
            WatchConnectivityProtocol.Key.value: payload.preference.rawValue
        ])
    }

    static func encode(_ payload: AppStateUpdatePayload) -> [String: Any]? {
        guard let data = try? payload.state.encode() else { return nil }
        return WatchConnectivityProtocol.stampedMessage([
            WatchConnectivityProtocol.Key.type: WatchConnectivityProtocol.MessageType.appStateUpdate.rawValue,
            WatchConnectivityProtocol.Key.value: data
        ])
    }

    static func encode(_ payload: RecordingFileTransferPayload) -> [String: Any] {
        WatchConnectivityProtocol.stampedMessage([
            WatchConnectivityProtocol.Key.type: WatchConnectivityProtocol.MessageType.recordingFileTransfer.rawValue,
            WatchConnectivityProtocol.Key.recordingId: payload.id.uuidString,
            WatchConnectivityProtocol.Key.fileKind: payload.kind.rawValue,
            WatchConnectivityProtocol.Key.recordingMetadata: payload.metadata
        ])
    }

    static func encode(_ payload: RecordingSyncedPayload) -> [String: Any] {
        WatchConnectivityProtocol.stampedMessage([
            WatchConnectivityProtocol.Key.type: WatchConnectivityProtocol.MessageType.recordingSynced.rawValue,
            WatchConnectivityProtocol.Key.recordingId: payload.id.uuidString
        ])
    }

    // MARK: - Decode

    static func decodeRecordingControl(
        from message: [String: Any],
        type: WatchConnectivityProtocol.MessageType
    ) -> RecordingControlPayload? {
        guard messageType(from: message) == type else { return nil }
        return RecordingControlPayload(source: microphoneSource(from: message))
    }

    static func decodeGain(from message: [String: Any]) -> GainPayload? {
        guard messageType(from: message) == .gain, let gain = gainValue(from: message) else { return nil }
        return GainPayload(gain: gain)
    }

    static func decodeMicrophoneSource(from message: [String: Any]) -> MicrophoneSourcePayload? {
        guard messageType(from: message) == .microphoneSource,
              let source = microphoneSource(from: message) else { return nil }
        return MicrophoneSourcePayload(source: source)
    }

    static func decodeFrequencyWeighting(from message: [String: Any]) -> FrequencyWeightingPayload? {
        guard messageType(from: message) == .frequencyWeighting,
              let weighting = message[WatchConnectivityProtocol.Key.value] as? String else { return nil }
        return FrequencyWeightingPayload(weighting: weighting)
    }

    static func decodeConfigString(
        from message: [String: Any],
        type: WatchConnectivityProtocol.MessageType
    ) -> ConfigStringPayload? {
        guard messageType(from: message) == type,
              let config = message[WatchConnectivityProtocol.Key.config] as? String else { return nil }
        return ConfigStringPayload(config: config)
    }

    static func decodeMeasurementSourcePreference(from message: [String: Any]) -> MeasurementSourcePreferencePayload? {
        guard messageType(from: message) == .watchMeasurementSourcePreference,
              let raw = message[WatchConnectivityProtocol.Key.value] as? String,
              let preference = WatchMeasurementSourcePreference(rawValue: raw) else { return nil }
        return MeasurementSourcePreferencePayload(preference: preference)
    }

    static func decodeAppStateUpdate(from message: [String: Any]) -> AppStateUpdatePayload? {
        guard messageType(from: message) == .appStateUpdate,
              let data = message[WatchConnectivityProtocol.Key.value] as? Data,
              let state = WatchAppState.decode(data) else { return nil }
        return AppStateUpdatePayload(state: state)
    }

    static func decodeRecordingFileTransfer(from metadata: [String: Any]) -> RecordingFileTransferPayload? {
        guard messageType(from: metadata) == .recordingFileTransfer,
              let id = recordingId(from: metadata),
              let kind = recordingFileKind(from: metadata),
              let data = metadata[WatchConnectivityProtocol.Key.recordingMetadata] as? Data else { return nil }
        return RecordingFileTransferPayload(id: id, kind: kind, metadata: data)
    }

    static func decodeRecordingSynced(from userInfo: [String: Any]) -> RecordingSyncedPayload? {
        guard messageType(from: userInfo) == .recordingSynced,
              let id = recordingId(from: userInfo) else { return nil }
        return RecordingSyncedPayload(id: id)
    }

    // MARK: - Wire comparison (characterization / round-trip tests)

    static func wireMessagesEqual(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, left) in lhs {
            guard let right = rhs[key] else { return false }
            if !wireValuesEqual(left, right) { return false }
        }
        return true
    }

    // MARK: - Private wire helpers

    private static func messageType(from message: [String: Any]) -> WatchConnectivityProtocol.MessageType? {
        guard let type = message[WatchConnectivityProtocol.Key.type] as? String else { return nil }
        return WatchConnectivityProtocol.MessageType(rawValue: type)
    }

    private static func gainValue(from message: [String: Any]) -> Float? {
        if let gain = message[WatchConnectivityProtocol.Key.value] as? Float {
            return gain
        }
        if let number = message[WatchConnectivityProtocol.Key.value] as? NSNumber {
            return number.floatValue
        }
        return nil
    }

    private static func microphoneSource(from message: [String: Any]) -> MicrophoneSource? {
        guard let sourceString = message[WatchConnectivityProtocol.Key.source] as? String else { return nil }
        return MicrophoneSource(rawValue: sourceString)
    }

    private static func recordingFileKind(from metadata: [String: Any]) -> WatchConnectivityProtocol.RecordingFileKind? {
        guard let raw = metadata[WatchConnectivityProtocol.Key.fileKind] as? String else { return nil }
        return WatchConnectivityProtocol.RecordingFileKind(rawValue: raw)
    }

    private static func recordingId(from metadata: [String: Any]) -> UUID? {
        guard let raw = metadata[WatchConnectivityProtocol.Key.recordingId] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    private static func wireValuesEqual(_ left: Any, _ right: Any) -> Bool {
        if let leftData = left as? Data, let rightData = right as? Data {
            if leftData == rightData { return true }
            // JSON blobs (e.g. WatchAppState) may differ in key order across encodes.
            if let leftObj = try? JSONSerialization.jsonObject(with: leftData),
               let rightObj = try? JSONSerialization.jsonObject(with: rightData) {
                return (leftObj as? NSDictionary)?.isEqual(rightObj) ?? false
            }
            return false
        }
        if let leftNumber = left as? NSNumber, let rightNumber = right as? NSNumber {
            return leftNumber.isEqual(to: rightNumber)
        }
        if let leftString = left as? String, let rightString = right as? String {
            return leftString == rightString
        }
        if let leftFloat = left as? Float, let rightFloat = right as? Float {
            return leftFloat == rightFloat
        }
        return String(describing: left) == String(describing: right)
    }
}
