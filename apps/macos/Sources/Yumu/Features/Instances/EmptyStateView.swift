import SwiftUI

struct EmptyStateView: View {
    @Binding var showingNew: Bool
    @Binding var importing: Bool
    @Binding var browsing: Bool

    var body: some View {
        VStack(spacing: Bark.Space.lg) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(L("empty.title"))
                .font(.title2.weight(.semibold))
            Text(L("empty.subtitle"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: Bark.Space.md) {
                Button(L("instances.new")) { showingNew = true }
                    .buttonStyle(.borderedProminent)
                Button(L("packs.browse")) { browsing = true }
                Button(L("empty.import")) { importing = true }
            }
            .controlSize(.large)
            .padding(.top, Bark.Space.sm)
            Text(L("import.drop"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
