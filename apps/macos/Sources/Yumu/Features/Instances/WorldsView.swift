import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every world of the instance, read from `saves/`.
struct WorldsView: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let worlds: [WorldInfo]
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.md) {
            HStack {
                Text(String(format: L("worlds.count"), worlds.count, ByteCountFormatter.string(fromByteCount: Int64(worlds.reduce(0) { $0 + $1.sizeBytes }), countStyle: .file)))
                    .font(.system(size: 13)).foregroundStyle(Bark.Colors.textSecondary)
                Spacer()
                Button { importing = true } label: { Label(L("worlds.import"), systemImage: "square.and.arrow.down") }
                    .buttonStyle(.secondary).disabled(model.importingSave)
                Button { NSWorkspace.shared.open(LocalFiles.gameDirectory(instance.id).appending(path: "saves")) } label: { Label(L("worlds.folder"), systemImage: "folder") }
                    .buttonStyle(.secondary)
            }
            if worlds.isEmpty {
                VStack(spacing: Bark.Space.sm) {
                    Image(systemName: "globe.americas").font(.system(size: 36, weight: .light)).foregroundStyle(Bark.Colors.textTertiary)
                    Text(L("worlds.empty")).font(.system(size: 13)).foregroundStyle(Bark.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .insetCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(worlds) { world in
                        WorldRow(instance: instance, world: world)
                        if world.id != worlds.last?.id { Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1).padding(.leading, Bark.Space.lg) }
                    }
                }
                .insetCard()
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.importSave(url.path, into: instance.id) }
        }
        .barkAnimation(Bark.Motion.standard, value: worlds)
    }
}
