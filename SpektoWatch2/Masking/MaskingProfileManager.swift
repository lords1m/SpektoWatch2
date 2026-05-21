import Combine
import Foundation
import SwiftUI

// Persistent store for saved masking profiles.
// Profiles are written as JSON to Documents/Masking/profiles.json.
@MainActor
final class MaskingProfileManager: ObservableObject {
    @Published private(set) var profiles: [MaskingProfile] = []

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Masking", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")
        load()
    }

    func save(_ profile: MaskingProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.insert(profile, at: 0)
        }
        persist()
    }

    func delete(offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MaskingProfile].self, from: data) else { return }
        profiles = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
