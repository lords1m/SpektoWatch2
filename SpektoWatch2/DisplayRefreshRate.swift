import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Main-thread lookup of the display's maximum refresh rate, used to derive the
/// display-matched live FFT hop (`RealtimeHop.displayMatched`). Read only on
/// the main actor and handed to the engine as a plain `Int`, so the audio
/// thread never touches UIKit.
enum DisplayRefreshRate {
    /// Fallback when no window scene is connected yet (app launch, unit tests).
    static let fallbackFramesPerSecond = 60

    /// Maximum frames per second of the foreground screen (120 on ProMotion,
    /// 60 otherwise). Low Power Mode caps ProMotion panels at 60 Hz, so the
    /// value is clamped there too — matching the hop to 120 Hz while the
    /// display runs at 60 would only double the FFT cost.
    @MainActor
    static func maximumFramesPerSecond() -> Int {
        var fps = fallbackFramesPerSecond
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        if let screenFPS = scene?.screen.maximumFramesPerSecond, screenFPS > 0 {
            fps = screenFPS
        }
        #endif
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            fps = min(fps, 60)
        }
        return fps
    }
}
