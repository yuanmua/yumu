import Foundation
import Observation

enum Activity: Equatable, Sendable {
    case preparing
    case installing(done: UInt64, total: UInt64)
    case running
}

private enum TaskKind {
    case launch(String)
    case versions
    case search(SearchScope)
    case installMod(instance: String, project: String)
    case installResource(instance: String, kind: ResourceKind, project: String)
    case importPack
    case login
    case scan
    case importSave(instance: String)
}

enum SearchScope: Hashable, Sendable {
    case mods(String)
    case resources(String, ResourceKind)
    case packs
}

@MainActor
@Observable
final class AppModel {
    private(set) var instances: [InstanceSummary] = []
    var selectedID: String?
    private(set) var activity: [String: Activity] = [:]
    private(set) var versions: VersionList?
    private(set) var mods: [LocalMod] = []
    private(set) var resources: [ResourceKind: [ResourceFile]] = [:]
    private(set) var searchResults: [SearchScope: [SearchHit]] = [:]
    private(set) var searching: Set<SearchScope> = []
    private(set) var installingProjects: Set<String> = []
    private(set) var importing: Activity?
    private(set) var accounts: [AccountSummary] = []
    private(set) var offlineWithoutMicrosoft = false
    private(set) var settings: InstanceSettings?
    private(set) var scan: Scan?
    private(set) var scanning = false
    private(set) var importingSave = false
    private(set) var loginCode: LoginCode?
    private(set) var loggingIn = false
    var error: GrainError?
    let startupError: String?

    private let client: GrainClient?
    private var tasks: [String: TaskKind] = [:]

    init() {
        do {
            let core = try GrainClient()
            let info: CoreInfo = try core.call("grain.info")
            client = core
            offlineWithoutMicrosoft = info.offlineWithoutMicrosoft
            startupError = nil
        } catch {
            client = nil
            startupError = (error as? GrainError)?.detail ?? error.localizedDescription
        }
    }

    var selected: InstanceSummary? {
        instances.first { $0.id == selectedID }
    }

    var activeAccount: AccountSummary? { accounts.first { $0.active } }
    var hasMicrosoftAccount: Bool { accounts.contains { $0.isMicrosoft } }
    var canAddOffline: Bool { hasMicrosoftAccount || offlineWithoutMicrosoft }

    // MARK: Instances

    func refresh() {
        guard let client else { return }
        do {
            instances = try client.call("instance.list")
        } catch {
            report(error)
        }
        if let selectedID, !instances.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        if selectedID == nil { selectedID = instances.first?.id }
    }

    func createInstance(name: String, version: String, loader: String) {
        guard let client else { return }
        do {
            let params = CreateParams(name: name, gameVersion: version, loaderKind: loader)
            let created: IdParams = try client.call("instance.create", params)
            refresh()
            selectedID = created.id
        } catch {
            report(error)
        }
    }

    func deleteInstance(_ id: String) {
        guard let client else { return }
        do {
            let _: Empty = try client.call("instance.delete", IdParams(id: id))
            refresh()
        } catch {
            report(error)
        }
    }

    func play(_ id: String) {
        guard let client, activity[id] == nil else { return }
        do {
            let taskId = try client.start("instance.launch", LaunchParams(id: id))
            tasks[taskId] = .launch(id)
            activity[id] = .preparing
        } catch {
            report(error)
        }
    }

    func loadVersions() {
        guard let client, versions == nil, !tasks.values.contains(where: { if case .versions = $0 { true } else { false } }) else { return }
        do {
            tasks[try client.start("version.listGame", VersionParams(snapshots: false))] = .versions
        } catch {
            report(error)
        }
    }

    func loadSettings(_ id: String) {
        guard let client else { return }
        do {
            settings = try client.call("instance.get", IdParams(id: id))
        } catch {
            report(error)
        }
    }

    func updateSettings(_ updated: InstanceSettings) {
        guard let client else { return }
        do {
            let _: Empty = try client.call("instance.update", updated)
            settings = updated
        } catch {
            report(error)
        }
    }

    // MARK: Discover

    func rescan() {
        guard let client, !scanning else { return }
        do {
            tasks[try client.start("discover.scan", Empty())] = .scan
            scanning = true
        } catch {
            report(error)
        }
    }

    func importSave(_ path: String, into instanceId: String) {
        guard let client, !importingSave else { return }
        do {
            tasks[try client.start("discover.importSave", SaveParams(id: instanceId, path: path))] = .importSave(instance: instanceId)
            importingSave = true
        } catch {
            report(error)
        }
    }

    // MARK: Mods

    func loadMods(_ id: String) {
        guard let client else { return }
        do {
            mods = try client.call("mod.listInstalled", IdParams(id: id))
        } catch {
            report(error)
        }
    }

    func setModEnabled(_ id: String, fileName: String, enabled: Bool) {
        guard let client else { return }
        do {
            let _: Empty = try client.call("mod.toggle", FileParams(id: id, fileName: fileName, enabled: enabled))
            loadMods(id)
        } catch {
            report(error)
        }
    }

    func removeMod(_ id: String, fileName: String) {
        guard let client else { return }
        do {
            let _: Empty = try client.call("mod.remove", FileParams(id: id, fileName: fileName, enabled: false))
            loadMods(id)
        } catch {
            report(error)
        }
    }

    func search(_ scope: SearchScope, query: String) {
        guard let client else { return }
        let params: SearchParams = switch scope {
        case .mods(let id): SearchParams(id: id, projectType: "mod", query: query)
        case .resources(let id, let kind): SearchParams(id: id, projectType: kind.projectType, query: query)
        case .packs: SearchParams(id: nil, projectType: "modpack", query: query)
        }
        do {
            tasks[try client.start("mod.search", params)] = .search(scope)
            searching.insert(scope)
        } catch {
            report(error)
        }
    }

    func clearSearch(_ scope: SearchScope) {
        searchResults[scope] = nil
        searching.remove(scope)
    }

    func installMod(_ id: String, projectId: String) {
        guard let client, !installingProjects.contains(projectId) else { return }
        do {
            let taskId = try client.start("mod.install", ModInstallParams(id: id, projectId: projectId))
            tasks[taskId] = .installMod(instance: id, project: projectId)
            installingProjects.insert(projectId)
        } catch {
            report(error)
        }
    }

    func isInstalled(projectId: String) -> Bool {
        mods.contains { $0.record?.projectId == projectId }
    }

    func installResource(_ id: String, kind: ResourceKind, projectId: String) {
        guard let client, !installingProjects.contains(projectId) else { return }
        do {
            let params = ResourceParams(id: id, kind: kind.rawValue, projectId: projectId)
            tasks[try client.start("resource.install", params)] = .installResource(instance: id, kind: kind, project: projectId)
            installingProjects.insert(projectId)
        } catch {
            report(error)
        }
    }

    // MARK: Resources

    func loadResources(_ id: String) {
        guard let client else { return }
        for kind in ResourceKind.allCases {
            do {
                resources[kind] = try client.call("resource.list", ResourceParams(id: id, kind: kind.rawValue))
            } catch {
                report(error)
            }
        }
    }

    func addResource(_ id: String, kind: ResourceKind, url: URL) {
        guard let client else { return }
        do {
            let params = ResourceParams(id: id, kind: kind.rawValue, path: url.path)
            let _: [String: String] = try client.call("resource.add", params)
            loadResources(id)
        } catch {
            report(error)
        }
    }

    func setResourceEnabled(_ id: String, kind: ResourceKind, fileName: String, enabled: Bool) {
        guard let client else { return }
        do {
            let params = ResourceParams(id: id, kind: kind.rawValue, fileName: fileName, enabled: enabled)
            let _: Empty = try client.call("resource.toggle", params)
            loadResources(id)
        } catch {
            report(error)
        }
    }

    func removeResource(_ id: String, kind: ResourceKind, fileName: String) {
        guard let client else { return }
        do {
            let params = ResourceParams(id: id, kind: kind.rawValue, fileName: fileName)
            let _: Empty = try client.call("resource.remove", params)
            loadResources(id)
        } catch {
            report(error)
        }
    }

    // MARK: Modpacks

    func importPack(_ url: URL) {
        guard let client, importing == nil else { return }
        do {
            tasks[try client.start("modpack.import", PackParams(path: url.path))] = .importPack
            importing = .preparing
        } catch {
            report(error)
        }
    }

    func installPack(projectId: String) {
        guard let client, importing == nil else { return }
        do {
            tasks[try client.start("modpack.installModrinth", ProjectParams(projectId: projectId))] = .importPack
            importing = .preparing
        } catch {
            report(error)
        }
    }

    // MARK: Accounts

    func loadAccounts() {
        guard let client else { return }
        do {
            accounts = try client.call("account.list")
        } catch {
            report(error)
        }
    }

    func beginMicrosoftLogin() {
        guard let client, !loggingIn else { return }
        do {
            tasks[try client.start("account.beginMicrosoftLogin", Empty())] = .login
            loggingIn = true
        } catch {
            report(error)
        }
    }

    func cancelLogin() {
        guard let client else { return }
        for (taskId, kind) in tasks {
            if case .login = kind { client.cancel(taskId) }
        }
    }

    func addOfflineAccount(name: String) {
        guard let client else { return }
        do {
            let _: [String: String] = try client.call("account.addOffline", NameParams(name: name))
            loadAccounts()
        } catch {
            report(error)
        }
    }

    func setActiveAccount(_ id: String) {
        guard let client else { return }
        do {
            let _: [String: String] = try client.call("account.setActive", IdParams(id: id))
            loadAccounts()
        } catch {
            report(error)
        }
    }

    func removeAccount(_ id: String) {
        guard let client else { return }
        do {
            let _: [String: String] = try client.call("account.remove", IdParams(id: id))
            loadAccounts()
        } catch {
            report(error)
        }
    }

    // MARK: Events

    func listen() async {
        guard let client else { return }
        for await event in client.events {
            handle(event)
        }
    }

    private func handle(_ event: GrainEvent) {
        let decoder = JSONDecoder()
        do {
            switch event.topic {
            case "task.progress":
                let progress = try decoder.decode(Envelope<TaskProgress>.self, from: event.data).payload
                let state = Activity.installing(done: progress.bytesDone, total: progress.bytesTotal)
                switch tasks[progress.taskId] {
                case .launch(let id): activity[id] = state
                case .importPack: importing = state
                default: break
                }
            case "task.completed":
                let taskId = try decoder.decode(Envelope<TaskRef>.self, from: event.data).payload.taskId
                switch tasks.removeValue(forKey: taskId) {
                case .versions:
                    versions = try decoder.decode(Envelope<TaskCompleted<VersionList>>.self, from: event.data).payload.result
                case .search(let scope):
                    searchResults[scope] = try decoder.decode(Envelope<TaskCompleted<SearchResult>>.self, from: event.data).payload.result.hits
                    searching.remove(scope)
                case .installMod(let instance, let project):
                    installingProjects.remove(project)
                    if instance == selectedID { loadMods(instance) }
                case .installResource(let instance, _, let project):
                    installingProjects.remove(project)
                    if instance == selectedID { loadResources(instance) }
                case .login:
                    loggingIn = false
                    loginCode = nil
                    loadAccounts()
                case .scan:
                    scan = try decoder.decode(Envelope<TaskCompleted<Scan>>.self, from: event.data).payload.result
                    scanning = false
                case .importSave:
                    importingSave = false
                case .importPack:
                    importing = nil
                    let created = try decoder.decode(Envelope<TaskCompleted<IdParams>>.self, from: event.data).payload.result
                    refresh()
                    selectedID = created.id
                case .launch, nil:
                    break
                }
            case "task.failed":
                let failure = try decoder.decode(Envelope<TaskFailed>.self, from: event.data).payload
                finish(task: failure.taskId)
                error = failure.error
            case "task.cancelled":
                finish(task: try decoder.decode(Envelope<TaskRef>.self, from: event.data).payload.taskId)
            case "game.started":
                activity[try decoder.decode(Envelope<GameEvent>.self, from: event.data).payload.instanceId] = .running
            case "game.exited":
                activity[try decoder.decode(Envelope<GameEvent>.self, from: event.data).payload.instanceId] = nil
            case "instance.changed":
                refresh()
            case "account.loginCode":
                loginCode = try decoder.decode(Envelope<LoginCode>.self, from: event.data).payload
            case "account.changed":
                loadAccounts()
            default:
                break
            }
        } catch {
            report(error)
        }
    }

    private func finish(task taskId: String) {
        switch tasks.removeValue(forKey: taskId) {
        case .launch(let id): activity[id] = nil
        case .search(let scope): searching.remove(scope)
        case .installMod(_, let project), .installResource(_, _, let project): installingProjects.remove(project)
        case .importPack: importing = nil
        case .login:
            loggingIn = false
            loginCode = nil
        case .scan: scanning = false
        case .importSave: importingSave = false
        case .versions, nil: break
        }
    }

    private func report(_ error: Error) {
        self.error = error as? GrainError ?? GrainError(kind: "INTERNAL", detail: error.localizedDescription)
    }
}
