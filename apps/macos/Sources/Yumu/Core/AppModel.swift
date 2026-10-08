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
    case search(String)
    case installMod(instance: String, project: String)
    case importPack
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
    private(set) var searchResults: [SearchHit]?
    private(set) var searching = false
    private(set) var installingProjects: Set<String> = []
    private(set) var importing: Activity?
    var error: GrainError?
    let startupError: String?

    private let client: GrainClient?
    private var tasks: [String: TaskKind] = [:]

    init() {
        do {
            client = try GrainClient()
            startupError = nil
        } catch {
            client = nil
            startupError = (error as? GrainError)?.detail ?? error.localizedDescription
        }
    }

    var selected: InstanceSummary? {
        instances.first { $0.id == selectedID }
    }

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

    func play(_ id: String, playerName: String) {
        guard let client, activity[id] == nil else { return }
        do {
            let taskId = try client.start("instance.launch", LaunchParams(id: id, playerName: playerName))
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

    func searchMods(_ id: String, query: String) {
        guard let client else { return }
        do {
            tasks[try client.start("mod.search", SearchParams(id: id, query: query, offset: 0))] = .search(id)
            searching = true
        } catch {
            report(error)
        }
    }

    func clearSearch() {
        searchResults = nil
        searching = false
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
                case .search:
                    searchResults = try decoder.decode(Envelope<TaskCompleted<SearchResult>>.self, from: event.data).payload.result.hits
                    searching = false
                case .installMod(let instance, let project):
                    installingProjects.remove(project)
                    if instance == selectedID { loadMods(instance) }
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
        case .search: searching = false
        case .installMod(_, let project): installingProjects.remove(project)
        case .importPack: importing = nil
        case .versions, nil: break
        }
    }

    private func report(_ error: Error) {
        self.error = error as? GrainError ?? GrainError(kind: "INTERNAL", detail: error.localizedDescription)
    }
}
