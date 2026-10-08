import SwiftUI

/// Procedural pixel landscape used as an instance icon, so instances without artwork still look alive.
struct PixelArt: View {
    enum Biome: String, CaseIterable, Sendable {
        case forest, plains, cave, sky, nether, snow

        var sky: (Color, Color) {
            switch self {
            case .forest: (Color(hex: 0x9FD3FF), Color(hex: 0xDFF2FF))
            case .plains: (Color(hex: 0x8EC9FF), Color(hex: 0xE6F4FF))
            case .cave: (Color(hex: 0x2B2F36), Color(hex: 0x3B414B))
            case .sky: (Color(hex: 0x6FB5FF), Color(hex: 0xF5FBFF))
            case .nether: (Color(hex: 0x3A0D0D), Color(hex: 0x6B1B1B))
            case .snow: (Color(hex: 0xBCD6F0), Color(hex: 0xEEF5FB))
            }
        }

        var top: Color {
            switch self {
            case .forest: Color(hex: 0x5FAE4A)
            case .plains: Color(hex: 0x7AC54F)
            case .cave: Color(hex: 0x6D6D6D)
            case .sky: Color(hex: 0x75C951)
            case .nether: Color(hex: 0xB03A2E)
            case .snow: Color(hex: 0xF2F6F8)
            }
        }

        var dirt: Color {
            switch self {
            case .cave: Color(hex: 0x5A5A5A)
            case .nether: Color(hex: 0x5E1F1A)
            case .plains: Color(hex: 0x946140)
            default: Color(hex: 0x8A5A37)
            }
        }

        var stone: Color {
            switch self {
            case .cave: Color(hex: 0x4B4B4B)
            case .nether: Color(hex: 0x4A1612)
            default: Color(hex: 0x8C8C8C)
            }
        }

        var hasTrees: Bool { self == .forest || self == .sky || self == .snow }
        var isDark: Bool { self == .cave || self == .nether }
        var floats: Bool { self == .sky }
    }

    let seed: String
    let biome: Biome
    var columns = 12
    var rows = 12

    /// Picks a biome for an instance that has no explicit icon: loader decides, name varies the terrain.
    static func defaultBiome(loader: String, version: String) -> Biome {
        switch loader {
        case "vanilla": .plains
        case "forge", "neoforge": .cave
        case "quilt": .snow
        default: .forest
        }
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var rng = SeededRandom(seed: seed + biome.rawValue)
            let cell = CGSize(width: size.width / CGFloat(columns), height: size.height / CGFloat(rows))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [biome.sky.0, biome.sky.1]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            if !biome.isDark {
                fill(&context, x: columns - 3, y: 1, cell: cell, color: Color(hex: 0xFFF3B0))
            }
            var height = rows / 2 + Int(rng.next() * 2)
            for x in 0..<columns {
                height = max(rows / 3, min(rows - 3, height + Int((rng.next() - 0.5) * 2.4)))
                let ground = rows - height
                for y in ground..<rows {
                    if biome.floats, y > ground + 3 + Int(rng.next() * 2) { continue }
                    let base = y == ground ? biome.top : y < ground + 3 ? biome.dirt : biome.stone
                    fill(&context, x: x, y: y, cell: cell, color: base.opacity(0.9 + rng.next() * 0.1))
                }
                if biome.hasTrees, rng.next() < 0.16, x > 0, x < columns - 1 {
                    let trunk = ground - 1
                    for i in 0..<2 { fill(&context, x: x, y: trunk - i, cell: cell, color: Color(hex: 0x5A3A21)) }
                    for dx in -1...1 { for dy in 2...4 { fill(&context, x: x + dx, y: trunk - dy, cell: cell, color: Color(hex: 0x3F8F3A).opacity(0.85 + rng.next() * 0.15)) } }
                }
                if biome.isDark, rng.next() < 0.1 {
                    fill(&context, x: x, y: Int(rng.next() * 3), cell: cell, color: .white.opacity(0.35))
                }
            }
        }
    }

    private func fill(_ context: inout GraphicsContext, x: Int, y: Int, cell: CGSize, color: Color) {
        guard x >= 0, y >= 0, x < columns, y < rows else { return }
        let rect = CGRect(x: CGFloat(x) * cell.width, y: CGFloat(y) * cell.height, width: cell.width + 0.5, height: cell.height + 0.5)
        context.fill(Path(rect), with: .color(color))
    }
}

/// Deterministic generator so the same instance always draws the same terrain.
private struct SeededRandom {
    private var state: UInt32

    init(seed: String) {
        var hash: UInt32 = 2166136261
        for byte in seed.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        state = hash == 0 ? 1 : hash
    }

    mutating func next() -> Double {
        state = state &* 1664525 &+ 1013904223
        return Double(state) / Double(UInt32.max)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Instance icon at any size: the chosen or default biome, rounded.
struct InstanceIcon: View {
    @Environment(AppModel.self) private var model
    let instance: InstanceSummary
    let size: CGFloat

    var body: some View {
        Group {
            if let url = model.iconURL(for: instance) {
                CachedImage(url: url) { PixelArt(seed: instance.id, biome: model.icon(for: instance)) }
            } else {
                PixelArt(seed: instance.id, biome: model.icon(for: instance))
            }
        }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(.black.opacity(0.08)))
    }
}
