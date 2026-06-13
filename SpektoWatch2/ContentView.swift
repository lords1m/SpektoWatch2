import SwiftUI

private let isDebugBuild: Bool = {
#if DEBUG
    return true
#else
    return false
#endif
}()

struct ContentView: View {
    @EnvironmentObject var services: AppServices
    // Owned here so ModularDashboardView re-inits don't allocate throwaway
    // managers (its @StateObject would discard all but the first).
    @StateObject private var dashboardManager = DashboardManager()

    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()
            ModularDashboardView(
                audioEngine: services.audioEngine!,
                connectivityManager: services.connectivityManager,
                dashboardManager: dashboardManager
            )

            if isDebugBuild {
                // Build indicator kept out of the header/control-bar zones so it
                // never occludes the title or the live controls. Bottom-leading,
                // floated above the control bar, low-prominence.
                VStack {
                    Spacer()
                    HStack {
                        Text("DEBUG")
                            .font(.caption2.weight(.bold))
                            .tracking(0.5)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.yellow.opacity(0.85))
                            .foregroundColor(.black)
                            .cornerRadius(6)
                        Spacer()
                    }
                    // Clears the control bar in its tallest (compact two-line)
                    // layout. Debug-only heuristic — not worth a GeometryReader
                    // to read the live footer height.
                    .padding(.bottom, 150)
                }
                .padding(.horizontal, 16)
                .allowsHitTesting(false)
            }
        }
    }
}
