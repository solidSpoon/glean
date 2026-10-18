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
        HSplitView {
            groupPane
                .frame(minWidth: 330, idealWidth: 440, maxWidth: 780)

            detailPane
                .frame(minWidth: 420, maxWidth: .infinity)
        }
        .navigationTitle(selectedGroup.map { "第 \($0.id + 1) 组" } ?? "glean")
        .navigationSubtitle(selectedGroup.map(subtitle) ?? "")
        .toolbar { toolbar }
        .frame(minWidth: 900, minHeight: 620)
        .overlay {
            if preview != nil {
                PreviewOverlay(state: $preview)
            }
        }
    }

    // MARK: - 左：组卡片网格

    private var groupPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(runner.groups.isEmpty ? "相似组" : "相似组 · \(runner.groups.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 152, maximum: 240), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(runner.groups) { group in
                        GroupCard(group: group, isSelected: group.id == selection) {
                            selection = group.id
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .overlay {
                if runner.groups.isEmpty {
                    if runner.running {
                        ProgressView("分析中…").controlSize(.small)
                    } else {
                        Text(assets.isEmpty ? "先扫描图库" : "还没有结果")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .background(.background)
    }

    // MARK: - 右：选中组的照片

    @ViewBuilder
    private var detailPane: some View {
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
                        : "左侧每一张卡片是一个相似组，点开看这一组里的照片"
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

// MARK: - 组卡片

struct GroupCard: View {
    let group: AnalyzedGroup
    let isSelected: Bool
    let action: () -> Void

    @State private var thumbnails: [String: CGImage] = [:]

    private var stripIDs: [String] {
        Array(group.assets.prefix(3).map(\.id))
    }

    private var countLine: String {
        String(format: "%d 张 · %.3f", group.assets.count, group.cohesion)
    }

    private var detailLine: String {
        var parts = ["跨度 " + Theme.duration(group.timeSpan)]
        if !group.links.isEmpty {
            parts.append(Theme.links(group.links))
        }
        if group.kind == .screenshot {
            parts.append("截图")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                thumbStrip

                VStack(alignment: .leading, spacing: 1) {
                    Text("第 \(group.id + 1) 组")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(countLine)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Text(detailLine)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.07), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("第 \(group.id + 1) 组 · \(group.assets.count) 张 · 凝聚度 \(String(format: "%.3f", group.cohesion))")
        .task(id: stripIDs.joined(separator: ",")) {
            var loaded: [String: CGImage] = [:]
            for id in stripIDs {
                if let image = await ThumbnailCache.shared.image(for: id, target: 220) {
                    loaded[id] = image
                }
            }
            thumbnails = loaded
        }
    }

    private var thumbStrip: some View {
        HStack(spacing: 2) {
            ForEach(stripIDs, id: \.self) { id in
                Color.clear
                    .overlay {
                        if let image = thumbnails[id] {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
