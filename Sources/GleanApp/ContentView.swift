import GleanCore
import Photos
import SwiftUI

/// 分析范围。
enum AnalysisRange: String, CaseIterable, Identifiable {
    case month1, month3, month6, year1, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month1: return "最近 1 个月"
        case .month3: return "最近 3 个月"
        case .month6: return "最近 6 个月"
        case .year1: return "最近 1 年"
        case .all: return "全部"
        }
    }

    private var months: Int? {
        switch self {
        case .month1: return 1
        case .month3: return 3
        case .month6: return 6
        case .year1: return 12
        case .all: return nil
        }
    }

    func includes(_ asset: GleanAsset, now: Date) -> Bool {
        guard let months else { return true }
        guard let date = asset.creationDate else { return false }
        return date >= now.addingTimeInterval(-Double(months) * 30 * 86_400)
    }
}

struct ContentView: View {
    @State private var status: PHAuthorizationStatus = PhotoAccess.current
    @State private var assets: [GleanAsset] = []
    @State private var busy = false
    @State private var scanProgress: (done: Int, total: Int)?
    @State private var range: AnalysisRange = .month3
    @State private var rangeCounts: [AnalysisRange: Int] = [:]
    @State private var selection: Int?
    @State private var preview: PreviewState?
    @StateObject private var runner = AnalysisRunner()

    @FocusState private var gridFocused: Bool

    /// 左栏固定两列，键盘上下跳一行就是 ±2。
    private let columnCount = 2

    private var selectedGroup: AnalyzedGroup? {
        guard let selection else { return nil }
        return runner.groups.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                groupPane
                    .frame(minWidth: 340, idealWidth: 460, maxWidth: 640)

                Divider()

                detailPane
                    .frame(minWidth: 420, maxWidth: .infinity)
            }

            Divider()

            statusBar
        }
        .navigationTitle(selectedGroup.map { "第 \($0.id + 1) 组" } ?? "glean")
        .navigationSubtitle(selectedGroup.map(subtitle) ?? "")
        .toolbar { toolbar }
        .frame(minWidth: 900, minHeight: 600)
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
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 140), spacing: 10),
                        count: columnCount
                    ),
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(runner.groups) { group in
                        GroupCard(group: group, isSelected: group.id == selection) {
                            selection = group.id
                            gridFocused = true
                        }
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
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
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onAppear { gridFocused = true }
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-columnCount) }
        .onKeyPress(.downArrow) { move(columnCount) }
        .onKeyPress(.space) { openSelected() }
        .onKeyPress(.return) { openSelected() }
    }

    /// 键盘移动选中项。左右走一格，上下跳一行。
    private func move(_ delta: Int) -> KeyPress.Result {
        guard !runner.groups.isEmpty else { return .ignored }
        guard let current = selection,
              let index = runner.groups.firstIndex(where: { $0.id == current }) else {
            selection = runner.groups.first?.id
            return .handled
        }
        let next = index + delta
        guard runner.groups.indices.contains(next) else { return .handled }
        selection = runner.groups[next].id
        return .handled
    }

    private func openSelected() -> KeyPress.Result {
        guard let group = selectedGroup else { return .ignored }
        preview = PreviewState(group: group, index: 0)
        return .handled
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
                        : "左侧每张卡片是一个相似组，点开看这一组里的照片"
                )
            )
        }
    }

    // MARK: - 底部状态栏

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let scanProgress {
                ProgressView(value: Double(scanProgress.done), total: Double(max(scanProgress.total, 1)))
                    .frame(width: 150)
                Text("读取相册 \(scanProgress.done)/\(scanProgress.total)")
            } else if runner.running {
                ProgressView(value: runner.progressValue)
                    .frame(width: 150)
                Text("\(runner.phase) \(runner.progressLabel)")
                    .monospacedDigit()
            } else {
                Text(runner.summary.first ?? idleText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Text("资产 \(assets.count) · 相似组 \(runner.groups.count)")
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.bar)
    }

    private var idleText: String {
        if assets.isEmpty { return "先扫描图库，再选分析范围" }
        return "分析范围：\(range.title) · \(rangeCounts[range] ?? 0) 张"
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if status == .notDetermined {
                Button("请求相册权限") {
                    Task { status = await PhotoAccess.request() }
                }
            } else if status == .authorized || status == .limited {
                Picker("范围", selection: $range) {
                    ForEach(AnalysisRange.allCases) { option in
                        Text("\(option.title)（\(rangeCounts[option] ?? 0)）")
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .disabled(busy || runner.running || assets.isEmpty)
                .help("分析哪段时间的照片")

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
                .help("按所选范围查找相似组")
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
        scanProgress = (0, 0)

        Task {
            let loaded = LibraryScanner.loadAssets { done, total in
                Task { @MainActor in
                    scanProgress = (done, total)
                }
            }

            let now = Date()
            var counts: [AnalysisRange: Int] = [:]
            for option in AnalysisRange.allCases {
                counts[option] = loaded.filter { option.includes($0, now: now) }.count
            }

            await MainActor.run {
                assets = loaded
                rangeCounts = counts
                scanProgress = nil
                busy = false
            }
        }
    }

    private func analyze() {
        let now = Date()
        let scope = assets.filter { range.includes($0, now: now) }

        Task {
            await runner.run(assets: scope)
            selection = runner.groups.first?.id
            gridFocused = true
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
        group.assets.prefix(3).map(\.id)
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
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.07),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("第 \(group.id + 1) 组 · \(group.assets.count) 张")
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
