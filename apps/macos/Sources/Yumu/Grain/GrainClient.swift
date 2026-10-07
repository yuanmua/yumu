import CGrain
import Foundation

struct GrainEvent: Sendable {
    let topic: String
    let data: Data
}

/// The only place that touches the C interface of the core.
final class GrainClient: Sendable {
    nonisolated(unsafe) private let core: OpaquePointer
    private let box: Unmanaged<EventBox>
    let events: AsyncStream<GrainEvent>

    init(dataDir: URL? = nil) throws {
        let (stream, continuation) = AsyncStream<GrainEvent>.makeStream()
        events = stream
        let box = Unmanaged.passRetained(EventBox(continuation: continuation))
        self.box = box
        var config: [String: String] = [:]
        if let dataDir { config["dataDir"] = dataDir.path }
        let configJSON = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        guard let core = grain_init(configJSON, eventCallback, box.toOpaque()) else {
            box.release()
            throw GrainError(kind: "INTERNAL", detail: String(cString: grain_last_init_error()))
        }
        self.core = core
    }

    deinit {
        grain_shutdown(core)
        box.release()
    }

    func call<R: Decodable>(_ method: String) throws -> R {
        try call(method, Empty())
    }

    func call<R: Decodable>(_ method: String, _ params: some Encodable) throws -> R {
        try decode(response(grain_call(core, method, encode(params))))
    }

    func start(_ method: String, _ params: some Encodable) throws -> String {
        let task: TaskRef = try decode(response(grain_start(core, method, encode(params))))
        return task.taskId
    }

    func cancel(_ taskId: String) {
        grain_string_free(grain_cancel(core, taskId))
    }

    private func encode(_ params: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(params), as: UTF8.self)
    }

    private func response(_ raw: UnsafeMutablePointer<CChar>?) -> Data {
        guard let raw else { return Data() }
        defer { grain_string_free(raw) }
        return Data(bytes: raw, count: strlen(raw))
    }

    private func decode<R: Decodable>(_ data: Data) throws -> R {
        let response = try JSONDecoder().decode(Response<R>.self, from: data)
        if let error = response.err { throw error }
        guard let value = response.ok else { throw GrainError(kind: "INTERNAL", detail: "empty response") }
        return value
    }
}

private struct Response<R: Decodable>: Decodable {
    let ok: R?
    let err: GrainError?
}

private struct Topic: Decodable {
    let topic: String
}

private final class EventBox: Sendable {
    let continuation: AsyncStream<GrainEvent>.Continuation

    init(continuation: AsyncStream<GrainEvent>.Continuation) {
        self.continuation = continuation
    }
}

/// Runs on a core thread: hand the event to the stream and return immediately.
private let eventCallback: GrainEventFn = { json, userData in
    guard let json, let userData else { return }
    let data = Data(bytes: json, count: strlen(json))
    guard let head = try? JSONDecoder().decode(Topic.self, from: data) else { return }
    Unmanaged<EventBox>.fromOpaque(userData).takeUnretainedValue()
        .continuation.yield(GrainEvent(topic: head.topic, data: data))
}
