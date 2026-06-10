import SwiftUI

/// When `false`, live Canvas views skip ingesting `liveData` so off-screen TabView
/// pages do not repaint while the user swipes between tabs.
private struct WatchTabLiveUpdatesActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var watchTabLiveUpdatesActive: Bool {
        get { self[WatchTabLiveUpdatesActiveKey.self] }
        set { self[WatchTabLiveUpdatesActiveKey.self] = newValue }
    }
}
