import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNew = false
    @State private var importing = false
    @State private var browsing = false
    @State private var discovering = false
    @State private var dropTargeted = false

    private static let mrpack = UTType(filenameExtension: "mrpack") ?? .zip

    var body: some View {
        @Bindable var model = model
        Group {
            if let startupError = model.startupError {
                ContentUnavailableView(
                    String(format: L("startup.failed"), startupError),
                    systemImage: "exclamationmark.triangle"
                )
            } else {
                NavigationSplitView {
                    InstanceList(showingNew: $showingNew, importing: $importing, browsing: $browsing, discovering: $discovering)
                } detail: {
                    if let instance = model.selected {
                        InstanceDetailView(instance: instance)
                    } else {
                        EmptyStateView(showingNew: $showingNew, importing: $importing, browsing: $browsing, discovering: $discovering)
                    }
                }
                .overlay { if dropTargeted { dropOverlay } }
            }
        }
        .task {
            model.refresh()
            await model.listen()
        }
        .sheet(isPresented: $showingNew) { NewInstanceSheet() }
        .sheet(isPresented: $browsing) { ModpackBrowserSheet() }
        .sheet(isPresented: $discovering) { DiscoverSheet() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [Self.mrpack]) { result in
            if case .success(let url) = result { model.importPack(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "mrpack" }) else { return false }
            model.importPack(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .alert(L("error.title"), isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error?.localizedMessage ?? "")
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: Bark.Space.md) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 48, weight: .light))
                Text(L("import.drop")).font(.title3)
            }
            .foregroundStyle(.tint)
            .padding(Bark.Space.xxl)
            .background(RoundedRectangle(cornerRadius: Bark.Radius.xl, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8])))
        }
        .transition(.opacity)
        .barkAnimation(Bark.Motion.quick, value: dropTargeted)
    }
}

struct InstanceList: View {
    @Environment(AppModel.self) private var model
    @Binding var showingNew: Bool
    @Binding var importing: Bool
    @Binding var browsing: Bool
    @Binding var discovering: Bool
    @State private var pendingDelete: InstanceSummary?

    var body: some View {
        @Bindable var model = model
        List(model.instances, selection: $model.selectedID) { instance in
            InstanceRow(instance: instance, activity: model.activity[instance.id])
                .tag(instance.id)
                .contextMenu {
                    Button(L("instances.delete"), role: .destructive) { pendingDelete = instance }
                }
        }
        .navigationTitle(L("instances.title"))
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .toolbar {
            ToolbarItemGroup {
                Button { discovering = true } label: { Label(L("discover.button"), systemImage: "externaldrive.badge.magnifyingglass") }
                Button { browsing = true } label: { Label(L("packs.browse"), systemImage: "shippingbox") }
                Button { importing = true } label: { Label(L("import.title"), systemImage: "square.and.arrow.down") }
                Button { showingNew = true } label: { Label(L("instances.new"), systemImage: "plus") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if case .some(let state) = model.importing { ImportStatus(state: state) }
                Divider()
                AccountBar()
            }
        }
        .barkAnimation(Bark.Motion.standard, value: model.instances)
        .barkAnimation(Bark.Motion.standard, value: model.importing)
        .confirmationDialog(
            String(format: L("instances.delete.confirm"), pendingDelete?.name ?? ""),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("instances.delete.action"), role: .destructive) {
                if let pendingDelete { model.deleteInstance(pendingDelete.id) }
            }
            Button(L("common.cancel"), role: .cancel) {}
        }
    }
}

private struct ImportStatus: View {
    let state: Activity

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.xs) {
            Text(String(format: L("import.progress"), percent))
                .font(.caption)
                .foregroundStyle(.secondary)
            if case .installing(let done, let total) = state {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
            } else {
                ProgressView()
            }
        }
        .controlSize(.small)
        .padding(Bark.Space.md)
        .background(.bar)
    }

    private var percent: String {
        if case .installing(let done, let total) = state, total > 0 {
            return (Double(done) / Double(total)).formatted(.percent.precision(.fractionLength(0)))
        }
        return "…"
    }
}

struct InstanceRow: View {
    let instance: InstanceSummary
    let activity: Activity?

    var body: some View {
        HStack(spacing: Bark.Space.md) {
            Image(systemName: instance.isVanilla ? "cube.fill" : "puzzlepiece.extension.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                Text(instance.gameVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch activity {
            case .running:
                Circle().fill(.green).frame(width: 8, height: 8)
            case .preparing, .installing:
                ProgressView().controlSize(.small)
            case nil:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }
}
