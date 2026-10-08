import AppKit
import SwiftUI

/// What went wrong, in one sentence, with the one button most likely to fix it.
struct CrashStatus: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let crash: Crash
    let logPath: String?
    let showMods: () -> Void
    let showLogs: () -> Void
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.sm) {
            HStack(alignment: .top, spacing: Bark.Space.md) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 18)).foregroundStyle(Bark.Colors.statusDanger)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("crash.title")).font(.system(size: 14, weight: .semibold))
                    Text(message).font(.system(size: 12)).foregroundStyle(Bark.Colors.textSecondary)
                }
                Spacer()
                fixButton.buttonStyle(.primary)
                if !crash.detail.isEmpty {
                    Button(L("crash.details")) { withAnimation(Bark.Motion.quick) { showingDetails.toggle() } }.buttonStyle(.secondary)
                }
            }
            if showingDetails {
                Text(crash.detail.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Bark.Colors.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .padding(.leading, 30)
            }
        }
        .padding(Bark.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Bark.Colors.statusDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: Bark.Radius.lg, style: .continuous))
    }

    private var message: String {
        var text = L("crash.\(crash.kind)")
        if !crash.mods.isEmpty {
            text += " " + String(format: L("crash.involved"), crash.mods.joined(separator: "、"))
        }
        return text
    }

    @ViewBuilder
    private var fixButton: some View {
        switch crash.kind {
        case "OUT_OF_MEMORY":
            let gigabytes = min(((model.settings?.maxMb ?? 2048) / 1024) + 2, max(4, AppModel.physicalMemoryMb / 2048))
            Button(String(format: L("crash.fix.memory"), String(gigabytes))) {
                if var settings = model.settings, settings.id == instance.id {
                    settings.maxMb = gigabytes * 1024
                    model.updateSettings(settings)
                }
            }
        case "JAVA_VERSION", "NATIVES":
            Button(L("crash.fix.java")) {
                if var settings = model.settings, settings.id == instance.id {
                    settings.javaProvider = "mojang"
                    settings.javaPath = ""
                    model.updateSettings(settings)
                }
            }
        case "MOD_DEPENDENCY", "MOD_CONFLICT":
            Button(L("crash.fix.mods"), action: showMods)
        default:
            Button(L("crash.fix.log")) {
                if let logPath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logPath)]) } else { showLogs() }
            }
        }
    }
}
