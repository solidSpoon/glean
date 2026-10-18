import SwiftUI

@main
struct GleanApp: App {
    init() {
        LaunchEnvironment.warnIfUnbundled()
    }

    var body: some Scene {
        WindowGroup("glean") {
            ContentView()
                .frame(minWidth: 940, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
