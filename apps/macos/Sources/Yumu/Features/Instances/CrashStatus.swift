import AppKit
import SwiftUI

/// What went wrong, in one sentence, with the one button most likely to fix it.
struct CrashStatus: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let crash: Crash
    let logPath: String?
    let showMods: () -> Void
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.sm) {
            Label(L("crash.title"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.headline)
            Text(message).font(.callout)
            HStack(spacing: Bark.Space.sm) {
                fixButton
                if !crash.detail.isEmpty {
                    Button(L("crash.details")) { showingDetails.toggle() }
                }
            }
            .controlSize(.small)
            if showingDetails {
                Text(crash.detail.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .frame(maxWidth: 480, alignment: .leading)
            }
        }
        .barkAnimation(Bark.Motion.quick, value: showingDetails)
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
            let gigabytes = min(((model.settings?.maxMb ?? 2048) / 1024) + 2, 16)
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
                if let logPath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logPath)]) }
            }
        }
    }
}
