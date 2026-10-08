import Foundation
import SwiftUI

/// Launcher-level preferences. Stored in UserDefaults until the core owns them (`settings.get/update`).
enum Prefs {
    static let welcomeDone = "welcomeDone"
    static let theme = "theme"                 // system, light, dark
    static let density = "density"             // comfortable, compact
    static let sidebarCovers = "sidebarCovers"
    static let afterLaunch = "afterLaunch"     // keep, hide
    static let notifyOnExit = "notifyOnExit"
    static let discover = "discover"
    static let downloadSource = "downloadSource" // auto, official, bmclapi
    static let concurrency = "concurrency"
    static let proxy = "proxy"
    static let defaultMemoryMb = "defaultMemoryMb"
    static let favorites = "favorites"
    static let sidebarGroup = "sidebarGroup"   // none, version, loader
    static let sidebarSort = "sidebarSort"     // recent, name
    static let sidebarLoader = "sidebarLoader" // all or a loader kind
    static func icon(_ instanceId: String) -> String { "icon.\(instanceId)" }

    static func register() {
        UserDefaults.standard.register(defaults: [
            theme: "system", density: "comfortable", sidebarCovers: true, afterLaunch: "keep",
            notifyOnExit: true, discover: true, downloadSource: "auto", concurrency: 8, defaultMemoryMb: 4096,
            sidebarGroup: "version", sidebarSort: "recent", sidebarLoader: "all",
        ])
    }
}

extension ColorScheme {
    static func from(theme: String) -> ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
