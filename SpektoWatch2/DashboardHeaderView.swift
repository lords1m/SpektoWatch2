import SwiftUI

struct DashboardHeaderView: View {
    @Binding var isEditMode: Bool
    var onAddWidget: () -> Void
    
    var body: some View {
        HStack {
            Text("Dashboard")
                .font(.title2)
                .bold()
            
            Spacer()
            
            if isEditMode {
                Button(action: onAddWidget) {
                    Label("Add", systemImage: "plus")
                }
                .padding(.trailing, 8)
            }
            
            Button(action: {
                withAnimation {
                    isEditMode.toggle()
                }
            }) {
                Text(isEditMode ? "Fertig" : "Bearbeiten")
                    .fontWeight(isEditMode ? .bold : .regular)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}