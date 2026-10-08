import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNew = false
    @State private var importing = false
    @State private var browsing = false
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
                    InstanceList(showingNew: $showingNew, importing: $importing, browsing: $browsing)
                } detail: {
                    if let instance = model.selected {
                        InstanceDetailView(instance: instance)
                    } else {
                        EmptyStateView(showingNew: $showingNew, importing: $importing, browsing: $browsing)
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
    @State private var pendingDelete: InstanceSummary?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedID) {
            ForEach(model.instances) { instance in
                InstanceRow(instance: instance, activity: model.activity[instance.id])
                    .tag(instance.id)
                    .contextMenu {
                        Button(L("instances.delete"), role: .destructive) { pendingDelete = instance }
                    }
            }
            if !model.foundVersions.isEmpty || !model.foundSaves.isEmpty {
                Section(L("sidebar.found")) {
                    ForEach(model.foundVersions) { found in FoundVersionRow(found: found) }
                    ForEach(model.foundSaves) { save in FoundSaveRow(save: save) }
                }
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("instances.title"))
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .toolbar(removing: .sidebarToggle)
        .task { model.rescan() }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if case .some(let state) = model.importing { ImportStatus(state: state) }
                Divider()
                HStack(spacing: 0) {
                    AccountBar()
                    AddMenu(showingNew: $showingNew, importing: $importing, browsing: $browsing)
                }
                .background(.bar)
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

/// The "+" at the bottom of the sidebar: every way to get a new instance, in one place.
struct AddMenu: View {
    @Binding var showingNew: Bool
    @Binding var importing: Bool
    @Binding var browsing: Bool

    var body: some View {
        Menu {
            Button(L("instances.new")) { showingNew = true }
            Button(L("packs.browse")) { browsing = true }
            Button(L("import.title")) { importing = true }
        } label: {
            Image(systemName: "plus")
                .font(.title3)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.trailing, Bark.Space.md)
        .help(L("sidebar.add"))
    }
}

/// A version another launcher has; one click makes it a Yumu instance.
struct FoundVersionRow: View {
    @Environment(AppModel.self) private var model
    let found: FoundVersion

    var body: some View {
        HStack(spacing: Bark.Space.md) {
            Image(systemName: found.loaderKind == "vanilla" ? "cube" : "puzzlepiece.extension")
            VStack(alignment: .leading, spacing: 2) {
                Text(found.id)
                Text(subtitle).font(.caption)
            }
            Spacer()
            Button(L("sidebar.found.add")) {
                model.createInstance(name: found.id, version: found.gameVersion, loader: found.loaderKind, loaderVersion: found.loaderVersion)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let loader = found.loaderKind == "vanilla" ? L("detail.vanilla") : L("loader.\(found.loaderKind)")
        let version = found.loaderVersion.isEmpty ? "" : " \(found.loaderVersion)"
        return "\(loader)\(version) · \(found.gameVersion)"
    }
}

/// A world from another launcher; imports into whichever instance is selected.
struct FoundSaveRow: View {
    @Environment(AppModel.self) private var model
    let save: Save

    var body: some View {
        HStack(spacing: Bark.Space.md) {
            Image(systemName: "globe.americas")
            VStack(alignment: .leading, spacing: 2) {
                Text(save.name)
                Text(L("sidebar.found.save")).font(.caption)
            }
            Spacer()
            Button(L("sidebar.found.add")) {
                if let id = model.selectedID { model.importSave(save.path, into: id) }
            }
            .controlSize(.small)
            .disabled(model.selectedID == nil || model.importingSave)
            .help(model.selectedID == nil ? L("sidebar.found.selectFirst") : L("sidebar.found.importHere"))
        }
        .padding(.vertical, 2)
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
