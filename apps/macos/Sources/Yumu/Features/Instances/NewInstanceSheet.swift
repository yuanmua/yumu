import SwiftUI

struct NewInstanceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var version = ""
    @State private var loader = "vanilla"
    @State private var loaderVersion = ""
    @State private var icon = PixelArt.Biome.forest
    @State private var advanced = false
    private static let loaders = ["vanilla", "fabric", "quilt", "forge", "neoforge"]

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("new.title")).font(Bark.Text.title)
                Text(L("new.subtitle")).font(.system(size: 12)).foregroundStyle(Bark.Colors.textSecondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Bark.Space.lg, verticalSpacing: Bark.Space.md) {
                GridRow {
                    label(L("new.name"))
                    TextField("", text: $name, prompt: Text(version)).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    label(L("new.version"))
                    if let versions = model.versions {
                        Picker("", selection: $version) {
                            ForEach(versions.versions) { candidate in
                                Text(candidate.id == versions.latestRelease ? "\(candidate.id)（\(L("new.latest"))）" : candidate.id).tag(candidate.id)
                            }
                        }
                        .labelsHidden()
                    } else {
                        HStack(spacing: Bark.Space.sm) {
                            ProgressView().controlSize(.small)
                            Text(L("new.loadingVersions")).foregroundStyle(Bark.Colors.textSecondary)
                        }
                    }
                }
                GridRow {
                    label(L("new.loader"))
                    Picker("", selection: $loader) {
                        ForEach(Self.loaders, id: \.self) { Text(L("loader.\($0)")).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                GridRow {
                    label(L("new.icon"))
                    HStack(spacing: 6) {
                        ForEach(PixelArt.Biome.allCases, id: \.self) { biome in
                            Button { icon = biome } label: {
                                PixelArt(seed: name.isEmpty ? version : name, biome: biome)
                                    .frame(width: 30, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(icon == biome ? Color.accentColor : Color.clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Bark.Space.lg)
            .background(Bark.Colors.surfaceSunken, in: RoundedRectangle(cornerRadius: Bark.Radius.md, style: .continuous))
            DisclosureGroup(isExpanded: $advanced) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Bark.Space.lg, verticalSpacing: Bark.Space.md) {
                    GridRow {
                        label(L("new.loaderVersion"))
                        TextField("", text: $loaderVersion, prompt: Text(L("new.loaderVersion.recommended"))).textFieldStyle(.roundedBorder).disabled(loader == "vanilla")
                    }
                    GridRow {
                        Color.clear.frame(width: 0, height: 0)
                        Text(L("new.advanced.hint")).font(.system(size: 11)).foregroundStyle(Bark.Colors.textTertiary)
                    }
                }
                .padding(.top, Bark.Space.sm)
            } label: {
                Text(L("new.advanced")).font(.system(size: 12, weight: .medium)).foregroundStyle(Bark.Colors.textSecondary)
            }
            HStack {
                Spacer()
                Button(L("common.cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.secondary)
                Button(L("new.create")) {
                    model.createInstance(name: name.isEmpty ? version : name, version: version, loader: loader, loaderVersion: loaderVersion, icon: icon)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primary)
                .disabled(version.isEmpty)
            }
        }
        .padding(Bark.Space.xl)
        .frame(width: 500)
        .task {
            model.loadVersions()
            if version.isEmpty, let latest = model.versions?.latestRelease { version = latest }
        }
        .onChange(of: model.versions?.latestRelease) { _, latest in
            if version.isEmpty, let latest { version = latest }
        }
        .onChange(of: loader) { _, loader in icon = PixelArt.defaultBiome(loader: loader, version: version) }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(Bark.Colors.textSecondary).frame(width: 80, alignment: .trailing)
    }
}
