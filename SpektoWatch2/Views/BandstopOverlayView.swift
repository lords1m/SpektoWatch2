import SwiftUI

/// Overlay-View, die aktive Bandsperre-Filter über das Spektrogramm zeichnet
struct BandstopOverlayView: View {
    let filters: [BandstopFilter]
    let frequencyRange: ClosedRange<Float>
    let geometryWidth: CGFloat
    let geometryHeight: CGFloat
    
    var body: some View {
        ZStack {
            // Zeichne jeden aktiven Filter als halbtransparente rote Region
            ForEach(filters.filter { $0.isEnabled }) { filter in
                BandstopRegionView(
                    filter: filter,
                    frequencyRange: frequencyRange,
                    width: geometryWidth,
                    height: geometryHeight
                )
            }
        }
    }
}

/// Einzelner Bandsperre-Bereich im Spektrogramm
struct BandstopRegionView: View {
    let filter: BandstopFilter
    let frequencyRange: ClosedRange<Float>
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        let startX = logPosition(for: filter.lowFrequency, width: width)
        let endX = logPosition(for: filter.highFrequency, width: width)
        let regionWidth = max(2, endX - startX)
        
        ZStack(alignment: .top) {
            // Halbtransparente rote Füllung
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: filter.color)?.opacity(0.3) ?? Color.red.opacity(0.3),
                            Color(hex: filter.color)?.opacity(0.15) ?? Color.red.opacity(0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: regionWidth)
                .position(x: (startX + endX) / 2, y: height / 2)
            
            // Vertikale Grenzlinien
            Rectangle()
                .fill(Color(hex: filter.color) ?? .red)
                .frame(width: 1)
                .opacity(0.6)
                .position(x: startX, y: height / 2)
            
            Rectangle()
                .fill(Color(hex: filter.color) ?? .red)
                .frame(width: 1)
                .opacity(0.6)
                .position(x: endX, y: height / 2)
            
            // Label oben (nur wenn genug Platz)
            if regionWidth > 30 {
                VStack(spacing: 2) {
                    Text(filter.name)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: filter.color) ?? .red)
                        .lineLimit(1)
                    
                    Text(filter.formattedRange)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.7))
                )
                .position(x: (startX + endX) / 2, y: 20)
            }
        }
    }
    
    private func logPosition(for frequency: Float, width: CGFloat) -> CGFloat {
        let minLog = log10(frequencyRange.lowerBound)
        let maxLog = log10(frequencyRange.upperBound)
        let freqLog = log10(max(frequencyRange.lowerBound, min(frequencyRange.upperBound, frequency)))
        let normalized = (freqLog - minLog) / (maxLog - minLog)
        return CGFloat(normalized) * width
    }
}

// MARK: - Hex Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

struct BandstopOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            BandstopOverlayView(
                filters: [
                    BandstopFilter(lowFrequency: 48, highFrequency: 52, name: "Netzbrummen", color: "#FF6B6B"),
                    BandstopFilter(lowFrequency: 500, highFrequency: 2000, name: "Sprache", color: "#4ECDC4")
                ],
                frequencyRange: 20...20000,
                geometryWidth: 400,
                geometryHeight: 300
            )
        }
    }
}
