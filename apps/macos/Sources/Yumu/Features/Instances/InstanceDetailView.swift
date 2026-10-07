import SwiftUI

struct InstanceDetailView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    // Stop-gap until account.* lands: offline name is a pure interface preference for now.
    @AppStorage("offlinePlayerName") private var playerName = "Player"

    private var activity: Activity? { model.activity[instance.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.xl) {
            header
            stats
            Spacer()
            TextField(L("detail.playerName"), text: $playerName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            HStack(alignment: .bottom) {
                status
                Spacer()
                Button {
                    model.play(instance.id, playerName: playerName)
                } label: {
                    Label(L("detail.play"), systemImage: "play.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .disabled(activity != nil || playerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Bark.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .barkAnimation(Bark.Motion.standard, value: activity)
        .navigationTitle(instance.name)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Bark.Space.lg) {
            RoundedRectangle(cornerRadius: Bark.Radius.lg, style: .continuous)
                .fill(.tint.opacity(0.15))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.tint)
                }
            VStack(alignment: .leading, spacing: Bark.Space.xs) {
                Text(instance.name)
                    .font(.largeTitle.weight(.semibold))
                Text("\(loaderName) · \(instance.gameVersion)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stats: some View {
        Grid(alignment: .leading, horizontalSpacing: Bark.Space.xl, verticalSpacing: Bark.Space.sm) {
            GridRow {
                Text(L("detail.lastPlayed")).foregroundStyle(.secondary)
                Text(lastPlayed)
            }
            GridRow {
                Text(L("detail.playtime")).foregroundStyle(.secondary)
                Text(Duration.seconds(Int64(instance.playtimeSeconds))
                    .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var status: some View {
        switch activity {
        case .preparing:
            HStack(spacing: Bark.Space.sm) {
                ProgressView().controlSize(.small)
                Text(L("detail.preparing")).foregroundStyle(.secondary)
            }
        case .installing(let done, let total):
            VStack(alignment: .leading, spacing: Bark.Space.xs) {
                Text(String(format: L("detail.installing"), bytes(done), bytes(total)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(width: 260)
            }
        case .running:
            Label(L("detail.running"), systemImage: "circle.fill")
                .foregroundStyle(.green)
        case nil:
            EmptyView()
        }
    }

    private var loaderName: String {
        instance.loaderKind == "vanilla" ? L("detail.vanilla") : instance.loaderKind.capitalized
    }

    private var lastPlayed: String {
        guard instance.lastPlayedAt > 0 else { return L("detail.never") }
        return Date(timeIntervalSince1970: TimeInterval(instance.lastPlayedAt))
            .formatted(.relative(presentation: .named))
    }

    private func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
