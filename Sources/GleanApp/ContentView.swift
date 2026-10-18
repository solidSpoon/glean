import GleanCore
import Photos
import SwiftUI

enum GroupFilter: String, CaseIterable, Identifiable {
    case all
    case photo
    case screenshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .photo: return "照片"
        case .screenshot: return "截图"
        }
    }
}

struct ContentView: View {
    @State private var status: PHAuthorizationStatus = PhotoAccess.current
    @State private var assets: [GleanAsset] = []
    @State private var scanning = false
    @State private var preview: PreviewState?
    @State private var filter: GroupFilter = .all
    @State private var showLog = false
    @StateObject private var runner = AnalysisRunner()

    private var visibleGroups: [AnalyzedGroup] {
        switch filter {
        case .all: return runner.groups
        case .photo: return runner.groups.filter { $0.kind == .photo }
        case .screenshot: return runner.groups.filter { $0.kind == .screenshot }
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: 14) {
                header
                statsBar
                content
                footer
            }
            .padding(18)

            if let state = preview {
                PreviewOverlay(state: Binding(
                    get: { preview },
                    set: { preview = $0 }
                ))
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.22), value: preview?.id)
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("glean")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                Text("拾穗 · 把一次拍摄里值得留下的那一张挑出来")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if status == .notDetermined {
                        Button("请求相册权限") {
                            Task { status = await PhotoAccess.request() }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    } else if status == .authorized || status == .limited {
                        Button("扫描图库", systemImage: "arrow.clockwise") { scan() }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            .disabled(scanning || runner.running)

                        Button("分析最近 300 张", systemImage: "sparkles") { analyze() }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(scanning || runner.running || assets.isEmpty)
                            .keyboardShortcut(.return, modifiers: .command)
                    } else {
                        Button("去系统设置授权") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }

                    if scanning || runner.running {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16)
                    }
                }
            }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            stat("授权", describe(status))
            stat("资产", "\(assets.count)")
            stat("连拍", "\(assets.filter { $0.burstID != nil }.count)")
            stat("截图", "\(assets.filter(\.isScreenshot).count)")

            Divider().frame(height: 22)

            stat("照片组", "\(runner.groups.filter { $0.kind == .photo }.count)")
            stat("截图组", "\(runner.groups.filter { $0.kind == .screenshot }.count)")

            Spacer(minLength: 8)

            filterChips

            if runner.running, runner.progressValue > 0 {
                ProgressView(value: runner.progressValue)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text(runner.progressLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
        }
    }

    private var filterChips: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(GroupFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        option == filter
                            ? Glass.regular.tint(Color.accentColor.opacity(0.55)).interactive()
                            : Glass.regular.interactive(),
                        in: .capsule
                    )
                    .disabled(runner.groups.isEmpty)
                    .opacity(runner.groups.isEmpty ? 0.45 : 1)
                }
            }
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        if visibleGroups.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { offset, group in
                        GroupCardView(index: offset + 1, group: group) { index in
                            preview = PreviewState(group: group, index: index)
                        }
                    }
                }
                .padding(.bottom, 6)
                .padding(.trailing, 4)
            }
            .scrollIndicators(.never)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: runner.running ? "hourglass" : "photo.stack")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(runner.running ? "分析中…" : (runner.summary.isEmpty ? "还没有结果" : "没有发现相似组"))
                .font(.callout)
            Text(runner.summary.isEmpty ? "点右上角「分析最近 300 张」" : "样本小的时候这很正常，可以加大样本量再试")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if !runner.summary.isEmpty {
                    GlassTag(text: runner.summary.first ?? "", systemImage: "info.circle")
                    Text(runner.summary.dropFirst().joined(separator: "   "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Button(showLog ? "收起原始日志" : "原始日志") { showLog.toggle() }
                    .buttonStyle(.glass)
                    .controlSize(.small)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([GleanLog.shared.textURL])
                } label: {
                    Label("日志文件夹", systemImage: "folder")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            Text(runner.logPath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            if showLog {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(runner.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 110)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.07), lineWidth: 1)
                )
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
