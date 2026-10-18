import SwiftUI

@main
struct GrazeApp: App {
    init() {
        LaunchEnvironment.warnIfUnbundled()
    }

    var body: some Scene {
        WindowGroup("graze") {
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
