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
    @StateObject private var services = AppServices()

    init() {
#if DEBUG
        UITestLaunchConfiguration.applyIfNeeded()
#endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let engine = services.audioEngine,
                   let maskingEngine = services.maskingEngine {
                    // Consumer views still pull individual services via
                    // @EnvironmentObject for backward compatibility. M13
                    // task-1 only consolidates the producer side.
                    ContentView()
                        .environmentObject(services)
                        .environmentObject(engine)
                        .environmentObject(services.filterManager)
                        .environmentObject(services.connectivityManager)
                        .environmentObject(services.recordingManager)
                        .environmentObject(services.fftConfiguration)
                        .environmentObject(maskingEngine)
                        .environmentObject(services.maskingProfileManager)
                } else {
                    GlassBackground()
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                // DispatchQueue.main.async guarantees execution after the
                // first frame is committed — more reliable than .task {}
                // on first launch.
                DispatchQueue.main.async {
                    services.startAudio()
                }
            }
        }
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
