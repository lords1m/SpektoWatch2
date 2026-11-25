import SwiftUI

struct WatchRecordingRow: View {
    let recording: WatchRecordingMetadata

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(WatchRecordingFormat.subtitle(for: recording))
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer()
            WatchSyncStateBadge(state: recording.syncState)
        }
        .padding(.vertical, 2)
    }
}
