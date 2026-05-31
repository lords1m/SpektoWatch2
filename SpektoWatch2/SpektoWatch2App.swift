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
        UITestSeedConfiguration.applyIfNeeded()
#endif
        // Run the one-shot persistence migrations before any service
        // (AppServices and its sub-services) reads a key. After a UI-test
        // -ResetState wipe this just stamps the current schema version on an
        // empty defaults domain. (M13 task-8 Phase 2.)
        PersistenceMigrator.runMigrationsIfNeeded()
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

/// Seeds a deterministic set of recordings into the Recordings directory
/// so screenshot tests render a populated list/detail/waterfall instead
/// of the `ContentUnavailableView` empty state. Triggered by
/// `-SeedTestData YES` (paired with `-ResetState` so the seed lands on
/// a clean directory). Idempotent: re-running overwrites the same
/// metadata file with the same content.
private enum UITestSeedConfiguration {
    static func applyIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-SeedTestData") else { return }

        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let recordingsDir = documentsURL.appendingPathComponent("Recordings", isDirectory: true)
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }

        // Three sample recordings spread across age buckets so date-grouping
        // shows Today / Yesterday / Older sections in the screenshot.
        let now = Date()
        let calendar = Calendar.current
        let samples: [(name: String, hoursAgo: Int, duration: TimeInterval, laeq: Float, peak: Float, tags: [String])] = [
            ("Werkstatt-Lärm",     1,   62,  74.3,  88.6, ["Werkstatt", "Schleifmaschine"]),
            ("Bürogeräusche",     26,  185,  52.1,  64.2, ["Büro"]),
            ("Strassenverkehr",  170,  430,  68.4,  82.9, ["Aussen", "Verkehr"])
        ]

        let recordings: [Recording] = samples.map { sample in
            let startDate = calendar.date(byAdding: .hour, value: -sample.hoursAgo, to: now) ?? now
            let id = UUID()
            // Create an empty placeholder file so RecordingManager's file
            // checks don't fail downstream.
            let audioFileName = "\(id.uuidString).caf"
            let audioURL = recordingsDir.appendingPathComponent(audioFileName)
            if !fileManager.fileExists(atPath: audioURL.path) {
                fileManager.createFile(atPath: audioURL.path, contents: Data())
            }
            return Recording(
                id: id,
                name: sample.name,
                description: "",
                startDate: startDate,
                duration: sample.duration,
                audioFileName: audioFileName,
                laeqFast: sample.laeq,
                peakLevel: sample.peak,
                minLevel: sample.laeq - 25,
                tags: sample.tags
            )
        }

        let metadataURL = recordingsDir.appendingPathComponent("recordings_metadata_v2.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(recordings) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }
}
#endif
