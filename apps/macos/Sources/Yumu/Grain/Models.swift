import Foundation

struct InstanceSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let gameVersion: String
    let loaderKind: String
    let loaderVersion: String
    let lastPlayedAt: UInt64
    let playtimeSeconds: UInt64
    let running: Bool

    var isVanilla: Bool { loaderKind == "vanilla" }
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

struct ModRecord: Codable, Hashable, Sendable {
    let projectId: String
    let versionId: String
    let title: String
    let versionNumber: String
}

struct LocalMod: Codable, Identifiable, Hashable, Sendable {
    let fileName: String
    let enabled: Bool
    let size: UInt64
    let name: String
    let version: String
    let record: ModRecord?

    var id: String { fileName }
    var displayName: String { record?.title ?? name }
}

struct SearchHit: Codable, Identifiable, Hashable, Sendable {
    let projectId: String
    let slug: String
    let title: String
    let description: String
    let iconUrl: String?
    let downloads: UInt64
    let author: String

    var id: String { projectId }
}

struct SearchResult: Codable, Hashable, Sendable {
    let hits: [SearchHit]
    let totalHits: UInt64
}

struct ResourceFile: Codable, Identifiable, Hashable, Sendable {
    let fileName: String
    let enabled: Bool
    let size: UInt64

    var id: String { fileName }
}

enum ResourceKind: String, CaseIterable, Sendable {
    case shaderpacks, resourcepacks

    var titleKey: String {
        self == .shaderpacks ? "resources.shaders" : "resources.resourcePacks"
    }

    var projectType: String {
        self == .shaderpacks ? "shader" : "resourcepack"
    }
}

struct AccountSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: String
    let name: String
    let uuid: String
    let active: Bool

    var isMicrosoft: Bool { kind == "microsoft" }
}

struct LoginCode: Decodable, Hashable, Sendable {
    let userCode: String
    let verificationUri: String
}

struct CoreInfo: Decodable, Sendable {
    let version: String
    let offlineWithoutMicrosoft: Bool
}

struct InstanceSettings: Codable, Hashable, Sendable {
    let id: String
    var name: String
    let gameVersion: String
    let loaderKind: String
    let loaderVersion: String
    var javaProvider: String
    var javaPath: String
    var maxMb: UInt32
    var extraArgs: [String]
    var width: UInt32
    var height: UInt32
}

struct Scan: Decodable, Hashable, Sendable {
    let installations: [Installation]
    let java: [JavaInstall]
}

struct Installation: Decodable, Hashable, Sendable {
    let launcher: String
    let path: String
    let versions: [String]
    let saves: [Save]
}

struct Save: Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let path: String
    let lastPlayed: UInt64

    var id: String { path }
}

struct JavaInstall: Decodable, Identifiable, Hashable, Sendable {
    let path: String
    let version: String
    let major: UInt32

    var id: String { path }
}

struct SaveParams: Encodable, Sendable { let id: String; let path: String }
struct Empty: Codable, Sendable {}
struct NameParams: Encodable, Sendable { let name: String }
struct ProjectParams: Encodable, Sendable { let projectId: String }
struct IdParams: Codable, Sendable { let id: String }
struct CreateParams: Encodable, Sendable { let name: String; let gameVersion: String; let loaderKind: String }
struct LaunchParams: Encodable, Sendable { let id: String }
struct VersionParams: Encodable, Sendable { let snapshots: Bool }
struct SearchParams: Encodable, Sendable {
    let id: String?
    let projectType: String
    let query: String
    var offset: UInt32 = 0
}
struct ModInstallParams: Encodable, Sendable { let id: String; let projectId: String }
struct FileParams: Encodable, Sendable { let id: String; let fileName: String; let enabled: Bool }
struct ResourceParams: Encodable, Sendable {
    let id: String
    let kind: String
    var fileName: String = ""
    var enabled: Bool = false
    var path: String = ""
    var projectId: String = ""
}
struct PackParams: Encodable, Sendable { let path: String }

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
