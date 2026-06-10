import SwiftUI

/// Sheet for preset pages and custom layouts (Model C).
struct LayoutsManagementView: View {
    @ObservedObject var dashboardManager: DashboardManager
    @Environment(\.dismiss) private var dismiss

    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var renameTargetID: UUID?
    @State private var showResetPresetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if dashboardManager.isCustomMode {
                    Section {
                        Button {
                            dashboardManager.returnToPresets()
                            dismiss()
                        } label: {
                            Label("Zu Presets zurück", systemImage: "square.grid.2x2")
                        }
                    }
                }

                Section(header: Text("Presets")) {
                    ForEach(PresetCatalogue.all) { preset in
                        Button {
                            dashboardManager.selectPreset(id: preset.id)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: preset.symbol)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text(preset.label)
                                Spacer()
                                if !dashboardManager.isCustomMode,
                                   dashboardManager.activePresetID == preset.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                        .accessibilityIdentifier("layoutsOpenPreset_\(preset.id)")
                    }

                    if !dashboardManager.isCustomMode {
                        Button(role: .destructive) {
                            showResetPresetConfirm = true
                        } label: {
                            Label("Aktuelles Preset zurücksetzen", systemImage: "arrow.counterclockwise")
                        }
                        .accessibilityIdentifier("layoutsResetPreset")
                    }
                }

                Section(header: Text("Meine Layouts")) {
                    if dashboardManager.customLayouts.isEmpty {
                        Text("Noch keine eigenen Layouts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dashboardManager.customLayouts) { layout in
                            Button {
                                dashboardManager.openCustomLayout(id: layout.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(layout.name)
                                    Spacer()
                                    if dashboardManager.isCustomMode,
                                       case .custom(let id) = dashboardManager.navigation,
                                       id == layout.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.accent)
                                    }
                                }
                            }
                            .accessibilityIdentifier("layoutsOpenCustom_\(layout.id.uuidString)")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    renameTargetID = layout.id
                                    renameText = layout.name
                                    showRenameAlert = true
                                } label: {
                                    Label("Umbenennen", systemImage: "pencil")
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    dashboardManager.deleteCustomLayout(id: layout.id)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        dashboardManager.addCustomLayout(empty: true)
                        dismiss()
                    } label: {
                        Label("Neues Layout", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .accessibilityIdentifier("layoutsNewCustom")

                    Button {
                        dashboardManager.duplicateCurrentAsCustomLayout()
                        dismiss()
                    } label: {
                        Label("Aktuelles als Layout speichern", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("layoutsDuplicateCurrent")
                }

                if UITestLaunchFlags.widgetSizeScreenshotPresetAvailable {
                    Section(header: Text("Entwicklung")) {
                        Button("Screenshot-Preset: Widgetgrößen") {
                            dashboardManager.installWidgetSizeScreenshotPreset()
                            dismiss()
                        }
                        .accessibilityIdentifier("layoutsScreenshotPreset")
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .polishedFormChrome()
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("layoutsDismiss")
                }
            }
            .alert("Preset zurücksetzen?", isPresented: $showResetPresetConfirm) {
                Button("Zurücksetzen", role: .destructive) {
                    dashboardManager.resetActivePresetToDefault()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Widgets auf dem aktuellen Preset werden durch die Standard-Zusammenstellung ersetzt.")
            }
            .alert("Layout umbenennen", isPresented: $showRenameAlert) {
                TextField("Name", text: $renameText)
                Button("Speichern") {
                    if let id = renameTargetID {
                        dashboardManager.renameCustomLayout(id: id, name: renameText)
                    }
                    renameTargetID = nil
                }
                Button("Abbrechen", role: .cancel) {
                    renameTargetID = nil
                }
            }
        }
        .polishedSheetChrome()
    }
}
