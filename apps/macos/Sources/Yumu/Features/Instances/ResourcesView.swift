import SwiftUI
import UniformTypeIdentifiers

struct ResourcesView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    @State private var adding: ResourceKind?
    @State private var queries: [ResourceKind: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.lg) {
            HStack(alignment: .top, spacing: Bark.Space.lg) {
                ForEach(ResourceKind.allCases, id: \.self) { kind in section(kind) }
            }
            search
        }
        .task(id: instance.id) { model.loadResources(instance.id) }
        .fileImporter(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } }), allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result, let kind = adding { model.addResource(instance.id, kind: kind, url: url) }
            adding = nil
        }
    }

    private func section(_ kind: ResourceKind) -> some View {
        let files = model.resources[kind] ?? []
        return VStack(spacing: 0) {
            CardHeader(icon: kind == .shaderpacks ? "sparkles" : "photo", title: L(kind.titleKey)) {
                Button(L("resources.add")) { adding = kind }.buttonStyle(.quiet)
            }
            if files.isEmpty {
                Text(kind == .shaderpacks ? L("resources.shaders.empty") : L("resources.empty"))
                    .font(.system(size: 12)).foregroundStyle(Bark.Colors.textTertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                ForEach(files) { file in
                    ResourceRow(instance: instance, kind: kind, file: file)
                    if file.id != files.last?.id { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1).padding(.leading, Bark.Space.lg) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .insetCard()
        .barkAnimation(Bark.Motion.standard, value: files)
    }

    private var search: some View {
        VStack(spacing: 0) {
            CardHeader(icon: "plus.circle", title: L("resources.addTitle"), hint: L("mods.addHint"))
            ForEach(ResourceKind.allCases, id: \.self) { kind in
                let scope = SearchScope.resources(instance.id, kind)
                VStack(alignment: .leading, spacing: Bark.Space.sm) {
                    Text(L(kind.titleKey)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Bark.Colors.textTertiary)
                    SearchField(scope: scope, query: Binding(get: { queries[kind] ?? "" }, set: { queries[kind] = $0 }), placeholderKey: "mods.search.placeholder")
                }
                .padding(.horizontal, Bark.Space.lg).padding(.top, Bark.Space.md)
                SearchResults(scope: scope, emptyKey: "mods.noResults") { hit in
                    if model.installingProjects.contains(hit.projectId) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(L("mods.install")) { model.installResource(instance.id, kind: kind, projectId: hit.projectId) }.buttonStyle(.secondary)
                    }
                }
            }
            Spacer().frame(height: Bark.Space.md)
        }
        .insetCard()
    }
}

private struct ResourceRow: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let kind: ResourceKind
    let file: ResourceFile
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Bark.Space.md) {
            ModIcon(url: model.iconURL(for: file), size: 28, fallback: kind == .shaderpacks ? "sparkles" : "photo")
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(.system(size: 11)).foregroundStyle(Bark.Colors.textSecondary)
            }
            Spacer()
            Button { model.removeResource(instance.id, kind: kind, fileName: file.fileName) } label: { Image(systemName: "trash") }
                .buttonStyle(.quiet).opacity(hovering ? 1 : 0)
            Toggle("", isOn: Binding(get: { file.enabled }, set: { model.setResourceEnabled(instance.id, kind: kind, fileName: file.fileName, enabled: $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, Bark.Space.lg)
        .frame(height: 50)
        .onHover { hovering = $0 }
    }
}
