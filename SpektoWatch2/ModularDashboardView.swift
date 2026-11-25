import SwiftUI
import UniformTypeIdentifiers

/// The app's main screen, laid out and behaving like the iOS Home Screen:
/// swipeable pages (one per preset) of icons and widgets on the tiled
/// wallpaper, page dots with the instrument status, and a glass dock with
/// the transport controls. Long-press enters jiggle mode.
struct ModularDashboardView: View {
    @State private var viewModel: DashboardViewModel
    @Bindable private var dashboardManager: DashboardManager
    @Environment(AppServices.self) private var services
    @State private var showLayoutsSheet = false
    @State private var launchedFeature: FeatureLauncherDestination?
    @State private var footerBarHeight: CGFloat = 0
    @AppStorage("dashboard.activePreset") private var activePresetID: String = "overview"
    @Namespace private var zoomNamespace

    /// `dashboardManager` is owned by the caller (ContentView's @State).
    init(audioEngine: AudioEngine, connectivityManager: WatchConnectivityManager, dashboardManager: DashboardManager) {
        _viewModel = State(initialValue: DashboardViewModel(dashboardManager: dashboardManager, audioEngine: audioEngine, connectivityManager: connectivityManager))
        self.dashboardManager = dashboardManager
    }

    var body: some View {
        DesignTokensReader { _ in
            mainBody
        }
    }

    private var isEditMode: Bool { dashboardManager.isEditMode }

    private func setEditMode(_ value: Bool) {
        guard dashboardManager.isEditMode != value else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            dashboardManager.isEditMode = value
        }
    }

    private var mainBody: some View {
        ZStack {
            HomeWallpaper()

            dashboardContent

            if let toast = viewModel.widgetUndoToast {
                VStack {
                    Spacer()
                    widgetUndoSnackbar(toast)
                        .padding(.bottom, 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isEditMode {
                HomeEditBar(
                    onAdd: viewModel.addWidget,
                    onPages: { showLayoutsSheet = true },
                    onDone: { setEditMode(false) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            homeBottom
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.widgetUndoToast?.id)
        .onChange(of: dashboardManager.activePresetIndex) { _, _ in
            syncActivePresetStorage()
        }
        .onChange(of: dashboardManager.navigation) { _, _ in
            syncActivePresetStorage()
        }
        .onPreferenceChange(FooterBarHeightPreferenceKey.self) { value in
            footerBarHeight = value
        }
        .onAppear { syncActivePresetStorage() }
        .sheet(isPresented: $viewModel.showWidgetPicker) {
            WidgetPickerView(dashboardManager: viewModel.dashboardManager)
                .polishedSheetChrome()
        }
        .sheet(isPresented: $showLayoutsSheet) {
            LayoutsManagementView(dashboardManager: dashboardManager)
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsRootView(
                selectedMicrophoneSource: $viewModel.selectedMicrophoneSource,
                watchGain: $viewModel.watchGain,
                audioEngine: viewModel.audioEngine
            )
            .environment(services)
            .polishedSheetChrome()
        }
        .fullScreenCover(item: $launchedFeature) { destination in
            FeatureFullScreenHostView(
                destination: destination,
                audioEngine: viewModel.audioEngine,
                fftConfig: services.fftConfiguration,
                selectedMicrophoneSource: $viewModel.selectedMicrophoneSource,
                watchGain: $viewModel.watchGain
            )
            .environment(services)
            // App-open feel: the feature zooms out of its icon.
            .navigationTransition(.zoom(sourceID: destination.widget.id, in: zoomNamespace))
        }
        .onChange(of: viewModel.selectedMicrophoneSource) { _, newSource in
            viewModel.handleMicrophoneSourceChange(newSource)
        }
        .alert("Apple Watch nicht erreichbar", isPresented: $viewModel.showWatchNotReachableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Stelle sicher, dass die Watch-App geöffnet ist und Bluetooth aktiv ist.")
        }
        .onChange(of: viewModel.watchGain) { _, newValue in
            viewModel.updateWatchGain(newValue)
        }
        .task {
            dashboardManager.startLoading()
            if UITestLaunchFlags.installWidgetSizeScreenshotPreset {
                await PersistenceMigrator.migrationsCompleted()
                dashboardManager.installWidgetSizeScreenshotPreset()
            }
        }
    }

    // MARK: Pages

    @ViewBuilder
    private var dashboardContent: some View {
        if dashboardManager.isCustomMode {
            page(widgets: dashboardManager.widgets, isActive: true)
        } else {
            let selection = Binding<Int>(
                get: { dashboardManager.activePresetIndex },
                set: { dashboardManager.setActivePresetIndex($0) }
            )
            TabView(selection: selection) {
                ForEach(Array(PresetCatalogue.all.indices), id: \.self) { index in
                    Group {
                        // Paged TabView mounts all pages eagerly. Only the
                        // active page and its swipe neighbors get a live
                        // page — otherwise every off-screen preset's widgets
                        // stay subscribed and re-render on each 15 Hz audio
                        // publish. Far pages mount on demand.
                        if abs(index - dashboardManager.activePresetIndex) <= 1 {
                            page(
                                widgets: dashboardManager.widgets(forPresetIndex: index),
                                isActive: index == dashboardManager.activePresetIndex
                            )
                        } else {
                            Color.clear
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func page(widgets: [WidgetConfiguration], isActive: Bool) -> some View {
        HomeScreenPage(
            widgets: widgets,
            isEditMode: isEditMode,
            isActive: isActive,
            audioEngine: viewModel.audioEngine,
            fftConfig: services.fftConfiguration,
            zoomNamespace: zoomNamespace,
            reorderItems: $dashboardManager.widgets,
            draggedWidget: $viewModel.draggedWidget,
            onLaunch: { launchedFeature = FeatureLauncherDestination(widget: $0) },
            onDelete: { viewModel.deleteWidget($0) },
            onResize: { id, size in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    dashboardManager.resizeWidget(id: id, to: size)
                }
            },
            onUpdateSettings: { id, settings in
                dashboardManager.updateWidgetSettings(id: id, settings: settings)
            },
            onUpdateStyle: { id, style in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    dashboardManager.setDisplayStyle(style, for: id)
                }
            },
            onSetEditMode: setEditMode,
            onSaveOrder: dashboardManager.saveConfiguration
        )
    }

    // MARK: Dots + dock

    private var homeBottom: some View {
        VStack(spacing: FerriteSpace.s) {
            HomePageIndicator(
                count: dashboardManager.isCustomMode ? 1 : PresetCatalogue.all.count,
                current: dashboardManager.isCustomMode ? 0 : dashboardManager.activePresetIndex,
                onSelect: { index in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        dashboardManager.setActivePresetIndex(index)
                    }
                }
            ) {
                HomeStatusLabel(audioEngine: viewModel.audioEngine)
            }

            ControlBarView(
                audioEngine: viewModel.audioEngine,
                style: .dock,
                onShowSettings: { viewModel.showSettings = true }
            )
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: FooterBarHeightPreferenceKey.self, value: geo.size.height)
            }
        )
    }

    private func syncActivePresetStorage() {
        guard !dashboardManager.isCustomMode else { return }
        let id = dashboardManager.activePresetID
        if activePresetID != id {
            activePresetID = id
        }
    }

    private func widgetUndoSnackbar(_ toast: WidgetUndoToast) -> some View {
        HStack(spacing: 12) {
            Text("Widget entfernt")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Rückgängig") {
                viewModel.undoWidgetDelete()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .accessibilityIdentifier("widgetUndoSnackbar")
    }
}

private struct FooterBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WidgetDropDelegate: DropDelegate {
    let item: WidgetConfiguration
    @Binding var items: [WidgetConfiguration]
    @Binding var draggedItem: WidgetConfiguration?
    @Binding var dropTargetWidgetID: UUID?
    let isEnabled: Bool
    var onSave: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        // draggedItem != nil rejects foreign text drags (iPad multitasking,
        // hardware-keyboard drags) that would otherwise trigger a spurious save.
        guard isEnabled, draggedItem != nil else { return false }
        dropTargetWidgetID = nil
        draggedItem = nil
        onSave()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
        dropTargetWidgetID = item.id
        guard let draggedItem = draggedItem else { return }
        if draggedItem.id != item.id {
            guard let from = items.firstIndex(where: { $0.id == draggedItem.id }),
                  let to = items.firstIndex(where: { $0.id == item.id }) else { return }
            if items[to].id != draggedItem.id {
                withAnimation {
                    items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return DropProposal(operation: .cancel) }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetWidgetID == item.id {
            dropTargetWidgetID = nil
        }
    }
}
