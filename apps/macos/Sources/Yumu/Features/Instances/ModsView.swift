import SwiftUI

struct ModsView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    @State private var query = ""
    @State private var filter = ""
    @State private var page = 0
    private static let pageSize = 40

    private var scope: SearchScope { .mods(instance.id) }

    var body: some View {
        if instance.isVanilla {
            VStack(spacing: Bark.Space.md) {
                Image(systemName: "puzzlepiece.extension").font(.system(size: 36, weight: .light)).foregroundStyle(Bark.Colors.textTertiary)
                Text(L("mods.vanillaHint")).font(.system(size: 13)).foregroundStyle(Bark.Colors.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                Button(L("overview.mods.newFabric")) { model.showingNew = true }.buttonStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 48).insetCard()
        } else {
            VStack(alignment: .leading, spacing: Bark.Space.lg) {
                search
                installed
            }
            .task(id: instance.id) {
                model.loadMods(instance.id)
                query = ""
                filter = ""
                page = 0
            }
            .onChange(of: filter) { page = 0 }
        }
    }

    private var search: some View {
        VStack(spacing: 0) {
            CardHeader(icon: "plus.circle", title: L("mods.addTitle"), hint: L("mods.addHint"))
            SearchField(scope: scope, query: $query, placeholderKey: "mods.search.placeholder")
                .padding(Bark.Space.lg)
            SearchResults(scope: scope, emptyKey: "mods.noResults") { hit in
                if model.installingProjects.contains(hit.projectId) {
                    ProgressView().controlSize(.small)
                } else if model.isInstalled(projectId: hit.projectId) {
                    Tag(text: L("mods.installedBadge"), tone: .accent)
                } else {
                    Button(L("mods.install")) { model.installMod(instance.id, projectId: hit.projectId, iconUrl: hit.iconUrl) }.buttonStyle(.secondary)
                }
            }
        }
        .insetCard()
    }

    private var filteredMods: [LocalMod] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty ? model.mods : model.mods.filter { $0.displayName.localizedCaseInsensitiveContains(needle) }
    }

    private var pageCount: Int { max(1, (filteredMods.count + Self.pageSize - 1) / Self.pageSize) }

    private var pageMods: ArraySlice<LocalMod> {
        let current = min(page, pageCount - 1)
        let start = current * Self.pageSize
        return filteredMods[start..<min(start + Self.pageSize, filteredMods.count)]
    }

    private var installed: some View {
        VStack(spacing: 0) {
            CardHeader(icon: "square.stack.3d.up", title: L("mods.installed"), hint: model.mods.isEmpty ? nil : String(format: L("overview.mods.count"), model.mods.count)) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11)).foregroundStyle(Bark.Colors.textTertiary)
                    TextField(L("mods.filter"), text: $filter).textFieldStyle(.plain).font(.system(size: 12))
                }
                .padding(.horizontal, 8).frame(width: 180, height: 26)
                .background(Bark.Colors.surfaceSunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            if model.mods.isEmpty {
                Text(L("mods.empty")).font(.system(size: 13)).foregroundStyle(Bark.Colors.textTertiary).frame(maxWidth: .infinity).padding(.vertical, 28)
            } else if filteredMods.isEmpty {
                Text(L("mods.noResults")).font(.system(size: 13)).foregroundStyle(Bark.Colors.textTertiary).frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                let shown = pageMods
                LazyVStack(spacing: 0) {
                    ForEach(shown) { mod in
                        ModRow(instance: instance, mod: mod)
                        if mod.id != shown.last?.id { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1).padding(.leading, Bark.Space.lg) }
                    }
                }
                if pageCount > 1 { pager }
            }
        }
        .insetCard()
        .barkAnimation(Bark.Motion.standard, value: model.mods)
    }

    private var pager: some View {
        let current = min(page, pageCount - 1)
        let first = current * Self.pageSize + 1
        let last = min(first + Self.pageSize - 1, filteredMods.count)
        return HStack(spacing: Bark.Space.sm) {
            Text(String(format: L("mods.page"), first, last, filteredMods.count)).font(.system(size: 12)).foregroundStyle(Bark.Colors.textSecondary).monospacedDigit()
            Spacer()
            Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.secondary).disabled(current == 0)
            ForEach(0..<pageCount, id: \.self) { index in
                Button(String(index + 1)) { page = index }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: index == current ? .semibold : .regular))
                    .foregroundStyle(index == current ? Color.accentColor : Bark.Colors.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(index == current ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Button { page = min(pageCount - 1, current + 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.secondary).disabled(current >= pageCount - 1)
        }
        .padding(.horizontal, Bark.Space.lg)
        .frame(height: 52)
        .overlay(alignment: .top) { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1) }
    }
}

private struct ModRow: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let mod: LocalMod
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Bark.Space.md) {
            ModIcon(url: model.iconURL(for: mod), size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("\(mod.record?.versionNumber ?? mod.version) · \(ByteCountFormatter.string(fromByteCount: Int64(mod.size), countStyle: .file))")
                    .font(.system(size: 11)).foregroundStyle(Bark.Colors.textSecondary).lineLimit(1)
            }
            Spacer()
            Button { model.removeMod(instance.id, fileName: mod.fileName) } label: { Image(systemName: "trash") }
                .buttonStyle(.quiet).opacity(hovering ? 1 : 0).help(L("mods.remove"))
            Toggle("", isOn: Binding(get: { mod.enabled }, set: { model.setModEnabled(instance.id, fileName: mod.fileName, enabled: $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, Bark.Space.lg)
        .frame(height: 50)
        .opacity(mod.enabled ? 1 : 0.6)
        .onHover { hovering = $0 }
    }
}

/// Modrinth artwork when known, otherwise the generic mod tile.
struct ModIcon: View {
    let url: URL?
    let size: CGFloat
    var fallback = "puzzlepiece.extension.fill"

    var body: some View {
        Group {
            if let url {
                CachedImage(url: url) { RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Bark.Colors.surfaceSunken) }
            } else {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color.accentColor.opacity(0.12))
                    .overlay(Image(systemName: fallback).font(.system(size: size * 0.43)).foregroundStyle(Color.accentColor))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}
