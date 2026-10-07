import SwiftUI

struct EmptyStateView: View {
    @Binding var showingNew: Bool

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
                Button(L("empty.import")) {}
                    .disabled(true)
                    .help(L("empty.comingSoon"))
            }
            .controlSize(.large)
            .padding(.top, Bark.Space.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
