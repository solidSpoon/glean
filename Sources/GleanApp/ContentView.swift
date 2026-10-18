import GleanCore
import Photos
import SwiftUI

struct ContentView: View {
    @State private var status: PHAuthorizationStatus = PhotoAccess.current
    @State private var assets: [GleanAsset] = []
    @State private var busy = false
    @State private var selection: Int?
    @State private var preview: PreviewState?
    @StateObject private var runner = AnalysisRunner()

    private var selectedGroup: AnalyzedGroup? {
        guard let selection else { return nil }
        return runner.groups.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
        } detail: {
            detail
        }
        .navigationTitle(selectedGroup.map { "第 \($0.id + 1) 组" } ?? "glean")
        .navigationSubtitle(selectedGroup.map(subtitle) ?? "")
        .toolbar { toolbar }
        .frame(minWidth: 900, minHeight: 560)
        .overlay {
            if preview != nil {
                PreviewOverlay(state: $preview)
            }
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(runner.groups) { group in
                    GroupRow(group: group)
                        .tag(group.id)
                }
            } header: {
                Text(runner.groups.isEmpty ? "相似组" : "相似组 · \(runner.groups.count)")
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if runner.groups.isEmpty {
                if runner.running {
                    ProgressView("分析中…")
                        .controlSize(.small)
                } else {
                    Text(assets.isEmpty ? "先扫描图库" : "还没有结果")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 详情

    @ViewBuilder
    private var detail: some View {
        if let group = selectedGroup {
            GroupDetailView(group: group) { index in
                preview = PreviewState(group: group, index: index)
            }
        } else {
            ContentUnavailableView(
                runner.groups.isEmpty ? "还没有相似组" : "选择一个组",
                systemImage: "photo.on.rectangle.angled",
                description: Text(
                    runner.groups.isEmpty
                        ? "点右上角「分析」开始查找"
                        : "左侧每一行是一个相似组，点开看这一组里的照片"
                )
            )
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if busy || runner.running {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if status == .notDetermined {
                Button("请求相册权限") {
                    Task { status = await PhotoAccess.request() }
                }
            } else if status == .authorized || status == .limited {
                Button {
                    scan()
                } label: {
                    Label("扫描图库", systemImage: "arrow.clockwise")
                }
                .disabled(busy || runner.running)
                .help("读取相册资产列表")

                Button {
                    analyze()
                } label: {
                    Label("分析", systemImage: "sparkles")
                }
                .disabled(busy || runner.running || assets.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("分析最近 300 张，找出相似组")
            } else {
                Button("去系统设置授权") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func subtitle(_ group: AnalyzedGroup) -> String {
        var parts = [
            group.kind == .photo ? "照片" : "截图",
            "\(group.assets.count) 张",
            String(format: "凝聚度 %.3f", group.cohesion),
            "跨度 " + Theme.duration(group.timeSpan),
        ]
        if !group.links.isEmpty {
            parts.append(Theme.links(group.links))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 动作

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
            selection = runner.groups.first?.id
        }
    }
}

// MARK: - 侧边栏行

struct GroupRow: View {
    let group: AnalyzedGroup

    @State private var thumbnail: CGImage?

    private var countLine: String {
        String(format: "%d 张 · 凝聚度 %.3f", group.assets.count, group.cohesion)
    }

    private var detailLine: String {
        var parts = [
            group.kind == .photo ? "照片" : "截图",
            "跨度 " + Theme.duration(group.timeSpan),
        ]
        if !group.links.isEmpty {
            parts.append(Theme.links(group.links))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: Theme.sidebarThumb, height: Theme.sidebarThumb)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(group.id + 1) 组")
                    .font(.system(size: 12, weight: .medium))
                Text(countLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(detailLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .task(id: group.assets.first?.id) {
            guard let id = group.assets.first?.id else { return }
            thumbnail = await ThumbnailCache.shared.image(for: id, target: 128)
        }
    }
}
