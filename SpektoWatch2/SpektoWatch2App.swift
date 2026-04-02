//
//  SpektoWatch2App.swift
//  SpektoWatch2
//
//  Created by Simeon Brandt on 22.01.26.
//

import Combine
import SwiftUI

@main
struct SpektoWatch2App: App {
    @StateObject private var filterManager: BandstopFilterManager
    @StateObject private var connectivityManager: WatchConnectivityManager
    @StateObject private var recordingManager: RecordingManager
    @StateObject private var fftConfiguration: FFTConfiguration
    @StateObject private var engineContainer: AudioEngineContainer

    init() {
        let fm = BandstopFilterManager()
        let cm = WatchConnectivityManager()
        let rm = RecordingManager()
        let fftConfig = FFTConfiguration()

        _filterManager = StateObject(wrappedValue: fm)
        _connectivityManager = StateObject(wrappedValue: cm)
        _recordingManager = StateObject(wrappedValue: rm)
        _fftConfiguration = StateObject(wrappedValue: fftConfig)
        _engineContainer = StateObject(wrappedValue: AudioEngineContainer(filterManager: fm, connectivityManager: cm))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let engine = engineContainer.engine {
                    ContentView()
                        .environmentObject(engine)
                        .environmentObject(filterManager)
                        .environmentObject(connectivityManager)
                        .environmentObject(recordingManager)
                        .environmentObject(fftConfiguration)
                } else {
                    GlassBackground()
                        .ignoresSafeArea()
                }
            }
            .task {
                await engineContainer.createEngine(fftConfiguration: fftConfiguration)
            }
        }
    }
}

private final class AudioEngineContainer: ObservableObject {
    @Published private(set) var engine: AudioEngine?

    private let filterManager: BandstopFilterManager
    private let connectivityManager: WatchConnectivityManager

    init(filterManager: BandstopFilterManager, connectivityManager: WatchConnectivityManager) {
        self.filterManager = filterManager
        self.connectivityManager = connectivityManager
    }

    func createEngine(fftConfiguration: FFTConfiguration) async {
        let fm = filterManager
        let cm = connectivityManager
        // Heavy init (vDSP_DFT setup, buffer allocation) on background thread
        let engine = await Task.detached(priority: .userInitiated) {
            AudioEngine(filterManager: fm, connectivityManager: cm)
        }.value
        // Configuration back on MainActor
        engine.applyFFTConfiguration(fftConfiguration)
        engine.scrollSpeed = .closest(to: fftConfiguration.hopSize)
        self.engine = engine
    }
}
