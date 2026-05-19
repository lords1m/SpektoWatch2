//
//  SpektoWatchApp.swift
//  SpektoWatch Watch App
//
//  Created by Simeon Brandt on 22.01.26.
//

import SwiftUI

@main
struct SpektoWatchWatchApp: App {
    @StateObject private var audioEngine: WatchAudioEngine
    @StateObject private var connectivityManager: WatchConnectivityManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let cm = WatchConnectivityManager()
        _connectivityManager = StateObject(wrappedValue: cm)
        _audioEngine = StateObject(wrappedValue: WatchAudioEngine(connectivityManager: cm))
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(audioEngine)
                .environmentObject(connectivityManager)
        }
        // When the watch app backgrounds (wrist drop, system overlay, etc.),
        // ask the audio engine to stop recording UNLESS a `WKExtendedRuntimeSession`
        // is currently keeping the audio tap alive (handled inside the engine).
        // This prevents the silent battery drain the audit flagged:
        // `WKExtendedRuntimeSession` invalidation can leave the tap running
        // with no session backing it, and the wrist-down case was previously
        // unhandled entirely.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                audioEngine.handleSceneBackgrounded()
            }
        }
    }
}
