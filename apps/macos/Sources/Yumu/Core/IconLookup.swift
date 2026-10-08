import CryptoKit
import Foundation

/// Finds Modrinth artwork for files on disk by hash, so mods and packs from anywhere get their real icon.
/// Temporary: the core already hashes every download and should store the project id and icon itself.
enum IconLookup {
    struct Item: Sendable {
        let key: String
        let path: URL
    }

    private struct VersionFile: Decodable { let projectId: String; enum CodingKeys: String, CodingKey { case projectId = "project_id" } }
    private struct Project: Decodable { let id: String; let iconUrl: String?; enum CodingKeys: String, CodingKey { case id, iconUrl = "icon_url" } }

    /// Returns `key → icon URL` for every item Modrinth recognises. Runs off the main thread.
    static func resolve(_ items: [Item]) async -> [String: String] {
        let hashed: [(key: String, hash: String)] = await Task.detached(priority: .utility) {
            items.compactMap { item in sha1(item.path).map { (item.key, $0) } }
        }.value
        guard !hashed.isEmpty else { return [:] }
        var projectByHash: [String: String] = [:]
        for batch in stride(from: 0, to: hashed.count, by: 100).map({ Array(hashed[$0..<min($0 + 100, hashed.count)]) }) {
            var request = URLRequest(url: URL(string: "https://api.modrinth.com/v2/version_files")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["hashes": batch.map(\.hash), "algorithm": "sha1"])
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let found = try? JSONDecoder().decode([String: VersionFile].self, from: data) else { continue }
            for (hash, file) in found { projectByHash[hash] = file.projectId }
        }
        guard !projectByHash.isEmpty else { return [:] }
        var iconByProject: [String: String] = [:]
        let ids = Array(Set(projectByHash.values))
        for batch in stride(from: 0, to: ids.count, by: 100).map({ Array(ids[$0..<min($0 + 100, ids.count)]) }) {
            var components = URLComponents(string: "https://api.modrinth.com/v2/projects")!
            components.queryItems = [URLQueryItem(name: "ids", value: String(decoding: (try? JSONEncoder().encode(batch)) ?? Data(), as: UTF8.self))]
            var request = URLRequest(url: components.url!)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let projects = try? JSONDecoder().decode([Project].self, from: data) else { continue }
            for project in projects { if let icon = project.iconUrl { iconByProject[project.id] = icon } }
        }
        var result: [String: String] = [:]
        for (key, hash) in hashed {
            if let project = projectByHash[hash], let icon = iconByProject[project] { result[key] = icon }
        }
        return result
    }

    private static let userAgent = "Yumu/0.1 (github.com/yuanmua/yumu)"

    private static func sha1(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
