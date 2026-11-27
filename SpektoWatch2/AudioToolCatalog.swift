import Foundation

enum AudioToolCategory: String, CaseIterable, Identifiable {
    case visualization
    case levels
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visualization: return "Visualisierung"
        case .levels: return "Pegel & Metriken"
        case .tools: return "Werkzeuge & Funktionen"
        }
    }
}

enum AudioToolLaunchDestination {
    case analysis
    case audioEditor
    case recordings
    case settings
}

struct AudioToolDescriptor: Identifiable {
    let type: AudioWidgetType
    let category: AudioToolCategory
    let supportedDisplayStyles: [WidgetDisplayStyle]
    let launchDestination: AudioToolLaunchDestination

    var id: String { type.rawValue }

    func supports(_ displayStyle: WidgetDisplayStyle) -> Bool {
        supportedDisplayStyles.contains(displayStyle)
    }
}

enum AudioToolCatalog {
    static let categories = AudioToolCategory.allCases

    /// Active tools in stable dashboard order. `AudioWidgetType` raw values
    /// remain unchanged because they are part of the persisted dashboard format.
    static let tools: [AudioToolDescriptor] = [
        .init(type: .spectrogram, category: .visualization, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .analysis),
        .init(type: .levelHistory, category: .levels, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .analysis),
        .init(type: .frequencyDisplay, category: .visualization, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .analysis),
        .init(type: .levelMeter, category: .levels, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .analysis),
        .init(type: .singleValue, category: .levels, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .analysis),
        .init(type: .toneGenerator, category: .tools, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .analysis),
        .init(type: .spektralanalyseLab, category: .tools, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .analysis),
        .init(type: .audioEditor, category: .tools, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .audioEditor),
        .init(type: .recordings, category: .tools, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .recordings),
        .init(type: .settings, category: .tools, supportedDisplayStyles: [.liveWidget, .icon], launchDestination: .settings)
    ]

    static var availableTypes: [AudioWidgetType] {
        tools.map(\.type)
    }

    static func tools(
        in category: AudioToolCategory,
        supporting displayStyle: WidgetDisplayStyle
    ) -> [AudioToolDescriptor] {
        tools.filter { $0.category == category && $0.supports(displayStyle) }
    }

    static func descriptor(for type: AudioWidgetType) -> AudioToolDescriptor? {
        tools.first { $0.type == type }
    }
}
