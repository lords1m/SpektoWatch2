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
    }
}
