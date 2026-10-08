import SwiftUI

/// Worlds, versions and Java runtimes found on this computer, with one-click import.
struct DiscoverSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.md) {
            HStack {
                Text(L("discover.title")).font(.title2.weight(.semibold))
                Spacer()
                if model.scanning || model.importingSave { ProgressView().controlSize(.small) }
                Button(L("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let scan = model.scan {
                if scan.installations.isEmpty {
                    Text(L("discover.nothing")).foregroundStyle(.secondary)
                }
                List {
                    ForEach(scan.installations, id: \.path) { installation in
                        if !installation.saves.isEmpty {
                            Section(L("discover.saves") + " · " + L("discover.launcher.\(installation.launcher)")) {
                                ForEach(installation.saves) { save in saveRow(save) }
                            }
                        }
                        if !installation.versions.isEmpty {
                            Section(L("discover.versions") + " · " + L("discover.launcher.\(installation.launcher)")) {
                                ForEach(installation.versions, id: \.self) { version in versionRow(version) }
                            }
                        }
                    }
                    if !scan.java.isEmpty {
                        Section(L("discover.java")) {
                            ForEach(scan.java) { java in
                                HStack {
                                    Text("Java \(java.version)")
                                    Spacer()
                                    Text(java.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: Bark.Radius.md, style: .continuous))
            } else {
                HStack(spacing: Bark.Space.sm) {
                    ProgressView().controlSize(.small)
                    Text(L("discover.scanning")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(Bark.Space.xl)
        .frame(width: 600, height: 540)
        .task { model.rescan() }
    }

    private func saveRow(_ save: Save) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(save.name)
                if save.lastPlayed > 0 {
                    Text(Date(timeIntervalSince1970: TimeInterval(save.lastPlayed)).formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu(L("discover.importTo")) {
                ForEach(model.instances) { instance in
                    Button("\(instance.name) · \(instance.gameVersion)") {
                        model.importSave(save.path, into: instance.id)
                    }
                }
            }
            .controlSize(.small)
            .fixedSize()
            .disabled(model.instances.isEmpty || model.importingSave)
        }
    }

    private func versionRow(_ version: String) -> some View {
        HStack {
            Text(version)
            Spacer()
            Button(L("discover.createInstance")) {
                model.createInstance(name: version, version: version, loader: "vanilla")
                dismiss()
            }
            .controlSize(.small)
        }
    }
}
