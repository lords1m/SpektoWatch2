import SwiftUI

/// Secondary watch surfaces grouped behind one page in the tab carousel.
struct WatchMoreFacesView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    WatchMeterLayoutSettingsView()
                } label: {
                    Label("Meter-Layout", systemImage: "square.grid.3x3.square")
                }

                NavigationLink {
                    WatchDashboardLayoutSettingsView()
                } label: {
                    Label("Dashboard-Pegel", systemImage: "gauge.with.needle")
                }

                NavigationLink {
                    WatchMeasurementSourceSettingsView()
                } label: {
                    Label("Messquelle", systemImage: "mic.and.signal.meter")
                }

                NavigationLink {
                    WatchTonegeneratorFace()
                } label: {
                    Label("Tongenerator", systemImage: "waveform.path")
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
