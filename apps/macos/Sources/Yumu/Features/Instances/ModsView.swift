import SwiftUI

struct ModsView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    @State private var query = ""

    var body: some View {
        if instance.isVanilla {
            ContentUnavailableView(L("mods.vanillaHint"), systemImage: "puzzlepiece.extension")
        } else {
            HStack(alignment: .top, spacing: Bark.Space.xl) {
                installed
                search
            }
            .task(id: instance.id) {
                model.loadMods(instance.id)
                model.clearSearch()
                query = ""
            }
        }
    }

    private var installed: some View {
        VStack(alignment: .leading, spacing: Bark.Space.sm) {
            Text(L("mods.installed")).font(.headline)
            if model.mods.isEmpty {
                Text(L("mods.empty")).foregroundStyle(.secondary).frame(maxHeight: .infinity, alignment: .top)
            } else {
                List(model.mods) { mod in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { mod.enabled },
                            set: { model.setModEnabled(instance.id, fileName: mod.fileName, enabled: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mod.displayName)
                                Text(mod.record?.versionNumber ?? mod.version)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        Spacer()
                        Button(role: .destructive) {
                            model.removeMod(instance.id, fileName: mod.fileName)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(L("mods.remove"))
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: Bark.Radius.md, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .barkAnimation(Bark.Motion.standard, value: model.mods)
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: Bark.Space.sm) {
            HStack {
                TextField(L("mods.search.placeholder"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.searchMods(instance.id, query: query) }
                if model.searching { ProgressView().controlSize(.small) }
            }
            if let results = model.searchResults {
                if results.isEmpty {
                    Text(L("mods.noResults")).foregroundStyle(.secondary)
                } else {
                    List(results) { hit in
                        SearchRow(instance: instance, hit: hit)
                    }
                    .listStyle(.inset)
                    .clipShape(RoundedRectangle(cornerRadius: Bark.Radius.md, style: .continuous))
                }
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .barkAnimation(Bark.Motion.standard, value: model.searchResults)
    }
}

private struct SearchRow: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let hit: SearchHit

    var body: some View {
        HStack(spacing: Bark.Space.md) {
            AsyncImage(url: hit.iconUrl.flatMap(URL.init)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: Bark.Radius.sm).fill(.quaternary)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: Bark.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).lineLimit(1)
                Text(hit.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(String(format: L("mods.downloads"), hit.downloads.formatted(.number.notation(.compactName))))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if model.installingProjects.contains(hit.projectId) {
                ProgressView().controlSize(.small)
            } else if model.isInstalled(projectId: hit.projectId) {
                Text(L("mods.installedBadge")).font(.caption).foregroundStyle(.secondary)
            } else {
                Button(L("mods.install")) { model.installMod(instance.id, projectId: hit.projectId) }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
