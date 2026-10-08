import AppKit
import SwiftUI

/// Account picker shown at the bottom of the sidebar.
struct AccountBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var addingOffline = false

    var body: some View {
        Menu {
            ForEach(model.accounts) { account in
                Button {
                    model.setActiveAccount(account.id)
                } label: {
                    if account.active {
                        Label(account.name, systemImage: "checkmark")
                    } else {
                        Text(account.name)
                    }
                }
            }
            if !model.accounts.isEmpty { Divider() }
            Button(L("account.addMicrosoft")) { model.beginMicrosoftLogin() }
            Button(L("account.addOffline")) { addingOffline = true }
                .disabled(!model.canAddOffline)
            Divider()
            Button(L("account.manage")) { openSettings() }
        } label: {
            HStack(spacing: Bark.Space.sm) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: model.activeAccount == nil ? "person" : "person.fill").font(.system(size: 13)).foregroundStyle(Color.accentColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.activeAccount?.name ?? L("account.none")).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(model.activeAccount.map { L("account.kind.\($0.kind)") } ?? L("account.addTitle"))
                        .font(.system(size: 11)).foregroundStyle(Bark.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Bark.Colors.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(model.offlineWithoutMicrosoft ? L("account.devOffline") : model.hasMicrosoftAccount ? "" : L("account.offlineHint"))
        .sheet(isPresented: $addingOffline) { OfflineAccountSheet() }
        .sheet(isPresented: Binding(get: { model.loggingIn }, set: { if !$0 { model.cancelLogin() } })) { LoginSheet() }
        .task { model.loadAccounts() }
    }
}

struct LoginSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Bark.Space.lg) {
            Text(L("account.login.title")).font(Bark.Text.title)
            if let code = model.loginCode {
                Text(code.userCode)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .kerning(4)
                    .textSelection(.enabled)
                Text(L("account.login.instructions"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Bark.Colors.textSecondary)
                    .frame(maxWidth: 360)
                HStack(spacing: Bark.Space.sm) {
                    ProgressView().controlSize(.small)
                    Text(L("account.login.waiting")).font(.system(size: 11)).foregroundStyle(Bark.Colors.textSecondary)
                }
                .onAppear { present(code) }
            } else {
                ProgressView()
            }
            HStack {
                Button(L("common.cancel"), role: .cancel) { model.cancelLogin() }.keyboardShortcut(.cancelAction).buttonStyle(.secondary)
                if let code = model.loginCode {
                    Button(L("account.login.open")) { present(code) }.buttonStyle(.primary)
                }
            }
        }
        .padding(Bark.Space.xxl)
        .frame(width: 440)
        .barkAnimation(Bark.Motion.standard, value: model.loginCode)
    }

    private func present(_ code: LoginCode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.userCode, forType: .string)
        if let url = URL(string: code.verificationUri) { NSWorkspace.shared.open(url) }
    }
}

struct OfflineAccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Bark.Space.lg) {
            Text(L("account.offline.title")).font(Bark.Text.title)
            TextField(L("account.offline.name"), text: $name).textFieldStyle(.roundedBorder).controlSize(.large)
            HStack {
                Spacer()
                Button(L("common.cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.secondary)
                Button(L("account.add")) {
                    model.addOfflineAccount(name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primary)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Bark.Space.xl)
        .frame(width: 380)
    }
}
