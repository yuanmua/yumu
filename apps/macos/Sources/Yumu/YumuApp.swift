import SwiftUI

@main
struct YumuApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 600)
    }
}
