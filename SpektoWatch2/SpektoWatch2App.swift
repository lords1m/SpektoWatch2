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
    @StateObject private var maskingProfileManager = MaskingProfileManager()

    init() {
#if DEBUG
        UITestLaunchConfiguration.applyIfNeeded()
#endif

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
                if let engine = engineContainer.engine,
                   let maskingEngine = engineContainer.maskingEngine {
                    ContentView()
                        .environmentObject(engine)
                        .environmentObject(filterManager)
                        .environmentObject(connectivityManager)
                        .environmentObject(recordingManager)
                        .environmentObject(fftConfiguration)
                        .environmentObject(maskingEngine)
                        .environmentObject(maskingProfileManager)
                } else {
                    GlassBackground()
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                // DispatchQueue.main.async guarantees execution after the first
                // frame is committed — more reliable than .task {} on first launch.
                DispatchQueue.main.async {
                    engineContainer.createEngine(fftConfiguration: fftConfiguration)
                }
            }
        }
    }
}

@MainActor
private final class AudioEngineContainer: ObservableObject {
    @Published private(set) var engine: AudioEngine?
    @Published private(set) var maskingEngine: MaskingEngine?

    private let filterManager: BandstopFilterManager
    private let connectivityManager: WatchConnectivityManager

    init(filterManager: BandstopFilterManager, connectivityManager: WatchConnectivityManager) {
        self.filterManager = filterManager
        self.connectivityManager = connectivityManager
    }

    @MainActor
    func createEngine(fftConfiguration: FFTConfiguration) {
        // Touch the shared Metal device now so all subsequent makeUIView calls
        // reuse it instead of each calling MTLCreateSystemDefaultDevice() fresh.
        _ = MetalWidgetManager.shared.sharedDevice
        let engine = AudioEngine(filterManager: filterManager, connectivityManager: connectivityManager)
        engine.applyFFTConfiguration(fftConfiguration)
        engine.scrollSpeed = .closest(to: fftConfiguration.hopSize)
        self.engine = engine
        self.maskingEngine = MaskingEngine(audioEngine: engine)
    }
}

#if DEBUG
private enum UITestLaunchConfiguration {
    static func applyIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ResetState") else { return }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }

        removeRecordingsDirectory()
    }

    private static func removeRecordingsDirectory() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let recordingsURL = documentsURL.appendingPathComponent("Recordings", isDirectory: true)
        try? fileManager.removeItem(at: recordingsURL)
    }
}
#endif
