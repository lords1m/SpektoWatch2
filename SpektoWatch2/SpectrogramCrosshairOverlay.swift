import SwiftUI

struct SpectrogramCrosshairOverlay: View {
    let inspector: (CGFloat, CGFloat) -> (time: TimeInterval, frequency: Float, magnitude: Float)?

    @State private var isActive = false
    @State private var position: CGPoint = .zero
    @State private var inspection: (time: TimeInterval, frequency: Float, magnitude: Float)?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isActive {
                    crosshairLines(in: geo.size)
                    
                    if let inspection {
                        inspectionLabel(for: inspection, in: geo.size)
                    }
                }
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.25) {
                isActive = true
                position = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
                inspection = inspector(position.x, position.y)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isActive else { return }
                        position = CGPoint(
                            x: max(0, min(geo.size.width, value.location.x)),
                            y: max(0, min(geo.size.height, value.location.y))
                        )
                        inspection = inspector(position.x, position.y)
                    }
                    .onEnded { _ in
                        isActive = false
                        inspection = nil
                    }
            )
        }
    }
    
    private func crosshairLines(in size: CGSize) -> some View {
        let x = max(0, min(size.width, position.x))
        let y = max(0, min(size.height, position.y))
        
        return Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(Color.white.opacity(0.85), lineWidth: 1)
    }
    
    private func inspectionLabel(
        for inspection: (time: TimeInterval, frequency: Float, magnitude: Float),
        in size: CGSize
    ) -> some View {
        let x = max(0, min(size.width, position.x))
        let y = max(0, min(size.height, position.y))
        
        let offsetX = x - size.width / 2 + 40
        let clampedX = max(-size.width / 2 + 48, min(size.width / 2 - 48, offsetX))
        
        let offsetY = y - size.height / 2 - 20
        let clampedY = max(-size.height / 2 + 24, min(size.height / 2 - 24, offsetY))
        
        return inspectionLabelContent(for: inspection)
            .offset(x: clampedX, y: clampedY)
    }
    
    private func inspectionLabelContent(
        for inspection: (time: TimeInterval, frequency: Float, magnitude: Float)
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "t %.2fs", inspection.time))
            Text(String(format: "f %.0fHz", inspection.frequency))
            Text(String(format: "%.1f dB", inspection.magnitude))
        }
        .font(.caption2.monospacedDigit())
        .padding(6)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
        .foregroundColor(.white)
    }
}

