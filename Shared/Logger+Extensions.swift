import OSLog

extension Logger {
    private static let subsystem = "com.spektowatch"
    
    static let audioEngine = Logger(subsystem: subsystem, category: "audio")
    static let metal = Logger(subsystem: subsystem, category: "rendering")
    static let connectivity = Logger(subsystem: subsystem, category: "watch")
    static let filters = Logger(subsystem: subsystem, category: "filters")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let recording = Logger(subsystem: subsystem, category: "recording")
}
