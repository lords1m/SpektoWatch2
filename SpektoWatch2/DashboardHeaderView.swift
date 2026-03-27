import SwiftUI

struct DashboardHeaderView: View {
    @Binding var isEditMode: Bool
    var currentLayoutName: String
    var onAddWidget: () -> Void
    var onAddLayout: () -> Void
    var onSaveLayout: () -> Void
    var onShowLayouts: () -> Void
    var onShowSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dashboard")
                        .font(.title2)
                        .bold()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(currentLayoutName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if !isEditMode {
                    Button(action: onShowSettings) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .padding(.trailing, 10)

                    Menu {
                        Button(action: onAddLayout) {
                            Label("Neue Seite", systemImage: "rectangle.stack.badge.plus")
                        }
                        Button(action: onSaveLayout) {
                            Label("Aktuelle Seite speichern", systemImage: "square.on.square")
                        }
                        Button(action: onShowLayouts) {
                            Label("Layouts abrufen", systemImage: "list.bullet.rectangle.portrait")
                        }
                    } label: {
                        Image(systemName: "rectangle.stack")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .padding(.trailing, 8)
                }
                
                if isEditMode {
                    Button(action: onAddWidget) {
                        ViewThatFits {
                            Label("Add", systemImage: "plus")
                                .foregroundColor(.blue)
                            Image(systemName: "plus")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.trailing, 6)
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
                        .lineLimit(1)
                        .fontWeight(isEditMode ? .bold : .regular)
                        .foregroundColor(.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .backgroundExtensionEffect(cornerRadius: 22)
            
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .background(Color.clear)
    }
}
