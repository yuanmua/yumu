import AppKit
import SwiftUI

private enum DetailTab: String, CaseIterable {
    case overview, mods, resources

    var titleKey: String { "detail.tab.\(rawValue)" }
}

struct InstanceDetailView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    @State private var tab = DetailTab.overview

    private var activity: Activity? { model.activity[instance.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.xl) {
            header
            Picker("", selection: $tab) {
                ForEach(DetailTab.allCases, id: \.self) { Text(L($0.titleKey)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            switch tab {
            case .overview: OverviewTab(instance: instance)
            case .mods: ModsView(instance: instance)
            case .resources: ResourcesView(instance: instance)
            }
            footer
        }
        .padding(Bark.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .barkAnimation(Bark.Motion.standard, value: activity)
        .navigationTitle(instance.name)
        .onChange(of: instance.id) { tab = .overview }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Bark.Space.lg) {
            RoundedRectangle(cornerRadius: Bark.Radius.lg, style: .continuous)
                .fill(.tint.opacity(0.15))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: instance.isVanilla ? "cube.fill" : "puzzlepiece.extension.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.tint)
                }
            VStack(alignment: .leading, spacing: Bark.Space.xs) {
                Text(instance.name)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSWorkspace.shared.open(gameDirectory)
            } label: {
                Label(L("detail.openFolder"), systemImage: "folder")
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            status
            Spacer()
            Button {
                model.play(instance.id)
            } label: {
                Label(L("detail.play"), systemImage: "play.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(activity != nil || model.activeAccount == nil)
            .help(model.activeAccount == nil ? L("error.ACCOUNT_REQUIRED") : "")
        }
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

    private var subtitle: String {
        let loader = instance.isVanilla ? L("detail.vanilla") : L("loader.\(instance.loaderKind)")
        let version = instance.loaderVersion.isEmpty ? "" : " \(instance.loaderVersion)"
        return "\(loader)\(version) · \(instance.gameVersion)"
    }

    private var gameDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Yumu/instances/\(instance.id)/.minecraft")
    }

    private func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

private struct OverviewTab: View {
    let instance: InstanceSummary

    var body: some View {
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
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var lastPlayed: String {
        guard instance.lastPlayedAt > 0 else { return L("detail.never") }
        return Date(timeIntervalSince1970: TimeInterval(instance.lastPlayedAt))
            .formatted(.relative(presentation: .named))
    }
}
