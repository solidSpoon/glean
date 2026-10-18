import GleanCore
import Photos
import SwiftUI

@main
struct GleanApp: App {
    init() {
        LaunchEnvironment.warnIfUnbundled()
    }

    var body: some Scene {
        WindowGroup("glean") {
            ContentView()
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @State private var status: PHAuthorizationStatus = PhotoAccess.current
    @State private var assets: [GleanAsset] = []
    @State private var scanning = false
    @State private var preview: PreviewItem?
    @State private var showLog = false
    @StateObject private var runner = AnalysisRunner()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            metrics
            summary
            content
            footer
        }
        .padding(20)
        .sheet(item: $preview) { item in
            PreviewSheet(item: item)
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("glean")
                .font(.system(size: 26, weight: .semibold, design: .serif))
            Text("拾穗：把一次拍摄里值得留下的那一张挑出来。")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if status == .notDetermined {
                    Button("请求相册访问权限") {
                        Task { status = await PhotoAccess.request() }
                    }
                    .keyboardShortcut(.defaultAction)
                } else if status == .authorized || status == .limited {
                    Button("扫描图库") { scan() }
                        .disabled(scanning || runner.running)

                    Button("分析最近 300 张") { analyze() }
                        .disabled(scanning || runner.running || assets.isEmpty)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Text("需要在系统设置 → 隐私与安全性 → 照片 里允许访问。")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if scanning || runner.running {
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

    private var metrics: some View {
        HStack(spacing: 20) {
            metric("授权", describe(status))
            metric("资产", "\(assets.count)")
            metric("连拍", "\(assets.filter { $0.burstID != nil }.count)")
            metric("截图", "\(assets.filter(\.isScreenshot).count)")
            if !runner.groups.isEmpty {
                metric("照片组", "\(runner.groups.filter { $0.kind == .photo }.count)")
                metric("截图组", "\(runner.groups.filter { $0.kind == .screenshot }.count)")
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, design: .monospaced))
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(runner.summary.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        if runner.groups.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Text(runner.running ? "分析中…" : "还没有结果")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("点上面的「分析最近 300 张」")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(runner.groups.enumerated()), id: \.element.id) { offset, group in
                        GroupSectionView(index: offset + 1, group: group, preview: $preview)
                        if offset < runner.groups.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.trailing, 6)
            }
        }
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 8) {
                Text("日志：")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(runner.logPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(showLog ? "收起日志" : "查看日志") { showLog.toggle() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
            if showLog {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(runner.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 110)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - 动作

    private func scan() {
        scanning = true
        Task {
            let loaded = LibraryScanner.loadAssets()
            await MainActor.run {
                assets = loaded
                scanning = false
            }
        }
    }

    private func analyze() {
        Task { await runner.run(assets: assets) }
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
