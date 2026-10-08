import SwiftUI

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Bark.Space.lg) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Bark.Colors.surfaceSunken)
                .frame(width: 96, height: 96)
                .overlay(Image(systemName: "cube.transparent").font(.system(size: 40, weight: .light)).foregroundStyle(Bark.Colors.textTertiary))
            VStack(spacing: 6) {
                Text(L("empty.title")).font(.system(size: 22, weight: .bold))
                Text(L("empty.subtitle")).foregroundStyle(Bark.Colors.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            HStack(spacing: Bark.Space.sm) {
                Button(L("instances.new")) { model.showingNew = true }.buttonStyle(.primaryLarge)
                Button(L("packs.browse")) { model.page = .packs }.buttonStyle(.secondaryLarge)
                Button(L("empty.import")) { model.choosingImport = true }.buttonStyle(.secondaryLarge)
            }
            .padding(.top, Bark.Space.xs)
            Text(L("import.drop")).font(.system(size: 11)).foregroundStyle(Bark.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
