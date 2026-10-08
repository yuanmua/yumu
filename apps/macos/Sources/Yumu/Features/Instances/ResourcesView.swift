import SwiftUI
import UniformTypeIdentifiers

struct ResourcesView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    @State private var adding: ResourceKind?
    @State private var queries: [ResourceKind: String] = [:]

    var body: some View {
        HStack(alignment: .top, spacing: Bark.Space.xl) {
            ForEach(ResourceKind.allCases, id: \.self) { kind in
                section(kind)
            }
        }
        .task(id: instance.id) { model.loadResources(instance.id) }
        .fileImporter(
            isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } }),
            allowedContentTypes: [.zip]
        ) { result in
            if case .success(let url) = result, let kind = adding {
                model.addResource(instance.id, kind: kind, url: url)
            }
            adding = nil
        }
    }

    private func section(_ kind: ResourceKind) -> some View {
        let files = model.resources[kind] ?? []
        let scope = SearchScope.resources(instance.id, kind)
        return VStack(alignment: .leading, spacing: Bark.Space.sm) {
            HStack {
                Text(L(kind.titleKey)).font(.headline)
                Spacer()
                Button(L("resources.add")) { adding = kind }.controlSize(.small)
            }
            if files.isEmpty {
                Text(L("resources.empty")).foregroundStyle(.secondary)
            } else {
                List(files) { file in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { file.enabled },
                            set: { model.setResourceEnabled(instance.id, kind: kind, fileName: file.fileName, enabled: $0) }
                        )) {
                            Text(file.fileName).lineLimit(1)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        Spacer()
                        Button(role: .destructive) {
                            model.removeResource(instance.id, kind: kind, fileName: file.fileName)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: Bark.Radius.md, style: .continuous))
                .frame(maxHeight: 220)
            }
            SearchField(
                scope: scope,
                query: Binding(get: { queries[kind] ?? "" }, set: { queries[kind] = $0 }),
                placeholderKey: "mods.search.placeholder"
            )
            SearchResults(scope: scope, emptyKey: "mods.noResults") { hit in
                if model.installingProjects.contains(hit.projectId) {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L("mods.install")) { model.installResource(instance.id, kind: kind, projectId: hit.projectId) }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .barkAnimation(Bark.Motion.standard, value: files)
    }
}
