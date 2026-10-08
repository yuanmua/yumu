import AppKit
import SwiftUI

/// Account picker shown at the bottom of the sidebar.
struct AccountBar: View {
    @Environment(AppModel.self) private var model
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
                .disabled(!model.hasMicrosoftAccount)
            if let active = model.activeAccount {
                Divider()
                Button(L("account.remove"), role: .destructive) { model.removeAccount(active.id) }
            }
        } label: {
            HStack(spacing: Bark.Space.sm) {
                Image(systemName: model.activeAccount?.isMicrosoft == true ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.activeAccount?.name ?? L("account.none"))
                        .lineLimit(1)
                    if let active = model.activeAccount {
                        Text(L("account.kind.\(active.kind)"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .padding(Bark.Space.md)
        .background(.bar)
        .help(model.hasMicrosoftAccount ? "" : L("account.offlineHint"))
        .sheet(isPresented: $addingOffline) { OfflineAccountSheet() }
        .sheet(isPresented: Binding(get: { model.loggingIn }, set: { if !$0 { model.cancelLogin() } })) {
            LoginSheet()
        }
        .task { model.loadAccounts() }
    }
}

struct LoginSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Bark.Space.lg) {
            Text(L("account.login.title")).font(.title2.weight(.semibold))
            if let code = model.loginCode {
                Text(code.userCode)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .kerning(4)
                    .textSelection(.enabled)
                Text(L("account.login.instructions"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
                HStack(spacing: Bark.Space.sm) {
                    ProgressView().controlSize(.small)
                    Text(L("account.login.waiting")).font(.caption).foregroundStyle(.secondary)
                }
                .onAppear { present(code) }
            } else {
                ProgressView()
            }
            HStack {
                Button(L("common.cancel"), role: .cancel) { model.cancelLogin() }
                    .keyboardShortcut(.cancelAction)
                if let code = model.loginCode {
                    Button(L("account.login.open")) { present(code) }
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
            Text(L("account.offline.title")).font(.title2.weight(.semibold))
            TextField(L("account.offline.name"), text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(L("common.cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("account.add")) {
                    model.addOfflineAccount(name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Bark.Space.xl)
        .frame(width: 360)
    }
}
