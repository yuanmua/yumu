import SwiftUI

struct NewInstanceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var version = ""
    @State private var loader = "vanilla"
    private static let loaders = ["vanilla", "fabric", "quilt", "forge", "neoforge"]

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.lg) {
            Text(L("new.title"))
                .font(.title2.weight(.semibold))
            Form {
                TextField(L("new.name"), text: $name, prompt: Text(version))
                if let versions = model.versions {
                    Picker(L("new.version"), selection: $version) {
                        ForEach(versions.versions) { candidate in
                            Text(candidate.id == versions.latestRelease
                                ? "\(candidate.id) (\(L("new.latest")))"
                                : candidate.id)
                                .tag(candidate.id)
                        }
                    }
                } else {
                    HStack(spacing: Bark.Space.sm) {
                        ProgressView().controlSize(.small)
                        Text(L("new.loadingVersions")).foregroundStyle(.secondary)
                    }
                }
                Picker(L("new.loader"), selection: $loader) {
                    ForEach(Self.loaders, id: \.self) { Text(L("loader.\($0)")).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("common.cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("new.create")) {
                    model.createInstance(name: name.isEmpty ? version : name, version: version, loader: loader)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(version.isEmpty)
            }
        }
        .padding(Bark.Space.xl)
        .frame(width: 440)
        .task {
            model.loadVersions()
            if version.isEmpty, let latest = model.versions?.latestRelease { version = latest }
        }
        .onChange(of: model.versions?.latestRelease) { _, latest in
            if version.isEmpty, let latest { version = latest }
        }
    }
}
