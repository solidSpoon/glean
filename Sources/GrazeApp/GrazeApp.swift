import SwiftUI

@main
struct GrazeApp: App {
    init() {
        LaunchEnvironment.warnIfUnbundled()
    }

    var body: some Scene {
        WindowGroup("graze") {
            ContentView()
        }
        // 窗口最小尺寸只由 ContentView 的 frame(minWidth:minHeight:) 决定，
        // 不在这里再写一份——两处写不同的值只会互相打架。
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
