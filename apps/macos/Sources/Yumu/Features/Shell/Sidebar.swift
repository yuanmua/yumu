import AppKit
import SwiftUI

/// Instance list: running first, favourites, the rest, then what other launchers have.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.sidebarCovers) private var covers = true
    @AppStorage(Prefs.sidebarGroup) private var grouping = "version"
    @AppStorage(Prefs.sidebarSort) private var sort = "recent"
    @AppStorage(Prefs.sidebarLoader) private var loaderFilter = "all"
    @State private var query = ""
    @State private var collapsed: Set<String> = []
    @State private var pendingDelete: InstanceSummary?
    @State private var renaming: InstanceSummary?

    private static let loaders = ["vanilla", "fabric", "quilt", "forge", "neoforge"]

    private var filtered: [InstanceSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return sorted(model.instances.filter { instance in
            (trimmed.isEmpty || instance.name.localizedCaseInsensitiveContains(trimmed))
                && (loaderFilter == "all" || instance.loaderKind == loaderFilter)
        })
    }

    private func sorted(_ list: [InstanceSummary]) -> [InstanceSummary] {
        list.sorted { a, b in
            if sort == "name" { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            if a.lastPlayedAt != b.lastPlayedAt { return a.lastPlayedAt > b.lastPlayedAt }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The rest of the list, cut into sections by game version or loader.
    private func groups(_ rest: [InstanceSummary], standalone: Bool) -> [(key: String, title: String, items: [InstanceSummary])] {
        switch grouping {
        case "version":
            let keys = Array(Set(rest.map(\.gameVersion))).sorted(by: Self.newerVersion)
            return keys.map { version in ("group:version:\(version)", version, rest.filter { $0.gameVersion == version }) }
        case "loader":
            return Self.loaders.compactMap { kind in
                let items = rest.filter { $0.loaderKind == kind }
                return items.isEmpty ? nil : ("group:loader:\(kind)", kind == "vanilla" ? L("detail.vanilla") : L("loader.\(kind)"), items)
            }
        default:
            return rest.isEmpty ? [] : [("group:all", standalone ? L("sidebar.all") : L("sidebar.others"), rest)]
        }
    }

    private static func newerVersion(_ a: String, _ b: String) -> Bool {
        let left = a.split(separator: ".").map { Int($0) ?? 0 }, right = b.split(separator: ".").map { Int($0) ?? 0 }
        for (x, y) in zip(left, right) where x != y { return x > y }
        return left.count > right.count
    }

    var body: some View {
        @Bindable var model = model
        let running = filtered.filter { model.isRunning($0.id) }
        let favorites = filtered.filter { model.favorites.contains($0.id) && !model.isRunning($0.id) }
        let rest = filtered.filter { !model.favorites.contains($0.id) && !model.isRunning($0.id) }
        let sections = groups(rest, standalone: running.isEmpty && favorites.isEmpty)
        List(selection: Binding(get: { model.page == .instances ? model.selectedID : nil }, set: { id in
            if let id { model.selectedID = id; model.page = .instances }
        })) {
            if !running.isEmpty {
                Section {
                    ForEach(running) { instance in row(instance) }
                } header: {
                    HStack(spacing: 6) { StatusDot(); Text(L("sidebar.running")); Spacer(); Text(String(running.count)).foregroundStyle(Bark.Colors.textTertiary) }
                }
            }
            if !favorites.isEmpty {
                Section(L("sidebar.favorites")) { ForEach(favorites) { instance in row(instance) } }
            }
            ForEach(sections, id: \.key) { group in
                Section(isExpanded: Binding(get: { !collapsed.contains(group.key) }, set: { open in if open { collapsed.remove(group.key) } else { collapsed.insert(group.key) } })) {
                    ForEach(group.items) { instance in row(instance) }
                } header: {
                    HStack { Text(group.title); Spacer(); Text(String(group.items.count)).foregroundStyle(Bark.Colors.textTertiary) }
                }
            }
            if filtered.isEmpty, !model.instances.isEmpty {
                Text(L("sidebar.noMatch")).foregroundStyle(Bark.Colors.textTertiary).font(.system(size: 12))
            }
            if !model.foundVersions.isEmpty || !model.foundSaves.isEmpty {
                Section(L("sidebar.found")) {
                    ForEach(model.foundVersions) { found in FoundVersionRow(found: found).selectionDisabled() }
                    ForEach(model.foundSaves) { save in FoundSaveRow(save: save).selectionDisabled() }
                }
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Bark.Colors.backgroundSidebar)
        .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Bark.Colors.textTertiary).font(.system(size: 12))
                    TextField(L("sidebar.search"), text: $query).textFieldStyle(.plain).font(.system(size: 13))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Bark.Colors.surfaceSunken, in: RoundedRectangle(cornerRadius: Bark.Radius.sm, style: .continuous))
                Menu {
                    Picker(L("sidebar.group"), selection: $grouping) {
                        Text(L("sidebar.group.version")).tag("version")
                        Text(L("sidebar.group.loader")).tag("loader")
                        Text(L("sidebar.group.none")).tag("none")
                    }
                    Picker(L("sidebar.sort"), selection: $sort) {
                        Text(L("sidebar.sort.recent")).tag("recent")
                        Text(L("sidebar.sort.name")).tag("name")
                    }
                    Picker(L("sidebar.filter"), selection: $loaderFilter) {
                        Text(L("sidebar.filter.all")).tag("all")
                        ForEach(Self.loaders, id: \.self) { kind in Text(kind == "vanilla" ? L("detail.vanilla") : L("loader.\(kind)")).tag(kind) }
                    }
                } label: {
                    Image(systemName: loaderFilter == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(loaderFilter == "all" ? Bark.Colors.textSecondary : Color.accentColor)
                        .frame(width: 28, height: 30)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("sidebar.filter"))
            }
            .padding(.horizontal, Bark.Space.md)
            .padding(.bottom, Bark.Space.xs)
            .background(Bark.Colors.backgroundSidebar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Bark.Space.sm) {
                if let state = model.importing { ImportStatus(state: state) }
                HStack(spacing: 6) {
                    Button { model.showingNew = true } label: { Label(L("sidebar.new"), systemImage: "plus") }
                    Button { model.page = .packs } label: { Label(L("sidebar.packs"), systemImage: "shippingbox") }
                    Spacer()
                    Button { openSettings() } label: { Image(systemName: "gearshape") }.help(L("prefs.title"))
                }
                .buttonStyle(.secondary)
                AccountBar()
            }
            .padding(Bark.Space.md)
            .background(Bark.Colors.backgroundSidebar)
            .overlay(alignment: .top) { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1) }
        }
        .task { model.rescan() }
        .barkAnimation(Bark.Motion.standard, value: model.instances)
        .barkAnimation(Bark.Motion.standard, value: model.processes)
        .barkAnimation(Bark.Motion.standard, value: model.importing)
        .confirmationDialog(
            String(format: L("instances.delete.confirm"), pendingDelete?.name ?? ""),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("instances.delete.action"), role: .destructive) { if let pendingDelete { model.deleteInstance(pendingDelete.id) } }
            Button(L("common.cancel"), role: .cancel) {}
        }
        .sheet(item: $renaming) { instance in RenameSheet(instance: instance) }
    }

    private func row(_ instance: InstanceSummary) -> some View {
        InstanceRow(instance: instance, covers: covers, grouping: grouping)
            .tag(instance.id)
            .contextMenu { InstanceMenu(instance: instance, rename: { renaming = instance }, delete: { pendingDelete = instance }) }
    }
}

/// Every action on an instance, shared by the sidebar context menu and the "···" button.
struct InstanceMenu: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let rename: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(L("detail.play")) { model.play(instance.id) }.disabled(model.activity[instance.id] != nil)
        if model.isRunning(instance.id) {
            Button(L("detail.stop")) { model.stopAll(instance.id) }
        }
        Divider()
        Button(model.favorites.contains(instance.id) ? L("detail.unfavorite") : L("detail.favorite")) { model.toggleFavorite(instance.id) }
        Button(L("detail.rename")) { rename() }
        Button(L("detail.openFolder")) { NSWorkspace.shared.open(LocalFiles.gameDirectory(instance.id)) }
        Divider()
        Button(L("instances.delete"), role: .destructive) { delete() }
    }
}

struct InstanceRow: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let covers: Bool
    var grouping = "none"
    @State private var hovering = false

    var body: some View {
        let processes = model.processes(for: instance.id)
        HStack(spacing: Bark.Space.sm) {
            if covers {
                InstanceIcon(instance: instance, size: 32)
            } else {
                Image(systemName: instance.isVanilla ? "cube.fill" : "puzzlepiece.extension.fill").foregroundStyle(.tint).frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(instance.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                subtitle(processes).font(.system(size: 11)).lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing(processes)
        }
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func subtitle(_ processes: [RunningProcess]) -> some View {
        if let first = processes.first {
            ElapsedText(since: first.startedAt, prefix: processes.count > 1 ? "×\(processes.count) · " : "")
                .foregroundStyle(Bark.Colors.statusSuccess)
        } else if model.activity[instance.id] != nil {
            Text(L("detail.preparing")).foregroundStyle(Bark.Colors.textSecondary)
        } else {
            Text(subtitleText).foregroundStyle(Bark.Colors.textSecondary)
        }
    }

    /// Whatever the group header already says is left out of the row.
    private var subtitleText: String {
        let loader = instance.isVanilla ? L("detail.vanilla") : L("loader.\(instance.loaderKind)") + (instance.loaderVersion.isEmpty ? "" : " \(instance.loaderVersion)")
        switch grouping {
        case "version": return loader
        case "loader": return instance.gameVersion
        default: return "\(loader) · \(instance.gameVersion)"
        }
    }

    @ViewBuilder
    private func trailing(_ processes: [RunningProcess]) -> some View {
        if !processes.isEmpty {
            if hovering {
                Button { model.stopAll(instance.id) } label: { Image(systemName: "stop.fill").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(Bark.Colors.textSecondary).help(L("detail.stop"))
            } else {
                StatusDot()
            }
        } else if model.activity[instance.id] != nil {
            ProgressView().controlSize(.small)
        } else if model.favorites.contains(instance.id) {
            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Bark.Colors.statusWarning)
        }
    }
}

private struct ImportStatus: View {
    let state: Activity

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.xs) {
            Text(String(format: L("import.progress"), percent)).font(.system(size: 11)).foregroundStyle(Bark.Colors.textSecondary)
            if case .installing(let done, let total) = state {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
            } else {
                ProgressView()
            }
        }
        .controlSize(.small)
        .padding(Bark.Space.md)
        .insetCard()
    }

    private var percent: String {
        if case .installing(let done, let total) = state, total > 0 {
            return (Double(done) / Double(total)).formatted(.percent.precision(.fractionLength(0)))
        }
        return "…"
    }
}

/// A version another launcher has; one click makes it a Yumu instance.
struct FoundVersionRow: View {
    @Environment(AppModel.self) private var model
    let found: FoundVersion

    var body: some View {
        HStack(spacing: Bark.Space.sm) {
            Image(systemName: found.loaderKind == "vanilla" ? "cube" : "puzzlepiece.extension").frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(found.id).font(.system(size: 13))
                Text(subtitle).font(.system(size: 11))
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
        HStack(spacing: Bark.Space.sm) {
            Image(systemName: "globe.americas").frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(save.name).font(.system(size: 13))
                Text(L("sidebar.found.save")).font(.system(size: 11))
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

struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: InstanceSummary
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.lg) {
            Text(L("detail.rename")).font(Bark.Text.title)
            TextField("", text: $name).textFieldStyle(.roundedBorder).controlSize(.large)
            HStack {
                Spacer()
                Button(L("common.cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.secondary)
                Button(L("detail.rename")) {
                    model.rename(instance.id, to: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primary)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Bark.Space.xl)
        .frame(width: 380)
        .onAppear { name = instance.name }
    }
}
