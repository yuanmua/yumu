import SwiftUI
import UniformTypeIdentifiers

/// Collapsed by default: the things a new player never needs, kept for the ones who do.
struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    @State private var expanded = false
    @State private var draft: InstanceSettings?
    @State private var choosingJava = false
    @State private var name = ""
    @State private var jvmArgs = ""

    var body: some View {
        DisclosureGroup(L("advanced.title"), isExpanded: $expanded) {
            if let draft {
                form(draft)
            }
        }
        .task(id: instance.id) {
            model.loadSettings(instance.id)
            sync(model.settings)
            if model.scan == nil { model.rescan() }
        }
        .onChange(of: model.settings) { _, settings in sync(settings) }
        .fileImporter(isPresented: $choosingJava, allowedContentTypes: [.unixExecutable, .item]) { result in
            if case .success(let url) = result, var updated = draft {
                updated.javaProvider = "custom"
                updated.javaPath = url.path
                model.updateSettings(updated)
            }
        }
    }

    private func form(_ settings: InstanceSettings) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Bark.Space.lg, verticalSpacing: Bark.Space.md) {
            GridRow {
                Text(L("advanced.name")).foregroundStyle(.secondary)
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { update { $0.name = name } }
            }
            GridRow {
                Text(L("advanced.memory")).foregroundStyle(.secondary)
                HStack {
                    Slider(
                        value: Binding(get: { Double(settings.maxMb) }, set: { value in update { $0.maxMb = UInt32(value) } }),
                        in: 1024...16384,
                        step: 512
                    )
                    .frame(width: 200)
                    Text("\(settings.maxMb / 1024) GB").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
            }
            GridRow {
                Text(L("advanced.java")).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { javaSelection(settings) }, set: { selectJava($0, settings) })) {
                    Text(L("advanced.java.auto")).tag("auto")
                    ForEach(model.scan?.java ?? []) { java in
                        Text("Java \(java.version)").tag(java.path)
                    }
                    if settings.javaProvider == "custom", !(model.scan?.java.contains { $0.path == settings.javaPath } ?? false) {
                        Text(settings.javaPath).tag(settings.javaPath)
                    }
                    Divider()
                    Text(L("advanced.java.custom")).tag("choose")
                }
                .labelsHidden()
                .frame(maxWidth: 280)
            }
            GridRow {
                Text(L("advanced.jvmArgs")).foregroundStyle(.secondary)
                TextField("-XX:+UseG1GC", text: $jvmArgs)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { update { $0.extraArgs = jvmArgs.split(separator: " ").map(String.init) } }
            }
            GridRow {
                Text(L("advanced.window")).foregroundStyle(.secondary)
                HStack {
                    TextField("", value: Binding(get: { settings.width }, set: { value in update { $0.width = value } }), format: .number)
                        .frame(width: 70)
                    Text("×")
                    TextField("", value: Binding(get: { settings.height }, set: { value in update { $0.height = value } }), format: .number)
                        .frame(width: 70)
                }
                .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Color.clear.frame(width: 0, height: 0)
                Text(L("advanced.hint")).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.top, Bark.Space.sm)
    }

    private func javaSelection(_ settings: InstanceSettings) -> String {
        settings.javaProvider == "custom" && !settings.javaPath.isEmpty ? settings.javaPath : "auto"
    }

    private func selectJava(_ selection: String, _ settings: InstanceSettings) {
        var updated = settings
        switch selection {
        case "choose": choosingJava = true; return
        case "auto": updated.javaProvider = "mojang"; updated.javaPath = ""
        default: updated.javaProvider = "custom"; updated.javaPath = selection
        }
        model.updateSettings(updated)
    }

    private func sync(_ settings: InstanceSettings?) {
        draft = settings
        name = settings?.name ?? ""
        jvmArgs = settings?.extraArgs.joined(separator: " ") ?? ""
    }

    private func update(_ change: (inout InstanceSettings) -> Void) {
        guard var updated = draft else { return }
        change(&updated)
        model.updateSettings(updated)
    }
}
