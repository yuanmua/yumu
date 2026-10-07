import Foundation

struct InstanceSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let gameVersion: String
    let loaderKind: String
    let lastPlayedAt: UInt64
    let playtimeSeconds: UInt64
    let running: Bool
}

struct GameVersion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: String
    let releaseTime: String
}

struct VersionList: Codable, Hashable, Sendable {
    let latestRelease: String
    let versions: [GameVersion]
}

struct Empty: Codable, Sendable {}
struct IdParams: Codable, Sendable { let id: String }
struct CreateParams: Encodable, Sendable { let name: String; let gameVersion: String }
struct LaunchParams: Encodable, Sendable { let id: String; let playerName: String }
struct VersionParams: Encodable, Sendable { let snapshots: Bool }

struct Envelope<P: Decodable & Sendable>: Decodable, Sendable { let topic: String; let payload: P }
struct TaskRef: Decodable, Sendable { let taskId: String }
struct TaskProgress: Decodable, Sendable { let taskId: String; let bytesDone: UInt64; let bytesTotal: UInt64 }
struct TaskCompleted<R: Decodable & Sendable>: Decodable, Sendable { let taskId: String; let result: R }
struct TaskFailed: Decodable, Sendable { let taskId: String; let error: GrainError }
struct GameEvent: Decodable, Sendable { let instanceId: String }

/// A scalar from an error's `args`; nested values are not needed for messages.
enum JSONValue: Decodable, Sendable, Hashable, CustomStringConvertible {
    case string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    var description: String {
        switch self {
        case .string(let value): value
        case .number(let value): value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): String(value)
        case .null: ""
        }
    }
}

struct GrainError: Error, Decodable, Hashable, Sendable {
    let kind: String
    let args: [String: JSONValue]
    let detail: String?

    init(kind: String, args: [String: JSONValue] = [:], detail: String? = nil) {
        self.kind = kind
        self.args = args
        self.detail = detail
    }

    /// The translated message for this error, with `{arg}` placeholders filled in.
    var localizedMessage: String {
        let key = "error.\(kind)"
        var text = L(key)
        if text == key { text = detail ?? kind }
        for (name, value) in args {
            text = text.replacingOccurrences(of: "{\(name)}", with: value.description)
        }
        return text
    }
}
