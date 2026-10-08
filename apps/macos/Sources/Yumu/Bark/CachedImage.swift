import AppKit
import CryptoKit
import SwiftUI

/// Remote image with a memory and disk cache, so artwork shows instantly on every launch and works offline.
struct CachedImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.none)
            } else {
                placeholder()
            }
        }
        .task(id: url) { image = await ImageCache.shared.image(for: url) }
    }
}

actor ImageCache {
    static let shared = ImageCache()

    private var memory: [URL: NSImage] = [:]
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Yumu/icons")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    func image(for url: URL) async -> NSImage? {
        if let cached = memory[url] { return cached }
        if let running = inFlight[url] { return await running.value }
        let file = directory.appending(path: SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined())
        let task = Task<NSImage?, Never> {
            if let data = try? Data(contentsOf: file), let image = NSImage(data: data) { return image }
            var request = URLRequest(url: url)
            request.setValue("Yumu/0.1 (github.com/yuanmua/yumu)", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request), let image = NSImage(data: data) else { return nil }
            try? data.write(to: file, options: .atomic)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory[url] = image }
        return image
    }
}
