import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.welcomeDone) private var welcomeDone = false
    @State private var dropTargeted = false

    private static let mrpack = UTType(filenameExtension: "mrpack") ?? .zip

    var body: some View {
        @Bindable var model = model
        Group {
            if let startupError = model.startupError {
                ContentUnavailableView(String(format: L("startup.failed"), startupError), systemImage: "exclamationmark.triangle")
            } else {
                NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
                    Sidebar()
                } detail: {
                    detail
                        .toolbar { ToolbarItemGroup(placement: .primaryAction) { TopActions() } }
                }
                .navigationSplitViewStyle(.balanced)
                .overlay { if dropTargeted { dropOverlay } }
            }
        }
        .task { model.refresh() }
        .sheet(isPresented: $model.showingNew) { NewInstanceSheet() }
        .fileImporter(isPresented: $model.choosingImport, allowedContentTypes: [Self.mrpack]) { result in
            if case .success(let url) = result { model.importPack(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "mrpack" }) else { return false }
            model.importPack(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .alert(L("error.title"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(model.error?.localizedMessage ?? "")
        }
    }

    /// The animated part is the inner group only, so the toolbar above it never moves with page changes.
    private var detail: some View {
        ZStack {
            Bark.Colors.backgroundCanvas.ignoresSafeArea()
            pages
                .barkAnimation(Bark.Motion.standard, value: model.selectedID)
                .barkAnimation(Bark.Motion.standard, value: model.page)
        }
    }

    @ViewBuilder
    private var pages: some View {
        switch model.page {
        case .packs:
            PacksView()
        case .monitor:
            MonitorView()
        case .instances:
            if let instance = model.selected {
                InstanceDetailView(instance: instance)
                    .id(instance.id)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            } else if !welcomeDone {
                WelcomeView()
            } else {
                EmptyStateView()
            }
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: Bark.Space.md) {
                Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 48, weight: .light))
                Text(L("import.drop")).font(.system(size: 20, weight: .medium))
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 56)
            .padding(.vertical, 40)
            .background(RoundedRectangle(cornerRadius: Bark.Radius.xl, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8])))
        }
        .transition(.opacity)
        .barkAnimation(Bark.Motion.quick, value: dropTargeted)
    }
}

/// Toolbar: the running pill, import, new.
private struct TopActions: View {
    @Environment(AppModel.self) private var model
    @State private var showingRunning = false

    var body: some View {
        if !model.processes.isEmpty {
            Button {
                showingRunning.toggle()
            } label: {
                HStack(spacing: 6) {
                    StatusDot()
                    Text(String(format: L("toolbar.running"), model.processes.count)).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Bark.Colors.surfaceElevated, in: Capsule())
                .overlay(Capsule().strokeBorder(Bark.Colors.borderSubtle))
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .popover(isPresented: $showingRunning, arrowEdge: .bottom) { RunningPopover(dismiss: { showingRunning = false }) }
        }
        Button { model.choosingImport = true } label: { Image(systemName: "square.and.arrow.down") }.help(L("import.title"))
        Button { model.showingNew = true } label: { Image(systemName: "plus") }.help(L("instances.new"))
    }
}

/// The list behind the running pill: every process, with view and stop.
struct RunningPopover: View {
    @Environment(AppModel.self) private var model
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("running.title"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Bark.Colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            ForEach(model.processes) { process in
                if let instance = model.instance(process.instanceId) {
                    HStack(spacing: Bark.Space.sm) {
                        InstanceIcon(instance: instance, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(instance.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            ElapsedText(since: process.startedAt, prefix: "PID \(process.pid) · ")
                                .font(.system(size: 11)).foregroundStyle(Bark.Colors.statusSuccess).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(L("running.view")) {
                            model.page = .instances
                            model.selectedID = process.instanceId
                            dismiss()
                        }
                        .buttonStyle(.quiet)
                        Button { model.stop(pid: process.pid) } label: { Image(systemName: "stop.fill") }
                            .buttonStyle(.quiet)
                            .help(L("running.stop"))
                    }
                    .padding(8)
                    .frame(width: 360)
                }
            }
            Divider().padding(.vertical, 4)
            Button {
                model.page = .monitor
                dismiss()
            } label: {
                Label(L("running.monitor"), systemImage: "waveform.path.ecg").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.quiet)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(4)
        .frame(width: 368)
        .transaction { $0.animation = nil }
    }
}

/// "运行中 · 12 分 03 秒", ticking once a second.
struct ElapsedText: View {
    let since: Date
    var prefix = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(prefix + String(format: L("running.elapsed"), Self.format(context.date.timeIntervalSince(since))))
                .monospacedDigit()
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        if hours > 0 { return String(format: L("time.hoursMinutes"), hours, minutes) }
        return String(format: L("time.minutesSeconds"), minutes, seconds % 60)
    }
}
