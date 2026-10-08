import SwiftUI

/// Modpack browser as a page: search, big rows, one install button each.
struct PacksView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bark.Space.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("packs.title")).font(.system(size: 30, weight: .bold))
                    Text(L("packs.hint")).font(.system(size: 14)).foregroundStyle(Bark.Colors.textSecondary)
                }
                SearchField(scope: .packs, query: $query, placeholderKey: "packs.search.placeholder", large: true)
                    .frame(maxWidth: 560)
                VStack(spacing: 0) {
                    SearchResults(scope: .packs, emptyKey: "mods.noResults", large: true) { hit in
                        if model.installingPack == hit.projectId {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(L("packs.install")) { model.installPack(projectId: hit.projectId, iconUrl: hit.iconUrl) }
                                .buttonStyle(.primary).disabled(model.importing != nil)
                        }
                    }
                }
                .insetCard()
            }
            .padding(.horizontal, Bark.Space.xxl)
            .padding(.top, Bark.Space.xl)
            .padding(.bottom, Bark.Space.xxxl)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(L("packs.title"))
        .task { if model.searchResults[.packs] == nil { model.search(.packs, query: "") } }
    }
}

/// Text field that runs a Modrinth search for `scope` on return.
struct SearchField: View {
    @Environment(AppModel.self) private var model
    let scope: SearchScope
    @Binding var query: String
    let placeholderKey: String
    var large = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Bark.Colors.textTertiary).font(.system(size: large ? 13 : 12))
            TextField(L(placeholderKey), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: large ? 14 : 13))
                .onSubmit { model.search(scope, query: query) }
            if model.searching.contains(scope) { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .frame(height: large ? 38 : 30)
        .background(Bark.Colors.surfaceSunken, in: RoundedRectangle(cornerRadius: large ? Bark.Radius.md : Bark.Radius.sm, style: .continuous))
    }
}

/// Result rows for a scope; `trailing` renders the install control for a hit.
struct SearchResults<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    let scope: SearchScope
    let emptyKey: String
    var large = false
    @ViewBuilder let trailing: (SearchHit) -> Trailing

    var body: some View {
        if let results = model.searchResults[scope] {
            if results.isEmpty {
                Text(L(emptyKey)).font(.system(size: 13)).foregroundStyle(Bark.Colors.textTertiary).frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                ForEach(results) { hit in
                    SearchRow(hit: hit, large: large) { trailing(hit) }
                    if hit.id != results.last?.id { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1).padding(.leading, Bark.Space.lg) }
                }
                if model.canLoadMore(scope) {
                    Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1)
                    HStack {
                        Text(String(format: L("search.count"), results.count, model.searchTotals[scope] ?? 0)).font(.system(size: 12)).foregroundStyle(Bark.Colors.textTertiary)
                        Spacer()
                        if model.searching.contains(scope) {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(L("search.loadMore")) { model.loadMore(scope) }.buttonStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Bark.Space.lg).frame(height: 48)
                }
            }
        } else if model.searching.contains(scope) {
            VStack(spacing: 6) { ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 8).fill(Bark.Colors.surfaceSunken).frame(height: 44) } }
                .padding(Bark.Space.lg)
        }
    }
}

struct SearchRow<Trailing: View>: View {
    let hit: SearchHit
    var large = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Bark.Space.md) {
            Group {
                if let url = hit.iconUrl.flatMap(URL.init) {
                    CachedImage(url: url) { RoundedRectangle(cornerRadius: Bark.Radius.sm).fill(Bark.Colors.surfaceSunken) }
                } else {
                    RoundedRectangle(cornerRadius: Bark.Radius.sm).fill(Bark.Colors.surfaceSunken)
                }
            }
            .frame(width: large ? 56 : 36, height: large ? 56 : 36)
            .clipShape(RoundedRectangle(cornerRadius: large ? 12 : 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title).font(.system(size: large ? 15 : 13, weight: .semibold)).lineLimit(1)
                Text(hit.description).font(.system(size: 12)).foregroundStyle(Bark.Colors.textSecondary).lineLimit(large ? 2 : 1)
                Text("\(hit.author) · \(String(format: L("mods.downloads"), hit.downloads.formatted(.number.notation(.compactName))))")
                    .font(.system(size: 11)).foregroundStyle(Bark.Colors.textTertiary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, Bark.Space.lg)
        .padding(.vertical, large ? 14 : 8)
    }
}
