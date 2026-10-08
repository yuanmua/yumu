import Darwin
import Foundation
import Observation
import SwiftUI

/// Getting an instance ready to launch; `running` is tracked per process in `processes`.
enum Activity: Equatable, Sendable {
    case preparing
    case installing(done: UInt64, total: UInt64)
}

/// One game process. The same instance may run several times at once.
struct RunningProcess: Identifiable, Hashable, Sendable {
    let pid: Int32
    let instanceId: String
    let startedAt: Date

    var id: Int32 { pid }
}

private enum TaskKind {
    case launch(String)
    case versions
    case search(SearchScope, append: Bool)
    case installMod(instance: String, project: String)
    case installResource(instance: String, kind: ResourceKind, project: String)
    case importPack
    case login
    case scan
    case importSave(instance: String)
}

/// What the detail area shows; instances are the default.
enum Page: Hashable, Sendable {
    case instances, packs, monitor
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
    var page = Page.instances
    var showingNew = false
    var choosingImport = false
    var sidebarVisibility = NavigationSplitViewVisibility.all
    private(set) var activity: [String: Activity] = [:]
    private(set) var processes: [RunningProcess] = []
    private(set) var stats: [Int32: ProcessStats] = [:]
    private(set) var versions: VersionList?
    private(set) var mods: [LocalMod] = []
    private(set) var resources: [ResourceKind: [ResourceFile]] = [:]
    private(set) var worlds: [String: [WorldInfo]] = [:]
    private(set) var searchResults: [SearchScope: [SearchHit]] = [:]
    private(set) var searchTotals: [SearchScope: UInt64] = [:]
    private var searchQueries: [SearchScope: String] = [:]
    private(set) var searching: Set<SearchScope> = []
    private(set) var installingProjects: Set<String> = []
    private(set) var importing: Activity?
    private(set) var accounts: [AccountSummary] = []
    private(set) var offlineWithoutMicrosoft = false
    private(set) var settings: InstanceSettings?
    private(set) var scan: Scan?
    private(set) var scanning = false
    private(set) var importingSave = false
    private(set) var crashes: [String: (crash: Crash, logPath: String?)] = [:]
    private(set) var loginCode: LoginCode?
    private(set) var loggingIn = false
    private(set) var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Prefs.favorites) ?? [])
    private(set) var icons: [String: PixelArt.Biome] = [:]
    /// Modrinth artwork for installed mods (`project:<id>`) and instances made from modpacks (`instance:<id>`).
    private(set) var iconURLs: [String: String] = UserDefaults.standard.dictionary(forKey: "iconURLs") as? [String: String] ?? [:]
    private var pendingPackIcon: String?
    private(set) var installingPack: String?
    private var lookingUpIcons = false
    private var modsRequest = 0

    /// Physical memory in MB, the ceiling for every memory slider.
    static let physicalMemoryMb = UInt32(min(ProcessInfo.processInfo.physicalMemory / 1_048_576, 262_144))
    var error: GrainError?
    let startupError: String?

    private let client: GrainClient?
    private var tasks: [String: TaskKind] = [:]
    private var sampler = ProcessSampler()

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
        Task { await listen() }
    }

    func iconURL(for instance: InstanceSummary) -> URL? {
        iconURLs["instance:\(instance.id)"].flatMap(URL.init)
    }

    func iconURL(for mod: LocalMod) -> URL? {
        (mod.record.flatMap { iconURLs["project:\($0.projectId)"] } ?? iconURLs[Self.fileKey(mod.fileName, mod.size)]).flatMap(URL.init)
    }

    func iconURL(for file: ResourceFile) -> URL? {
        iconURLs[Self.fileKey(file.fileName, file.size)].flatMap(URL.init)
    }

    private static func fileKey(_ name: String, _ size: UInt64) -> String { "file:\(name):\(size)" }

    private func rememberIcon(_ key: String, url: String?) {
        guard let url, !url.isEmpty else { return }
        iconURLs[key] = url
        UserDefaults.standard.set(iconURLs, forKey: "iconURLs")
    }

    /// Matches files on disk to Modrinth projects by hash and remembers their artwork.
    private func lookUpIcons(instanceId: String, mods: [LocalMod], resources: [(ResourceKind, ResourceFile)]) {
        var items: [IconLookup.Item] = []
        let game = LocalFiles.gameDirectory(instanceId)
        for mod in mods where iconURL(for: mod) == nil {
            items.append(.init(key: Self.fileKey(mod.fileName, mod.size), path: game.appending(path: "mods/\(mod.fileName)")))
        }
        for (kind, file) in resources where iconURL(for: file) == nil {
            items.append(.init(key: Self.fileKey(file.fileName, file.size), path: game.appending(path: "\(kind.rawValue)/\(file.fileName)")))
        }
        let pending = items.filter { iconURLs[$0.key + ":checked"] == nil }
        guard !pending.isEmpty, !lookingUpIcons else { return }
        lookingUpIcons = true
        Task {
            let found = await IconLookup.resolve(pending)
            for item in pending { iconURLs[item.key + ":checked"] = "1" }
            for (key, url) in found { iconURLs[key] = url }
            UserDefaults.standard.set(iconURLs, forKey: "iconURLs")
            lookingUpIcons = false
        }
    }

    func icon(for instance: InstanceSummary) -> PixelArt.Biome {
        if let chosen = icons[instance.id] { return chosen }
        if let raw = UserDefaults.standard.string(forKey: Prefs.icon(instance.id)), let saved = PixelArt.Biome(rawValue: raw) { return saved }
        return PixelArt.defaultBiome(loader: instance.loaderKind, version: instance.gameVersion)
    }

    var selected: InstanceSummary? {
        instances.first { $0.id == selectedID }
    }

    /// Versions other launchers have that no instance covers yet, and worlds from everywhere.
    var foundVersions: [FoundVersion] {
        (scan?.installations ?? []).flatMap(\.versions).filter { found in
            !instances.contains { $0.gameVersion == found.gameVersion && $0.loaderKind == found.loaderKind }
        }
    }

    var foundSaves: [Save] { (scan?.installations ?? []).flatMap(\.saves) }

    var activeAccount: AccountSummary? { accounts.first { $0.active } }
    var hasMicrosoftAccount: Bool { accounts.contains { $0.isMicrosoft } }
    var canAddOffline: Bool { hasMicrosoftAccount || offlineWithoutMicrosoft }

    func processes(for instanceId: String) -> [RunningProcess] {
        processes.filter { $0.instanceId == instanceId }
    }

    func isRunning(_ instanceId: String) -> Bool {
        processes.contains { $0.instanceId == instanceId }
    }

    func instance(_ id: String) -> InstanceSummary? {
        instances.first { $0.id == id }
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

    func createInstance(name: String, version: String, loader: String, loaderVersion: String = "", icon: PixelArt.Biome? = nil) {
        guard let client else { return }
        do {
            let params = CreateParams(name: uniqueName(name), gameVersion: version, loaderKind: loader, loaderVersion: loaderVersion)
            let created: IdParams = try client.call("instance.create", params)
            if let icon { setIcon(created.id, biome: icon) }
            refresh()
            selectedID = created.id
        } catch {
            report(error)
        }
    }

    /// "26.2" becomes "26.2 2" when an instance of that name exists; the core refuses duplicates.
    private func uniqueName(_ name: String) -> String {
        let taken = Set(instances.flatMap { [$0.name.lowercased(), $0.id.lowercased()] })
        var candidate = name, counter = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(name) \(counter)"
            counter += 1
        }
        return candidate
    }

    func deleteInstance(_ id: String) {
        guard let client else { return }
        do {
            let _: Empty = try client.call("instance.delete", IdParams(id: id))
            favorites.remove(id)
            saveFavorites()
            UserDefaults.standard.removeObject(forKey: Prefs.icon(id))
            icons[id] = nil
            refresh()
        } catch {
            report(error)
        }
    }

    func rename(_ id: String, to name: String) {
        guard let client else { return }
        do {
            var current: InstanceSettings = try client.call("instance.get", IdParams(id: id))
            current.name = name
            let _: Empty = try client.call("instance.update", current)
            if settings?.id == id { settings = current }
            refresh()
        } catch {
            report(error)
        }
    }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        saveFavorites()
    }

    func setIcon(_ id: String, biome: PixelArt.Biome) {
        UserDefaults.standard.set(biome.rawValue, forKey: Prefs.icon(id))
        icons[id] = biome
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: Prefs.favorites)
    }

    /// Launches another process even if the instance is already running; only a launch in progress blocks.
    func play(_ id: String) {
        guard let client, activity[id] == nil else { return }
        do {
            let taskId = try client.start("instance.launch", LaunchParams(id: id))
            tasks[taskId] = .launch(id)
            activity[id] = .preparing
            crashes[id] = nil
        } catch {
            report(error)
        }
    }

    /// Asks the game to quit. The launcher signals the detached process directly; the core reports the exit.
    func stop(pid: Int32) {
        kill(pid, SIGTERM)
    }

    func stopAll(_ instanceId: String) {
        for process in processes(for: instanceId) { stop(pid: process.pid) }
    }

    func sampleStats() {
        for process in processes {
            if let sample = sampler.sample(process.pid) { stats[process.pid] = sample }
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
            refresh()
        } catch {
            report(error)
        }
    }

    func loadWorlds(_ id: String) {
        worlds[id] = LocalFiles.worlds(id)
    }

    // MARK: Discover

    func rescan() {
        guard let client, !scanning, UserDefaults.standard.bool(forKey: Prefs.discover) else { return }
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

    /// Reads jar metadata off the main thread; a modpack with hundreds of mods must not freeze the window.
    func loadMods(_ id: String) {
        guard let client else { return }
        modsRequest += 1
        let request = modsRequest
        Task {
            do {
                let loaded: [LocalMod] = try await Task.detached(priority: .userInitiated) { try client.call("mod.listInstalled", IdParams(id: id)) }.value
                guard request == modsRequest else { return }
                mods = loaded
                lookUpIcons(instanceId: id, mods: loaded, resources: [])
            } catch {
                report(error)
            }
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

    func search(_ scope: SearchScope, query: String, offset: UInt32 = 0) {
        guard let client, !searching.contains(scope) else { return }
        var params: SearchParams = switch scope {
        case .mods(let id): SearchParams(id: id, projectType: "mod", query: query)
        case .resources(let id, let kind): SearchParams(id: id, projectType: kind.projectType, query: query)
        case .packs: SearchParams(id: nil, projectType: "modpack", query: query)
        }
        params.offset = offset
        searchQueries[scope] = query
        do {
            tasks[try client.start("mod.search", params)] = .search(scope, append: offset > 0)
            searching.insert(scope)
        } catch {
            report(error)
        }
    }

    func canLoadMore(_ scope: SearchScope) -> Bool {
        UInt64(searchResults[scope]?.count ?? 0) < (searchTotals[scope] ?? 0)
    }

    func loadMore(_ scope: SearchScope) {
        search(scope, query: searchQueries[scope] ?? "", offset: UInt32(searchResults[scope]?.count ?? 0))
    }

    func clearSearch(_ scope: SearchScope) {
        searchResults[scope] = nil
        searchTotals[scope] = nil
        searching.remove(scope)
    }

    func installMod(_ id: String, projectId: String, iconUrl: String? = nil) {
        guard let client, !installingProjects.contains(projectId) else { return }
        rememberIcon("project:\(projectId)", url: iconUrl)
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
        lookUpIcons(instanceId: id, mods: [], resources: ResourceKind.allCases.flatMap { kind in (resources[kind] ?? []).map { (kind, $0) } })
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

    func installPack(projectId: String, iconUrl: String? = nil) {
        guard let client, importing == nil else { return }
        pendingPackIcon = iconUrl
        installingPack = projectId
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

    private func listen() async {
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
                case .search(let scope, let append):
                    let result = try decoder.decode(Envelope<TaskCompleted<SearchResult>>.self, from: event.data).payload.result
                    searchResults[scope] = append ? (searchResults[scope] ?? []) + result.hits : result.hits
                    searchTotals[scope] = result.totalHits
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
                case .importSave(let instance):
                    importingSave = false
                    loadWorlds(instance)
                case .importPack:
                    importing = nil
                    let created = try decoder.decode(Envelope<TaskCompleted<IdParams>>.self, from: event.data).payload.result
                    rememberIcon("instance:\(created.id)", url: pendingPackIcon)
                    pendingPackIcon = nil
                    installingPack = nil
                    refresh()
                    selectedID = created.id
                case .launch(let id):
                    // `game.started` carries the pid; the task only tells us preparation is over.
                    activity[id] = nil
                case nil:
                    break
                }
            case "task.failed":
                let failure = try decoder.decode(Envelope<TaskFailed>.self, from: event.data).payload
                finish(task: failure.taskId)
                error = failure.error
            case "task.cancelled":
                finish(task: try decoder.decode(Envelope<TaskRef>.self, from: event.data).payload.taskId)
            case "game.started":
                let started = try decoder.decode(Envelope<GameEvent>.self, from: event.data).payload
                activity[started.instanceId] = nil
                processes.append(RunningProcess(pid: started.pid ?? -Int32(processes.count + 1), instanceId: started.instanceId, startedAt: Date()))
            case "game.exited":
                let exited = try decoder.decode(Envelope<GameExited>.self, from: event.data).payload
                // The event has no pid yet, so the oldest process of that instance is the one assumed gone.
                if let index = processes.firstIndex(where: { process in exited.pid.map { $0 == process.pid } ?? (process.instanceId == exited.instanceId) }) {
                    let gone = processes.remove(at: index)
                    stats[gone.pid] = nil
                    sampler.forget(gone.pid)
                }
                if let crash = exited.crash { crashes[exited.instanceId] = (crash, exited.logPath) }
                refresh()
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
        case .search(let scope, _): searching.remove(scope)
        case .installMod(_, let project), .installResource(_, _, let project): installingProjects.remove(project)
        case .importPack:
            importing = nil
            pendingPackIcon = nil
            installingPack = nil
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

private struct ModrinthProject: Decodable {
    let id: String
    let iconUrl: String?

    enum CodingKeys: String, CodingKey { case id, iconUrl = "icon_url" }
}
