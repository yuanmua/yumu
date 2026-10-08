import SwiftUI

/// First launch: three steps, and every button leaves this page for good.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.welcomeDone) private var welcomeDone = false
    @State private var addingOffline = false

    var body: some View {
        VStack(spacing: Bark.Space.xxl) {
            HStack(spacing: 0) {
                ForEach(PixelArt.Biome.allCases, id: \.self) { biome in
                    PixelArt(seed: "welcome", biome: biome, columns: 16, rows: 10).frame(height: 76)
                }
            }
            .frame(width: 560)
            .clipShape(RoundedRectangle(cornerRadius: Bark.Radius.lg, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
            VStack(spacing: 8) {
                Text(L("welcome.title")).font(.system(size: 36, weight: .bold))
                Text(L("welcome.subtitle")).font(.system(size: 15)).foregroundStyle(Bark.Colors.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            }
            VStack(spacing: 0) {
                step(number: 1, done: model.activeAccount != nil, title: L("welcome.step1"),
                     detail: model.activeAccount.map { String(format: L("welcome.step1.done"), $0.name) } ?? L("welcome.step1.todo")) {
                    if model.activeAccount == nil {
                        Button(L("account.addMicrosoft")) { model.beginMicrosoftLogin() }.buttonStyle(.secondary)
                        if model.canAddOffline { Button(L("account.addOffline")) { addingOffline = true }.buttonStyle(.secondary) }
                    }
                }
                Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1)
                step(number: 2, done: !model.instances.isEmpty, title: L("welcome.step2"), detail: L("welcome.step2.hint")) {
                    if !model.foundSaves.isEmpty || !model.foundVersions.isEmpty {
                        Text(String(format: L("welcome.step2.found"), model.foundVersions.count, model.foundSaves.count))
                            .font(.system(size: 12)).foregroundStyle(Bark.Colors.textTertiary)
                    }
                    Button(L("packs.browse")) { finish { model.page = .packs } }.buttonStyle(.secondary)
                    Button(L("instances.new")) { finish { model.showingNew = true } }.buttonStyle(.primary)
                }
                Rectangle().fill(Bark.Colors.borderSubtle).frame(height: 1)
                step(number: 3, done: false, title: L("welcome.step3"), detail: L("welcome.step3.hint")) { EmptyView() }
            }
            .frame(width: 640)
            .insetCard()
            Button(L("welcome.skip")) { finish {} }.buttonStyle(.plain).foregroundStyle(Bark.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Bark.Space.xxl)
        .task { model.loadAccounts(); model.rescan() }
        .sheet(isPresented: $addingOffline) { OfflineAccountSheet() }
        .sheet(isPresented: Binding(get: { model.loggingIn }, set: { if !$0 { model.cancelLogin() } })) { LoginSheet() }
        .onChange(of: model.instances.count) { _, count in if count > 0 { welcomeDone = true } }
    }

    private func step<Actions: View>(number: Int, done: Bool, title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: Bark.Space.md) {
            Circle()
                .fill(done ? Bark.Colors.statusSuccess : Bark.Colors.surfaceSunken)
                .frame(width: 26, height: 26)
                .overlay {
                    if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
                    else { Text(String(number)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Bark.Colors.textSecondary) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Bark.Colors.textSecondary)
            }
            Spacer()
            actions()
        }
        .padding(Bark.Space.lg)
    }

    private func finish(_ then: () -> Void) {
        welcomeDone = true
        then()
    }
}
