import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNew = false

    var body: some View {
        @Bindable var model = model
        Group {
            if let startupError = model.startupError {
                ContentUnavailableView(
                    String(format: L("startup.failed"), startupError),
                    systemImage: "exclamationmark.triangle"
                )
            } else {
                NavigationSplitView {
                    InstanceList(showingNew: $showingNew)
                } detail: {
                    if let id = model.selectedID, let instance = model.instances.first(where: { $0.id == id }) {
                        InstanceDetailView(instance: instance)
                    } else {
                        EmptyStateView(showingNew: $showingNew)
                    }
                }
            }
        }
        .task {
            model.refresh()
            await model.listen()
        }
        .sheet(isPresented: $showingNew) { NewInstanceSheet() }
        .alert(L("error.title"), isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error?.localizedMessage ?? "")
        }
    }
}

struct InstanceList: View {
    @Environment(AppModel.self) private var model
    @Binding var showingNew: Bool
    @State private var pendingDelete: InstanceSummary?

    var body: some View {
        @Bindable var model = model
        List(model.instances, selection: $model.selectedID) { instance in
            InstanceRow(instance: instance, activity: model.activity[instance.id])
                .tag(instance.id)
                .contextMenu {
                    Button(L("instances.delete"), role: .destructive) { pendingDelete = instance }
                }
        }
        .navigationTitle(L("instances.title"))
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .toolbar {
            ToolbarItem {
                Button { showingNew = true } label: { Label(L("instances.new"), systemImage: "plus") }
            }
        }
        .barkAnimation(Bark.Motion.standard, value: model.instances)
        .confirmationDialog(
            String(format: L("instances.delete.confirm"), pendingDelete?.name ?? ""),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("instances.delete.action"), role: .destructive) {
                if let pendingDelete { model.deleteInstance(pendingDelete.id) }
            }
            Button(L("common.cancel"), role: .cancel) {}
        }
    }
}

struct InstanceRow: View {
    let instance: InstanceSummary
    let activity: Activity?

    var body: some View {
        HStack(spacing: Bark.Space.md) {
            Image(systemName: "cube.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                Text(instance.gameVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch activity {
            case .running:
                Circle().fill(.green).frame(width: 8, height: 8)
            case .preparing, .installing:
                ProgressView().controlSize(.small)
            case nil:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }
}
