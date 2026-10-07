import Foundation
import Observation

enum Activity: Equatable, Sendable {
    case preparing
    case installing(done: UInt64, total: UInt64)
    case running
}

@MainActor
@Observable
final class AppModel {
    private(set) var instances: [InstanceSummary] = []
    var selectedID: String?
    private(set) var activity: [String: Activity] = [:]
    private(set) var versions: VersionList?
    var error: GrainError?
    let startupError: String?

    private let client: GrainClient?
    /// Task id → instance id for launches in flight.
    private var launches: [String: String] = [:]
    private var versionTask: String?

    init() {
        do {
            client = try GrainClient()
            startupError = nil
        } catch {
            client = nil
            startupError = (error as? GrainError)?.detail ?? error.localizedDescription
        }
    }

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

    func createInstance(name: String, version: String) {
        guard let client else { return }
        do {
            let created: IdParams = try client.call("instance.create", CreateParams(name: name, gameVersion: version))
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
            launches[taskId] = id
            activity[id] = .preparing
        } catch {
            report(error)
        }
    }

    func loadVersions() {
        guard let client, versions == nil, versionTask == nil else { return }
        do {
            versionTask = try client.start("version.listGame", VersionParams(snapshots: false))
        } catch {
            report(error)
        }
    }

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
                if let id = launches[progress.taskId] {
                    activity[id] = .installing(done: progress.bytesDone, total: progress.bytesTotal)
                }
            case "task.completed":
                let task = try decoder.decode(Envelope<TaskRef>.self, from: event.data).payload
                if task.taskId == versionTask {
                    versions = try decoder.decode(Envelope<TaskCompleted<VersionList>>.self, from: event.data).payload.result
                    versionTask = nil
                }
                launches[task.taskId] = nil
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
        if let id = launches.removeValue(forKey: taskId) { activity[id] = nil }
        if taskId == versionTask { versionTask = nil }
    }

    private func report(_ error: Error) {
        self.error = error as? GrainError ?? GrainError(kind: "INTERNAL", detail: error.localizedDescription)
    }
}
