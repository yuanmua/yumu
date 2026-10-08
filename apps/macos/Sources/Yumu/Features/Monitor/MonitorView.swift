import AppKit
import SwiftUI

/// Every running game process with live CPU and memory, like a task manager for the launcher.
struct MonitorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bark.Space.lg) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("running.title")).font(.system(size: 30, weight: .bold))
                        Text(model.processes.isEmpty ? L("running.emptyHint") : String(format: L("toolbar.running"), model.processes.count))
                            .font(.system(size: 14)).foregroundStyle(Bark.Colors.textSecondary)
                    }
                    Spacer()
                    if model.processes.count > 1 {
                        Button(L("running.stopAll")) { for process in model.processes { model.stop(pid: process.pid) } }.buttonStyle(.secondary)
                    }
                }
                if model.processes.isEmpty {
                    VStack(spacing: Bark.Space.md) {
                        Image(systemName: "waveform.path.ecg").font(.system(size: 36, weight: .light)).foregroundStyle(Bark.Colors.textTertiary)
                        Text(L("running.empty")).font(.system(size: 13)).foregroundStyle(Bark.Colors.textSecondary)
                        Button(L("running.backToInstances")) { model.page = .instances }.buttonStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 56).insetCard()
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text(L("running.instance")).frame(maxWidth: .infinity, alignment: .leading)
                            Text(L("running.pid")).frame(width: 70, alignment: .trailing)
                            Text(L("running.elapsedColumn")).frame(width: 110, alignment: .trailing)
                            Text(L("running.cpu")).frame(width: 70, alignment: .trailing)
                            Text(L("running.memory")).frame(width: 90, alignment: .trailing)
                            Spacer().frame(width: 110)
                        }
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Bark.Colors.textTertiary)
                        .padding(.horizontal, Bark.Space.lg).frame(height: 36)
                        .hairlineBelow()
                        ForEach(model.processes) { process in
                            ProcessRow(process: process)
                            if process.id != model.processes.last?.id { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1).padding(.leading, Bark.Space.lg) }
                        }
                    }
                    .insetCard()
                }
                Text(L("running.note")).font(.system(size: 11)).foregroundStyle(Bark.Colors.textTertiary)
            }
            .padding(.horizontal, Bark.Space.xxl)
            .padding(.top, Bark.Space.xl)
            .padding(.bottom, Bark.Space.xxxl)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(L("running.title"))
        .task {
            while !Task.isCancelled {
                model.sampleStats()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .barkAnimation(Bark.Motion.standard, value: model.processes)
    }
}

private struct ProcessRow: View {
    @Environment(AppModel.self) private var model
    let process: RunningProcess

    var body: some View {
        let instance = model.instance(process.instanceId)
        let stats = model.stats[process.pid]
        HStack {
            HStack(spacing: Bark.Space.sm) {
                if let instance { InstanceIcon(instance: instance, size: 32) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance?.name ?? process.instanceId).font(.system(size: 13, weight: .medium))
                    HStack(spacing: 5) { StatusDot(); Text(L("detail.running")) }.font(.system(size: 11)).foregroundStyle(Bark.Colors.statusSuccess)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(process.pid)).monospacedDigit().foregroundStyle(Bark.Colors.textSecondary).frame(width: 70, alignment: .trailing)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(ElapsedText.format(context.date.timeIntervalSince(process.startedAt))).monospacedDigit()
            }
            .frame(width: 110, alignment: .trailing)
            Text(stats.map { String(format: "%.0f%%", $0.cpuPercent) } ?? "—").monospacedDigit().frame(width: 70, alignment: .trailing)
            Text(stats.map { ByteCountFormatter.string(fromByteCount: Int64($0.residentBytes), countStyle: .memory) } ?? "—").monospacedDigit().frame(width: 90, alignment: .trailing)
            HStack(spacing: 4) {
                Button(L("running.view")) { model.page = .instances; model.selectedID = process.instanceId }.buttonStyle(.quiet)
                Button { model.stop(pid: process.pid) } label: { Image(systemName: "stop.fill") }.buttonStyle(.quiet).help(L("running.stop"))
            }
            .frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 13))
        .padding(.horizontal, Bark.Space.lg)
        .frame(height: 56)
    }
}
