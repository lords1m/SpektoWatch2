import SwiftUI

/// Secondary watch surfaces grouped behind one page in the tab carousel.
struct WatchMoreFacesView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    WatchSpectrogramView()
                } label: {
                    Label("Spektrogramm", systemImage: "waveform.path.ecg")
                }
                NavigationLink {
                    WatchLevelMeterView()
                } label: {
                    Label("Pegel-Meter", systemImage: "gauge.with.needle")
                }
                NavigationLink {
                    WatchDashboardView()
                } label: {
                    Label("Modular", systemImage: "square.grid.2x2")
                }
                NavigationLink {
                    WatchRecordingsView()
                } label: {
                    Label("Aufnahmen", systemImage: "folder")
                }
            }
            .navigationTitle("Mehr")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(WatchAppBackground().ignoresSafeArea())
    }
}
