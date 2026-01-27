import SwiftUI

struct DashboardHeaderView: View {
    @Binding var isEditMode: Bool
    var onAddWidget: () -> Void
    var onShowSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Dashboard")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                if !isEditMode {
                    Button(action: onShowSettings) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .padding(.trailing, 16)
                }
                
                if isEditMode {
                    Button(action: onAddWidget) {
                        Label("Add", systemImage: "plus")
                            .foregroundColor(.blue)
                    }
                    .padding(.trailing, 8)
                }
                
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isEditMode.toggle()
                    }
                    print("[DashboardHeaderView] Edit mode: \(isEditMode)")
                }) {
                    Text(isEditMode ? "Fertig" : "Bearbeiten")
                        .fontWeight(isEditMode ? .bold : .regular)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            
            // Bottom Separator
            Divider()
                .background(Color.gray.opacity(0.3))
        }
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}
