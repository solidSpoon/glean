import GleanCore
import Photos
import SwiftUI

@main
struct GleanApp: App {
    var body: some Scene {
        WindowGroup("glean") {
            ContentView()
                .frame(minWidth: 820, minHeight: 540)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @State private var status: PHAuthorizationStatus = PhotoAccess.current
    @State private var assets: [GleanAsset] = []
    @State private var busy = false
    @StateObject private var runner = AnalysisRunner()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            summary
            report
        }
        .padding(20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("glean")
                .font(.system(size: 28, weight: .semibold, design: .serif))
            Text("拾穗：把一次拍摄里值得留下的那一张挑出来。")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if status == .notDetermined {
                    Button("请求相册访问权限") {
                        Task {
                            status = await PhotoAccess.request()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                } else if status == .authorized || status == .limited {
                    Button("扫描图库") { scan() }
                        .disabled(busy || runner.running)

                    Button("分析最近 300 张") { analyze() }
                        .disabled(busy || runner.running || assets.isEmpty)
                } else {
                    Text("需要在系统设置 → 隐私与安全性 → 照片 里允许访问。")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if busy || runner.running {
                    ProgressView().controlSize(.small)
                }
                if !runner.progress.isEmpty {
                    Text(runner.progress)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 18) {
            metric("授权", describe(status))
            metric("资产", "\(assets.count)")
            metric("连拍", "\(assets.filter { $0.burstID != nil }.count)")
            metric("截图", "\(assets.filter(\.isScreenshot).count)")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout).monospacedDigit()
        }
    }

    private var report: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(runner.report.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("──") ? .primary : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func scan() {
        busy = true
        Task {
            let loaded = LibraryScanner.loadAssets()
            await MainActor.run {
                assets = loaded
                busy = false
            }
        }
    }

    private func analyze() {
        Task {
            await runner.run(assets: assets)
        }
    }

    private func describe(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "未决定"
        case .restricted: return "受限"
        case .denied: return "已拒绝"
        case .authorized: return "完整授权"
        case .limited: return "仅选中照片"
        @unknown default: return "未知"
        }
    }
}
