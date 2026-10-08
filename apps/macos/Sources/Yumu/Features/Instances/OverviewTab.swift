import AppKit
import SwiftUI

/// What a player wants first: their worlds, then what is installed, then shortcuts.
struct OverviewTab: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let worlds: [WorldInfo]
    let showTab: (DetailTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.lg) {
            if let crashed = model.crashes[instance.id], model.processes(for: instance.id).isEmpty {
                CrashStatus(instance: instance, crash: crashed.crash, logPath: crashed.logPath, showMods: { showTab(.mods) }, showLogs: { showTab(.logs) })
            }
            worldsCard
            HStack(alignment: .top, spacing: Bark.Space.lg) {
                if !instance.isVanilla { modsCard }
                recentCard
            }
            quickActions
        }
    }

    private var worldsCard: some View {
        VStack(spacing: 0) {
            CardHeader(icon: "globe.americas", title: L("overview.worlds"), hint: worlds.isEmpty ? nil : L("overview.worlds.hint")) {
                if worlds.count > 3 {
                    Button(L("overview.worlds.all")) { showTab(.worlds) }.buttonStyle(.quiet)
                }
            }
            if worlds.isEmpty {
                Text(L("overview.worlds.empty"))
                    .font(.system(size: 13)).foregroundStyle(Bark.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else {
                ForEach(worlds.prefix(3)) { world in
                    WorldRow(instance: instance, world: world)
                    if world.id != worlds.prefix(3).last?.id { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1).padding(.leading, Bark.Space.lg) }
                }
            }
        }
        .insetCard()
    }

    private var modsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(icon: "square.stack.3d.up", title: L("overview.mods")) {
                Button(L("overview.mods.manage")) { showTab(.mods) }.buttonStyle(.quiet)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(model.mods.count)).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    Text(L("detail.count")).foregroundStyle(Bark.Colors.textSecondary)
                    let disabled = model.mods.filter { !$0.enabled }.count
                    if disabled > 0 { Tag(text: String(format: L("overview.mods.disabled"), disabled)).padding(.leading, 6) }
                }
                if model.mods.isEmpty {
                    Text(L("mods.empty")).font(.system(size: 12)).foregroundStyle(Bark.Colors.textTertiary)
                } else {
                    FlowTags(texts: model.mods.prefix(6).map(\.displayName), more: max(0, model.mods.count - 6))
                }
            }
            .padding(Bark.Space.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetCard()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(icon: "clock", title: L("overview.recent"))
            VStack(alignment: .leading, spacing: 0) {
                recentRow(icon: "play", text: instance.lastPlayedAt > 0 ? String(format: L("overview.recent.lastPlayed"), lastPlayed) : L("overview.recent.neverPlayed"))
                Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1)
                recentRow(icon: "hourglass", text: String(format: L("overview.recent.playtime"), playtime))
                if let crashed = model.crashes[instance.id] {
                    Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1)
                    recentRow(icon: "exclamationmark.triangle", text: L("crash.\(crashed.crash.kind)"))
                }
            }
            .padding(.horizontal, Bark.Space.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetCard()
    }

    private func recentRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Bark.Colors.textTertiary).frame(width: 16)
            Text(text).font(.system(size: 13))
        }
        .frame(height: 40)
    }

    private var quickActions: some View {
        HStack(spacing: Bark.Space.md) {
            QuickAction(icon: "folder", title: L("quick.folder"), hint: L("quick.folder.hint")) { NSWorkspace.shared.open(LocalFiles.gameDirectory(instance.id)) }
            QuickAction(icon: "doc.text", title: L("quick.logs"), hint: L("quick.logs.hint")) { showTab(.logs) }
            QuickAction(icon: "slider.horizontal.3", title: L("quick.settings"), hint: L("quick.settings.hint")) { showTab(.settings) }
            QuickAction(icon: "shippingbox", title: L("quick.export"), hint: L("empty.comingSoon"), disabled: true) {}
        }
    }

    private var lastPlayed: String {
        Date(timeIntervalSince1970: TimeInterval(instance.lastPlayedAt)).formatted(.relative(presentation: .named))
    }

    private var playtime: String {
        Duration.seconds(Int64(instance.playtimeSeconds)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

struct WorldRow: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let world: WorldInfo
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Bark.Space.md) {
            PixelArt(seed: world.name, biome: .plains, columns: 10, rows: 10)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(world.name).font(.system(size: 13, weight: .medium))
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(world.sizeBytes), countStyle: .file)) · \(world.modifiedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11)).foregroundStyle(Bark.Colors.textSecondary)
            }
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([world.path]) } label: { Image(systemName: "folder") }
                .buttonStyle(.quiet).opacity(hovering ? 1 : 0).help(L("worlds.openFolder"))
            Button { model.play(instance.id) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.quiet).disabled(model.activity[instance.id] != nil).help(L("worlds.play"))
        }
        .padding(.horizontal, Bark.Space.lg)
        .frame(height: 64)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Four shortcut tiles under the overview.
private struct QuickAction: View {
    let icon: String
    let title: String
    let hint: String
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(disabled ? Bark.Colors.textTertiary : Color.accentColor)
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(hint).font(.system(size: 11)).foregroundStyle(Bark.Colors.textSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Bark.Space.md)
            .insetCard()
            .shadow(color: .black.opacity(hovering && !disabled ? 0.06 : 0), radius: 10, y: 4)
            .offset(y: hovering && !disabled ? -1 : 0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
        .onHover { hovering = $0 }
        .barkAnimation(Bark.Motion.quick, value: hovering)
    }
}

/// Wrapping row of small tags.
struct FlowTags: View {
    let texts: [String]
    var more = 0

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(texts.enumerated()), id: \.offset) { _, text in Tag(text: text) }
            if more > 0 { Tag(text: "+\(more)", tone: .accent) }
        }
    }
}

/// Lays children out left to right, wrapping to a new line when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
