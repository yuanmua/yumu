import SwiftUI

struct ModpackBrowserSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.md) {
            HStack {
                Text(L("packs.browse")).font(.title2.weight(.semibold))
                Spacer()
                Button(L("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(L("packs.hint")).font(.caption).foregroundStyle(.secondary)
            SearchField(scope: .packs, query: $query, placeholderKey: "packs.search.placeholder")
            SearchResults(scope: .packs, emptyKey: "mods.noResults") { hit in
                if model.importing != nil {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L("packs.install")) {
                        model.installPack(projectId: hit.projectId)
                        dismiss()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(Bark.Space.xl)
        .frame(width: 560, height: 520)
        .task { if model.searchResults[.packs] == nil { model.search(.packs, query: "") } }
    }
}

/// Text field that runs a Modrinth search for `scope` on return.
struct SearchField: View {
    @Environment(AppModel.self) private var model
    let scope: SearchScope
    @Binding var query: String
    let placeholderKey: String

    var body: some View {
        HStack {
            TextField(L(placeholderKey), text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.search(scope, query: query) }
            if model.searching.contains(scope) { ProgressView().controlSize(.small) }
        }
    }
}

/// Result list for a scope; `trailing` renders the install control for a hit.
struct SearchResults<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    let scope: SearchScope
    let emptyKey: String
    @ViewBuilder let trailing: (SearchHit) -> Trailing

    var body: some View {
        if let results = model.searchResults[scope] {
            if results.isEmpty {
                Text(L(emptyKey)).foregroundStyle(.secondary).frame(maxHeight: .infinity, alignment: .top)
            } else {
                List(results) { hit in
                    SearchRow(hit: hit) { trailing(hit) }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: Bark.Radius.md, style: .continuous))
                .barkAnimation(Bark.Motion.standard, value: results)
            }
        } else {
            Spacer()
        }
    }
}

struct SearchRow<Trailing: View>: View {
    let hit: SearchHit
    @ViewBuilder let trailing: () -> Trailing

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
            trailing()
        }
        .padding(.vertical, 2)
    }
}
