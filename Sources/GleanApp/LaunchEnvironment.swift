import AppKit
import Darwin
import Foundation

/// 运行环境自检。
///
/// `GleanApp` 是 SwiftPM 的 executable target。直接从 Xcode 选 `GleanApp` scheme 运行、
/// 或者 `swift run`，得到的是一个没有 bundle 的裸二进制：没有 Info.plist、没有
/// NSPhotoLibraryUsageDescription，PhotoKit 一碰就被系统杀，SwiftUI 也建不出窗口。
///
/// 表现是"点了运行，什么都没发生"，很难自己想到原因。所以这里主动拦一下。
enum LaunchEnvironment {
    static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static func warnIfUnbundled() {
        guard !isBundled else { return }

        let message = """
        glean 必须从 .app bundle 里运行：裸可执行文件没有相册权限声明，窗口也建不出来。

        正确姿势（任选其一）：
          · 双击 build/Glean.app
          · 终端跑 ./scripts/run.sh
          · 在 Xcode 里打开 glean.xcodeproj，scheme 选 Glean（不是 GleanApp），再按 ⌘R
        """

        FileHandle.standardError.write(Data((message + "\n").utf8))

        // 终端里跑：打完就退，不要弹窗卡住命令行。
        if isatty(STDERR_FILENO) != 0 {
            exit(1)
        }

        // Xcode 控制台不是 TTY：弹个窗，否则用户只会看到“跑了但没界面”。
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "glean 需要以 App 方式运行"
            alert.informativeText = message
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}
