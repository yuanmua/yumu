import SwiftUI

struct ModsView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    @State private var query = ""

    private var scope: SearchScope { .mods(instance.id) }

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
            SearchField(scope: scope, query: $query, placeholderKey: "mods.search.placeholder")
            SearchResults(scope: scope, emptyKey: "mods.noResults") { hit in
                if model.installingProjects.contains(hit.projectId) {
                    ProgressView().controlSize(.small)
                } else if model.isInstalled(projectId: hit.projectId) {
                    Text(L("mods.installedBadge")).font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(L("mods.install")) { model.installMod(instance.id, projectId: hit.projectId) }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
