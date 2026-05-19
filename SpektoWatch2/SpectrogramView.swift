import SwiftUI

// Historical note: this file used to contain `struct SpectrogramView` — a
// legacy entry point that itself nested `ModularDashboardView`, with all the
// audio-engine subscriptions duplicated. It was unreachable from the live
// navigation graph (only `ContentView → ModularDashboardView` is on the live
// path) and was deleted in M6 task-9. The `SpectrogramTimeSpan` enum below
// is still used by widget settings, the LAF graph, the spectrogram widget,
// and the high-end spectrogram adapter, so it stayed here.

enum SpectrogramTimeSpan: Int, CaseIterable, Identifiable {
    case seconds1 = 1
    case seconds2 = 2
    case seconds5 = 5
    case seconds10 = 10
    case seconds20 = 20
    case seconds30 = 30
    case seconds60 = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .seconds1: return "1s"
        case .seconds2: return "2s"
        case .seconds5: return "5s"
        case .seconds10: return "10s"
        case .seconds20: return "20s"
        case .seconds30: return "30s"
        case .seconds60: return "60s"
        }
    }
}
