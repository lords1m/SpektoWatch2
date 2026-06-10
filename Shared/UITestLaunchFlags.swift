import Foundation

/// Launch-argument gates for screenshot / audit tooling in UI tests.
public enum UITestLaunchFlags {
    public static var snapshotCatalog: Bool {
        ProcessInfo.processInfo.arguments.contains("-SnapshotCatalog")
    }

    /// Screenshot preset for widget-size grids (M9 audit).
    public static var widgetSizeScreenshotPresetAvailable: Bool {
        #if DEBUG
        return true
        #else
        return snapshotCatalog
        #endif
    }

    /// Auto-install widget-size screenshot layouts on dashboard load (UI tests).
    public static var installWidgetSizeScreenshotPreset: Bool {
        ProcessInfo.processInfo.arguments.contains("-InstallWidgetSizeScreenshotPreset")
    }
}
