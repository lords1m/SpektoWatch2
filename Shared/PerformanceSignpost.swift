import os
import os.signpost

/// Shared `os_signpost` log for Instruments **Points of Interest**.
///
/// Use subsystem `com.spektowatch` and category `.pointsOfInterest` so traces
/// recorded with the POI instrument (or Blank + Points of Interest) show
/// migration, Metal prewarm, audio startup, and dashboard load intervals.
public enum PerformanceSignpost {
    public static let log = OSLog(
        subsystem: "com.spektowatch",
        category: .pointsOfInterest
    )

    @discardableResult
    public static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    public static func end(_ name: StaticString, signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: signpostID)
    }
}
