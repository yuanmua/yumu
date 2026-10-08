import AppKit
import SwiftUI

/// The game's output, newest log first, refreshed while a process is running.
struct LogsView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    @State private var files: [URL] = []
    @State private var selected: URL?
    @State private var text = ""
    @State private var filter = ""

    private var running: Bool { model.isRunning(instance.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.md) {
            HStack(spacing: Bark.Space.sm) {
                Picker("", selection: $selected) {
                    ForEach(files, id: \.self) { file in Text(label(file)).tag(Optional(file)) }
                }
                .labelsHidden()
                .frame(width: 240)
                .disabled(files.isEmpty)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Bark.Colors.textTertiary).font(.system(size: 11))
                    TextField(L("logs.search"), text: $filter).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).frame(width: 220, height: 30)
                .background(Bark.Colors.surfaceSunken, in: RoundedRectangle(cornerRadius: Bark.Radius.sm, style: .continuous))
                Spacer()
                Button { copy() } label: { Label(L("logs.copy"), systemImage: "doc.on.doc") }.buttonStyle(.secondary).disabled(text.isEmpty)
                Button { NSWorkspace.shared.open(LocalFiles.logsDirectory(instance.id)) } label: { Label(L("logs.folder"), systemImage: "folder") }.buttonStyle(.secondary)
            }
            if let crashed = model.crashes[instance.id], !running {
                CrashStatus(instance: instance, crash: crashed.crash, logPath: crashed.logPath, showMods: {}, showLogs: {})
            }
            if files.isEmpty {
                Text(L("logs.empty"))
                    .font(.system(size: 13)).foregroundStyle(Bark.Colors.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 48).insetCard()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(color(for: line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(Bark.Space.lg)
                    }
                    .frame(height: 440)
                    .background(Color(hex: 0x141311), in: RoundedRectangle(cornerRadius: Bark.Radius.lg, style: .continuous))
                    .onChange(of: text) { if filter.isEmpty, let last = lines.indices.last { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }
        }
        .task(id: instance.id) { reload() }
        .onChange(of: selected) { text = selected.map { LocalFiles.tail($0) } ?? "" }
        .onChange(of: model.processes.count) { reload() }
        .task(id: running) {
            while running, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if let selected, selected == files.first { text = LocalFiles.tail(selected) }
            }
        }
    }

    private var lines: [String] {
        let all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let needle = filter.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(needle) }
    }

    private func reload() {
        files = LocalFiles.logFiles(instance.id)
        if selected == nil || !files.contains(selected!) { selected = files.first }
        text = selected.map { LocalFiles.tail($0) } ?? ""
    }

    private func label(_ file: URL) -> String {
        let stamp = file.deletingPathExtension().lastPathComponent
        if let seconds = TimeInterval(stamp) {
            return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000 : seconds).formatted(date: .abbreviated, time: .shortened)
        }
        return stamp
    }

    private func color(for line: String) -> Color {
        if line.contains("/ERROR]") || line.contains("Exception") { return Color(hex: 0xE26B61) }
        if line.contains("/WARN]") { return Color(hex: 0xE0A94A) }
        if line.hasPrefix("[") { return Color(hex: 0xD7D3CB) }
        return Color(hex: 0x9C9890)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
