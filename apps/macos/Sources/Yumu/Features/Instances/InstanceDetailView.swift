import AppKit
import SwiftUI

enum DetailTab: String, CaseIterable {
    case overview, mods, resources, worlds, logs, settings

    var titleKey: String { "detail.tab.\(rawValue)" }
}

/// One instance: header with the numbers that matter, one primary action, tabs below.
struct InstanceDetailView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    @State private var tab = DetailTab.overview
    @State private var renaming = false
    @State private var confirmingDelete = false

    private var processes: [RunningProcess] { model.processes(for: instance.id) }
    private var activity: Activity? { model.activity[instance.id] }
    private var worlds: [WorldInfo] { model.worlds[instance.id] ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bark.Space.xl) {
                header
                actions
                UnderlineTabs(items: tabs, selection: $tab)
                content
                    .id(tab)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .padding(.horizontal, Bark.Space.xxl)
            .padding(.top, Bark.Space.xl)
            .padding(.bottom, Bark.Space.xxxl)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .barkAnimation(Bark.Motion.standard, value: tab)
        .barkAnimation(Bark.Motion.standard, value: processes)
        .barkAnimation(Bark.Motion.standard, value: activity)
        .navigationTitle(instance.name)
        .task(id: instance.id) {
            model.loadWorlds(instance.id)
            if !instance.isVanilla { model.loadMods(instance.id) }
        }
        .onChange(of: processes.count) { model.loadWorlds(instance.id) }
        .sheet(isPresented: $renaming) { RenameSheet(instance: instance) }
        .confirmationDialog(String(format: L("instances.delete.confirm"), instance.name), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L("instances.delete.action"), role: .destructive) { model.deleteInstance(instance.id) }
            Button(L("common.cancel"), role: .cancel) {}
        }
    }

    private var tabs: [UnderlineTabs<DetailTab>.Item] {
        DetailTab.allCases.map { tab in
            let count: Int? = switch tab {
            case .mods: instance.isVanilla ? nil : model.mods.count
            case .worlds: worlds.count
            default: nil
            }
            return .init(id: tab, title: L(tab.titleKey), count: count)
        }
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Bark.Space.xl) {
                identity
                Spacer(minLength: Bark.Space.lg)
                stats.layoutPriority(1)
            }
            VStack(alignment: .leading, spacing: Bark.Space.lg) {
                identity
                stats
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: Bark.Space.xl) {
            InstanceIcon(instance: instance, size: 96)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(instance.name).font(.system(size: 32, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                    Button { model.toggleFavorite(instance.id) } label: {
                        Image(systemName: model.favorites.contains(instance.id) ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundStyle(model.favorites.contains(instance.id) ? Bark.Colors.statusWarning : Bark.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(model.favorites.contains(instance.id) ? L("detail.unfavorite") : L("detail.favorite"))
                }
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Bark.Colors.textSecondary).lineLimit(2)
                statusLine.padding(.top, 2)
            }
        }
    }

    private var stats: some View {
        StatsGrid(instance: instance, worlds: worlds.count, mods: instance.isVanilla ? nil : model.mods.count)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch activity {
        case .preparing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("detail.preparing")) }
                .font(.system(size: 12)).foregroundStyle(Bark.Colors.textSecondary)
        case .installing(let done, let total):
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: L("detail.installing"), bytes(done), bytes(total)))
                    .font(.system(size: 12)).foregroundStyle(Bark.Colors.textSecondary).monospacedDigit()
                ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 240)
            }
        case nil:
            if let first = processes.first {
                HStack(spacing: 6) {
                    StatusDot()
                    if processes.count > 1 {
                        Text(String(format: L("detail.runningCount"), processes.count))
                    } else {
                        ElapsedText(since: first.startedAt)
                    }
                }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Bark.Colors.statusSuccess)
            } else if model.crashes[instance.id] != nil {
                Tag(text: L("detail.crashed"), tone: .danger, icon: "exclamationmark.triangle.fill")
            } else {
                HStack(spacing: 6) { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)); Text(L("detail.ready")) }
                    .font(.system(size: 12)).foregroundStyle(Bark.Colors.textTertiary)
            }
        }
    }

    private var subtitle: String {
        let loader = instance.isVanilla ? L("detail.vanilla") : L("loader.\(instance.loaderKind)")
        let version = instance.loaderVersion.isEmpty ? "" : " \(instance.loaderVersion)"
        return "\(loader)\(version) · \(instance.gameVersion) · \(String(format: L("detail.subtitle.lastPlayed"), lastPlayed))"
    }

    private var lastPlayed: String {
        guard instance.lastPlayedAt > 0 else { return L("detail.never") }
        return Date(timeIntervalSince1970: TimeInterval(instance.lastPlayedAt)).formatted(.relative(presentation: .named))
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: Bark.Space.sm) {
            Button { model.play(instance.id) } label: {
                Label(processes.isEmpty ? L("detail.play") : L("detail.launchAgain"), systemImage: "play.fill")
            }
            .buttonStyle(.primaryLarge)
            .disabled(activity != nil || model.activeAccount == nil)
            .help(model.activeAccount == nil ? L("error.ACCOUNT_REQUIRED") : "")
            .keyboardShortcut(.return, modifiers: .command)
            if processes.count == 1 {
                Button { model.stopAll(instance.id) } label: { Label(L("detail.stop"), systemImage: "stop.fill") }
                    .buttonStyle(.secondaryLarge)
            } else if processes.count > 1 {
                Menu {
                    ForEach(processes) { process in
                        Button(String(format: L("detail.stopOne"), process.pid)) { model.stop(pid: process.pid) }
                    }
                    Divider()
                    Button(L("running.stopAll")) { model.stopAll(instance.id) }
                } label: {
                    Label(L("detail.stop"), systemImage: "stop.fill")
                }
                .buttonStyle(.secondaryLarge)
            }
            Button { NSWorkspace.shared.open(LocalFiles.gameDirectory(instance.id)) } label: { Label(L("detail.openFolder"), systemImage: "folder") }
                .buttonStyle(.secondaryLarge)
            Menu {
                InstanceMenu(instance: instance, rename: { renaming = true }, delete: { confirmingDelete = true })
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .buttonStyle(.secondaryLarge)
            .frame(width: 44)
        }
    }

    // MARK: Tabs

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview: OverviewTab(instance: instance, worlds: worlds, showTab: { tab = $0 })
        case .mods: ModsView(instance: instance)
        case .resources: ResourcesView(instance: instance)
        case .worlds: WorldsView(instance: instance, worlds: worlds)
        case .logs: LogsView(instance: instance)
        case .settings: InstanceSettingsView(instance: instance, delete: { confirmingDelete = true })
        }
    }

    private func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

/// The four numbers at the top right: playtime, last played, worlds, mods.
private struct StatsGrid: View {
    let instance: InstanceSummary
    let worlds: Int
    let mods: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                cell(icon: "clock", label: L("detail.stats.playtime"), value: playtime.0, unit: playtime.1)
                divider
                cell(icon: "calendar", label: L("detail.stats.lastPlayed"), value: lastPlayed, unit: "")
            }
            Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1)
            HStack(spacing: 0) {
                cell(icon: "globe.americas", label: L("detail.stats.worlds"), value: String(worlds), unit: L("detail.count"))
                divider
                if let mods {
                    cell(icon: "square.stack.3d.up", label: L("detail.stats.mods"), value: String(mods), unit: L("detail.count"))
                } else {
                    cell(icon: "cube", label: L("detail.stats.edition"), value: L("detail.vanilla"), unit: "")
                }
            }
        }
        .frame(width: 320)
        .fixedSize()
        .insetCard()
    }

    private var divider: some View { Rectangle().fill(Bark.Colors.borderSubtle).frame(width: 1) }

    private func cell(icon: String, label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) { Image(systemName: icon).font(.system(size: 10)); Text(label) }
                .font(.system(size: 11)).foregroundStyle(Bark.Colors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if !unit.isEmpty { Text(unit).font(.system(size: 12)).foregroundStyle(Bark.Colors.textTertiary) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 159, alignment: .leading)
        .clipped()
    }

    private var playtime: (String, String) {
        let minutes = Int(instance.playtimeSeconds / 60)
        if minutes >= 60 { return (String(minutes / 60), L("time.hours")) }
        return (String(minutes), L("time.minutes"))
    }

    private var lastPlayed: String {
        guard instance.lastPlayedAt > 0 else { return L("detail.never") }
        return Date(timeIntervalSince1970: TimeInterval(instance.lastPlayedAt)).formatted(.relative(presentation: .named))
    }
}
