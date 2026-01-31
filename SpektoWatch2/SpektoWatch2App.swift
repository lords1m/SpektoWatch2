//
//  SpektoWatch2App.swift
//  SpektoWatch2
//
//  Created by Simeon Brandt on 22.01.26.
//

import SwiftUI

@main
struct SpektoWatch2App: App {
    @StateObject private var filterManager: BandstopFilterManager
    @StateObject private var connectivityManager: WatchConnectivityManager
    @StateObject private var recordingManager: RecordingManager
    @StateObject private var audioEngine: AudioEngine
    @StateObject private var fftConfiguration: FFTConfiguration

    init() {
        // Create the managers first
        let fm = BandstopFilterManager()
        // Assuming WatchConnectivityManager is refactored to have a public init
        let cm = WatchConnectivityManager()
        let rm = RecordingManager()
        let fftConfig = FFTConfiguration()

        // Create the engine with its dependencies
        let engine = AudioEngine(
            filterManager: fm,
            connectivityManager: cm
        )

        // Initialize the StateObjects
        _filterManager = StateObject(wrappedValue: fm)
        _connectivityManager = StateObject(wrappedValue: cm)
        _recordingManager = StateObject(wrappedValue: rm)
        _audioEngine = StateObject(wrappedValue: engine)
        _fftConfiguration = StateObject(wrappedValue: fftConfig)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioEngine)
                .environmentObject(filterManager)
                .environmentObject(connectivityManager)
                .environmentObject(recordingManager)
                .environmentObject(fftConfiguration)
        }
    }
}
