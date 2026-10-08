import SwiftUI
import UniformTypeIdentifiers

/// Per-instance settings. Defaults always work; the advanced group is folded.
struct InstanceSettingsView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let delete: () -> Void
    @State private var draft: InstanceSettings?
    @State private var name = ""
    @State private var jvmArgs = ""
    @State private var choosingJava = false
    @State private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.xl) {
            SettingGroup(L("settings.instance.general")) {
                SettingRow(L("settings.instance.name")) {
                    TextField("", text: $name).textFieldStyle(.roundedBorder).frame(width: 240).onSubmit { update { $0.name = name } }
                }
                SettingRow(L("settings.instance.icon"), detail: L("settings.instance.icon.hint")) { iconPicker }
                SettingRow(L("settings.instance.favorite"), detail: L("settings.instance.favorite.hint")) {
                    Toggle("", isOn: Binding(get: { model.favorites.contains(instance.id) }, set: { _ in model.toggleFavorite(instance.id) }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            if let draft {
                SettingGroup(L("settings.instance.game")) {
                    SettingRow(L("settings.instance.window"), detail: L("settings.instance.window.hint")) {
                        HStack(spacing: 6) {
                            TextField("", value: Binding(get: { draft.width }, set: { value in update { $0.width = value } }), format: .number).frame(width: 64)
                            Text("×").foregroundStyle(Bark.Colors.textTertiary)
                            TextField("", value: Binding(get: { draft.height }, set: { value in update { $0.height = value } }), format: .number).frame(width: 64)
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                }
                SettingGroup(L("settings.instance.java")) {
                    SettingRow(L("settings.instance.memory"), detail: String(format: L("settings.instance.memory.hint"), physicalGigabytes)) {
                        HStack(spacing: 10) {
                            Slider(value: Binding(get: { Double(draft.maxMb) }, set: { value in update { $0.maxMb = UInt32(value) } }), in: 1024...Double(AppModel.physicalMemoryMb), step: 512).frame(width: 180)
                            Text("\(draft.maxMb / 1024) GB").monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                    }
                    SettingRow(L("settings.instance.javaPick"), detail: L("settings.instance.javaPick.hint")) {
                        Picker("", selection: Binding(get: { javaSelection(draft) }, set: { selectJava($0, draft) })) {
                            Text(L("advanced.java.auto")).tag("auto")
                            ForEach(model.scan?.java ?? []) { java in Text("Java \(java.version)").tag(java.path) }
                            if draft.javaProvider == "custom", !(model.scan?.java.contains { $0.path == draft.javaPath } ?? false) {
                                Text(draft.javaPath).tag(draft.javaPath)
                            }
                            Divider()
                            Text(L("advanced.java.custom")).tag("choose")
                        }
                        .labelsHidden().frame(width: 240)
                    }
                }
                VStack(alignment: .leading, spacing: Bark.Space.sm) {
                    Button { withAnimation(Bark.Motion.standard) { advanced.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(advanced ? 90 : 0))
                            Text(L("settings.instance.advanced"))
                        }
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Bark.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, Bark.Space.xs)
                    if advanced {
                        SettingGroup {
                            SettingRow(L("settings.instance.jvmArgs"), detail: L("settings.instance.jvmArgs.hint")) {
                                TextField("-XX:+UseG1GC", text: $jvmArgs).textFieldStyle(.roundedBorder).frame(width: 300)
                                    .onSubmit { update { $0.extraArgs = jvmArgs.split(separator: " ").map(String.init) } }
                            }
                            SettingRow(L("settings.instance.loaderVersion")) {
                                Text(instance.loaderVersion.isEmpty ? "—" : instance.loaderVersion).foregroundStyle(Bark.Colors.textSecondary).monospacedDigit()
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                }
            }
            SettingGroup {
                SettingRow(L("settings.instance.delete"), detail: L("settings.instance.delete.hint")) {
                    Button(L("settings.instance.deleteAction")) { delete() }.buttonStyle(.danger)
                }
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

    private var iconPicker: some View {
        HStack(spacing: 6) {
            ForEach(PixelArt.Biome.allCases, id: \.self) { biome in
                let chosen = model.icon(for: instance)
                Button { model.setIcon(instance.id, biome: biome) } label: {
                    PixelArt(seed: instance.id, biome: biome)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(chosen == biome ? Color.accentColor : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var physicalGigabytes: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) }

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
        guard settings == nil || settings?.id == instance.id else { return }
        draft = settings
        name = settings?.name ?? instance.name
        jvmArgs = settings?.extraArgs.joined(separator: " ") ?? ""
    }

    private func update(_ change: (inout InstanceSettings) -> Void) {
        guard var updated = draft else { return }
        change(&updated)
        model.updateSettings(updated)
    }
}
