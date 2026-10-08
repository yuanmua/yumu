import AppKit
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, download, java, accounts, about

    var id: String { rawValue }
    var titleKey: String { "prefs.\(rawValue)" }

    var icon: (String, Color) {
        switch self {
        case .general: ("slider.horizontal.3", .gray)
        case .appearance: ("paintpalette.fill", .pink)
        case .download: ("arrow.down.circle.fill", .blue)
        case .java: ("cpu.fill", .orange)
        case .accounts: ("person.2.fill", .green)
        case .about: ("info.circle.fill", .indigo)
        }
    }
}

/// The preferences window (⌘,): System Settings layout, one group of rows per section.
struct SettingsView: View {
    @State private var section = SettingsSection.general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.allCases) { item in
                    Button { section = item } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(item.icon.1).frame(width: 24, height: 24)
                                .overlay(Image(systemName: item.icon.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
                            Text(L(item.titleKey)).font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(section == item ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: Bark.Radius.sm, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(Bark.Space.md)
            .frame(width: 190)
            .background(Bark.Colors.backgroundSidebar)
            ScrollView {
                VStack(alignment: .leading, spacing: Bark.Space.xl) {
                    Text(L(section.titleKey)).font(.system(size: 22, weight: .bold))
                    switch section {
                    case .general: GeneralSettings()
                    case .appearance: AppearanceSettings()
                    case .download: DownloadSettings()
                    case .java: JavaSettings()
                    case .accounts: AccountSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(Bark.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Bark.Colors.backgroundCanvas)
        }
        .frame(width: 820, height: 560)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.afterLaunch) private var afterLaunch = "keep"
    @AppStorage(Prefs.notifyOnExit) private var notify = true
    @AppStorage(Prefs.discover) private var discover = true

    var body: some View {
        SettingGroup(L("prefs.launch")) {
            SettingRow(L("prefs.afterLaunch")) {
                Picker("", selection: $afterLaunch) {
                    Text(L("prefs.afterLaunch.keep")).tag("keep")
                    Text(L("prefs.afterLaunch.hide")).tag("hide")
                }
                .labelsHidden().frame(width: 180)
            }
            SettingRow(L("prefs.notify"), detail: L("prefs.notify.hint")) { Toggle("", isOn: $notify).toggleStyle(.switch).labelsHidden() }
        }
        SettingGroup(L("prefs.local")) {
            SettingRow(L("prefs.discover"), detail: L("prefs.discover.hint")) { Toggle("", isOn: $discover).toggleStyle(.switch).labelsHidden() }
            SettingRow(L("prefs.dataDir"), detail: LocalFiles.dataDirectory.path) {
                Button(L("prefs.open")) { NSWorkspace.shared.open(LocalFiles.dataDirectory) }.buttonStyle(.secondary)
            }
        }
    }
}

private struct AppearanceSettings: View {
    @AppStorage(Prefs.theme) private var theme = "system"
    @AppStorage(Prefs.density) private var density = "comfortable"
    @AppStorage(Prefs.sidebarCovers) private var covers = true

    var body: some View {
        SettingGroup(L("prefs.theme")) {
            HStack(spacing: Bark.Space.lg) {
                ForEach([("system", L("prefs.theme.system")), ("light", L("prefs.theme.light")), ("dark", L("prefs.theme.dark"))], id: \.0) { value, name in
                    Button { theme = value } label: {
                        VStack(spacing: 8) {
                            ThemeThumb(value: value)
                                .frame(width: 108, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme == value ? Color.accentColor : Bark.Colors.borderStrong, lineWidth: theme == value ? 2 : 1))
                            Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(theme == value ? Bark.Colors.textPrimary : Bark.Colors.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Bark.Space.lg)
        }
        SettingGroup(L("prefs.interface")) {
            SettingRow(L("prefs.accent"), detail: L("prefs.accent.hint")) {
                Circle().fill(Color.accentColor).frame(width: 22, height: 22)
            }
            SettingRow(L("prefs.density")) {
                Picker("", selection: $density) {
                    Text(L("prefs.density.comfortable")).tag("comfortable")
                    Text(L("prefs.density.compact")).tag("compact")
                }
                .labelsHidden().frame(width: 140)
            }
            SettingRow(L("prefs.sidebarCovers")) { Toggle("", isOn: $covers).toggleStyle(.switch).labelsHidden() }
            SettingRow(L("prefs.language"), detail: L("prefs.language.hint")) {
                Button(L("prefs.language.open")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                }
                .buttonStyle(.secondary)
            }
        }
    }
}

private struct ThemeThumb: View {
    let value: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch value {
            case "light": Color(hex: 0xF3F1EC)
            case "dark": Color(hex: 0x1D1C1A)
            default: HStack(spacing: 0) { Color(hex: 0xF3F1EC); Color(hex: 0x1D1C1A) }
            }
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(.gray.opacity(0.3)).frame(width: 26)
                RoundedRectangle(cornerRadius: 3).fill(Color.accentColor).frame(height: 10)
            }
            .padding(10)
        }
    }
}

private struct DownloadSettings: View {
    @AppStorage(Prefs.downloadSource) private var source = "auto"
    @AppStorage(Prefs.concurrency) private var concurrency = 8
    @AppStorage(Prefs.proxy) private var proxy = ""

    var body: some View {
        SettingGroup(L("prefs.source")) {
            SettingRow(L("prefs.source.pick"), detail: L("prefs.source.hint")) {
                Picker("", selection: $source) {
                    Text(L("prefs.source.auto")).tag("auto")
                    Text(L("prefs.source.official")).tag("official")
                    Text(L("prefs.source.bmclapi")).tag("bmclapi")
                }
                .labelsHidden().frame(width: 160)
            }
            SettingRow(L("prefs.concurrency")) {
                Stepper(value: $concurrency, in: 1...32) { Text(String(concurrency)).monospacedDigit().frame(width: 28, alignment: .trailing) }
            }
            SettingRow(L("prefs.proxy"), detail: L("prefs.proxy.hint")) {
                TextField("http://127.0.0.1:7890", text: $proxy).textFieldStyle(.roundedBorder).frame(width: 240)
            }
        }
        SettingGroup(L("prefs.cache")) {
            SettingRow(L("prefs.cache.shared"), detail: L("prefs.cache.hint")) {
                Button(L("prefs.open")) { NSWorkspace.shared.open(LocalFiles.dataDirectory.appending(path: "cache")) }.buttonStyle(.secondary)
            }
        }
        Text(L("prefs.backendPending")).font(.system(size: 11)).foregroundStyle(Bark.Colors.textTertiary)
    }
}

private struct JavaSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.defaultMemoryMb) private var defaultMemory = 4096

    var body: some View {
        SettingGroup(L("prefs.javaList")) {
            SettingRow(L("advanced.java.auto"), detail: L("prefs.javaList.hint")) { Tag(text: L("prefs.javaList.auto"), tone: .accent) }
            ForEach(model.scan?.java ?? []) { java in
                SettingRow("Java \(java.version)", detail: java.path) { EmptyView() }
            }
            SettingRow(L("prefs.javaRescan"), detail: nil) {
                Button(L("prefs.javaRescan.action")) { model.rescan() }.buttonStyle(.secondary).disabled(model.scanning)
            }
        }
        SettingGroup(L("prefs.defaults")) {
            SettingRow(L("prefs.defaultMemory"), detail: L("prefs.defaultMemory.hint")) {
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { Double(defaultMemory) }, set: { defaultMemory = Int($0) }), in: 1024...Double(AppModel.physicalMemoryMb), step: 512).frame(width: 180)
                    Text("\(defaultMemory / 1024) GB").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
        }
        .task { if model.scan == nil { model.rescan() } }
    }
}

private struct AccountSettings: View {
    @Environment(AppModel.self) private var model
    @State private var addingOffline = false

    var body: some View {
        SettingGroup(L("prefs.accounts")) {
            ForEach(model.accounts) { account in
                SettingRow(account.name, detail: "\(L("account.kind.\(account.kind)")) · \(account.uuid)") {
                    if account.active {
                        Tag(text: L("account.current"), tone: .accent)
                    } else {
                        Button(L("account.switch")) { model.setActiveAccount(account.id) }.buttonStyle(.secondary)
                    }
                    Button { model.removeAccount(account.id) } label: { Image(systemName: "trash") }.buttonStyle(.quiet).help(L("account.remove"))
                }
            }
            SettingRow(L("account.addTitle"), detail: model.canAddOffline ? nil : L("account.offlineHint")) {
                Button(L("account.addMicrosoft")) { model.beginMicrosoftLogin() }.buttonStyle(.primary)
                Button(L("account.addOffline")) { addingOffline = true }.buttonStyle(.secondary).disabled(!model.canAddOffline)
            }
        }
        .task { model.loadAccounts() }
        .sheet(isPresented: $addingOffline) { OfflineAccountSheet() }
        .sheet(isPresented: Binding(get: { model.loggingIn }, set: { if !$0 { model.cancelLogin() } })) { LoginSheet() }
    }
}

private struct AboutSettings: View {
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    var body: some View {
        HStack(spacing: Bark.Space.lg) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.accentColor).frame(width: 72, height: 72)
                .overlay(Image(systemName: "cube.fill").font(.system(size: 34)).foregroundStyle(.white))
                .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text("Yumu").font(.system(size: 24, weight: .bold))
                Text(String(format: L("about.version"), version)).font(.system(size: 12)).foregroundStyle(Bark.Colors.textSecondary)
            }
            Spacer()
            Button(L("about.checkUpdates")) {}.buttonStyle(.secondary).disabled(true).help(L("empty.comingSoon"))
        }
        SettingGroup(L("about.links")) {
            link(L("about.source"), icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/yuanmua/yumu")
            link(L("about.issue"), icon: "exclamationmark.bubble", url: "https://github.com/yuanmua/yumu/issues")
            SettingRow(L("about.logs"), detail: nil) {
                Button(L("prefs.open")) { NSWorkspace.shared.open(FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appending(path: "Logs/Yumu")) }.buttonStyle(.secondary)
            }
        }
        Text(L("about.credits")).font(.system(size: 11)).foregroundStyle(Bark.Colors.textTertiary).lineSpacing(3)
    }

    private func link(_ title: String, icon: String, url: String) -> some View {
        SettingRow(title, detail: nil) {
            Button { if let link = URL(string: url) { NSWorkspace.shared.open(link) } } label: { Image(systemName: "arrow.up.right") }.buttonStyle(.quiet)
        }
    }
}
