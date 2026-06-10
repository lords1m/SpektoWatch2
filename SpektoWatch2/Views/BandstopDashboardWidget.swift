import SwiftUI

/// Kompaktes Dashboard-Widget zum Aktivieren/Deaktivieren von Bandsperren
struct BandstopDashboardWidget: View {
    @EnvironmentObject var services: AppServices
    @State private var showFullSettings = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "waveform.path.badge.minus")
                    .font(.title3)
                    .foregroundColor(hasActiveFilters ? .orange : .gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bandsperre")
                        .font(.headline)
                    Text(filterStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showFullSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            
            // Quick Toggle Liste (max 3 anzeigen)
            if !services.filterManager.filters.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(services.filterManager.filters.prefix(3))) { filter in
                        BandstopQuickToggleRow(filter: filter)
                    }
                    
                    // "Mehr"-Button wenn mehr als 3 Filter
                    if services.filterManager.filters.count > 3 {
                        Button(action: { showFullSettings = true }) {
                            HStack {
                                Text("+\(services.filterManager.filters.count - 3) weitere")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                    }
                }
            } else {
                // Placeholder wenn keine Filter vorhanden
                Button(action: { showFullSettings = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Filter hinzufügen")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showFullSettings) {
            BandstopFilterSettingsView(filters: filterListBinding, onFilterChanged: services.filterManager.updateFilter)
        }
    }

    private var filterListBinding: Binding<[BandstopFilter]> {
        Binding(
            get: { services.filterManager.filters },
            set: { services.filterManager.filters = $0 }
        )
    }
    
    private var hasActiveFilters: Bool {
        services.filterManager.enabledFilters.count > 0
    }
    
    private var filterStatusText: String {
        let activeCount = services.filterManager.enabledFilters.count
        let totalCount = services.filterManager.filters.count
        
        if activeCount == 0 {
            return "Keine Filter aktiv"
        } else if activeCount == 1 {
            return "1 Filter aktiv"
        } else {
            return "\(activeCount)/\(totalCount) Filter aktiv"
        }
    }
}

/// Einzelne Zeile mit Toggle für schnelles Ein/Ausschalten
struct BandstopQuickToggleRow: View {
    let filter: BandstopFilter
    @EnvironmentObject private var services: AppServices
    
    var body: some View {
        HStack(spacing: 12) {
            // Color Indicator
            Circle()
                .fill(Color(hex: filter.color) ?? .red)
                .frame(width: 8, height: 8)
                .opacity(filter.isEnabled ? 1.0 : 0.3)
            
            // Filter Info
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(filter.isEnabled ? .primary : .secondary)
                
                Text(filter.formattedRange)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            Spacer()
            
            // Toggle Switch
            Toggle("", isOn: Binding(
                get: { filter.isEnabled },
                set: { _ in
                    services.filterManager.toggleFilter(id: filter.id)
                }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: Color(hex: filter.color) ?? .blue))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.tertiarySystemGroupedBackground))
        )
        .opacity(filter.isEnabled ? 1.0 : 0.7)
    }
}

// MARK: - Compact Mini Widget (für noch kleinere Bereiche)

struct BandstopMiniWidget: View {
    @EnvironmentObject var services: AppServices
    @State private var showFullSettings = false
    
    var body: some View {
        Button(action: { showFullSettings = true }) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.badge.minus")
                    .font(.body)
                    .foregroundColor(hasActiveFilters ? .orange : .gray)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bandsperre")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Quick Toggle für ersten Filter
                if let firstFilter = services.filterManager.filters.first {
                    Toggle("", isOn: Binding(
                        get: { firstFilter.isEnabled },
                        set: { _ in
                            services.filterManager.toggleFilter(id: firstFilter.id)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                    .scaleEffect(0.8)
                }
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showFullSettings) {
            BandstopFilterSettingsView(filters: filterListBinding, onFilterChanged: services.filterManager.updateFilter)
        }
    }

    private var filterListBinding: Binding<[BandstopFilter]> {
        Binding(
            get: { services.filterManager.filters },
            set: { services.filterManager.filters = $0 }
        )
    }
    
    private var hasActiveFilters: Bool {
        services.filterManager.enabledFilters.count > 0
    }
    
    private var statusText: String {
        let count = services.filterManager.enabledFilters.count
        return count == 0 ? "Inaktiv" : "\(count) aktiv"
    }
}

// MARK: - Filter Status Indicator (nur Icon + Badge)

struct BandstopStatusIndicator: View {
    @EnvironmentObject var services: AppServices
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "waveform.path.badge.minus")
                .font(.title2)
                .foregroundColor(hasActiveFilters ? .orange : .gray)
            
            if hasActiveFilters {
                Text("\(activeCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.orange))
                    .offset(x: 8, y: -8)
            }
        }
    }
    
    private var hasActiveFilters: Bool {
        services.filterManager.enabledFilters.count > 0
    }
    
    private var activeCount: Int {
        services.filterManager.enabledFilters.count
    }
}

// MARK: - Preview

struct BandstopDashboardWidget_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            BandstopDashboardWidget()
            BandstopMiniWidget()
            BandstopStatusIndicator()
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
        .previewLayout(.sizeThatFits)
        .environmentObject(AppServices.testFixture())
    }
}
