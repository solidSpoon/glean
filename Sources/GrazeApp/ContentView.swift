import GrazeCore
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

    func includes(_ asset: GrazeAsset, now: Date) -> Bool {
        guard let months else { return true }
        guard let date = asset.creationDate else { return false }
        return date >= now.addingTimeInterval(-Double(months) * 30 * 86_400)
    }
}

struct ContentView: View {
    @State private var status: PHAuthorizationStatus = PhotoAccess.current
    @State private var assets: [GrazeAsset] = []
    @State private var busy = false
    @State private var range: AnalysisRange = .month3
    @State private var rangeCounts: [AnalysisRange: Int] = [:]
    @State private var selection: Int?
    @State private var selectedIDs: Set<String> = []
    @State private var focusedID: String?
    @State private var preview: PreviewState?
    @StateObject private var runner = AnalysisRunner()
    @StateObject private var marks = MarkStore()

    /// 键盘导航只在中间一栏生效。左栏纯鼠标点击。
    @FocusState private var photoFocused: Bool

    /// 左栏固定两列。
    private let columnCount = 2

    private var selectedGroup: AnalyzedGroup? {
        guard let selection else { return nil }
        return runner.group(selection)
    }

    private var focusedAsset: AnalyzedAsset? {
        guard let focusedID else { return nil }
        return selectedGroup?.assets.first { $0.id == focusedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                groupPane
                    .frame(minWidth: 320, idealWidth: 420, maxWidth: 600)

                Divider()

                photoPane
                    .frame(minWidth: 340, maxWidth: .infinity)

                Divider()

                infoPane
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
            }

            Divider()

            statusBar
        }
        .navigationTitle(selectedGroup.map { "第 \($0.id + 1) 组" } ?? "graze")
        .navigationSubtitle(selectedGroup.map(subtitle) ?? "")
        .toolbar { toolbar }
        .frame(minWidth: 1060, minHeight: 600)
        .task(id: selection) {
            guard let id = selection else {
                selectedIDs = []
                focusedID = nil
                return
            }
            if let group = runner.group(id) {
                let existing = group.assets.filter { selectedIDs.contains($0.id) }
                if existing.isEmpty, let first = group.assets.first {
                    selectedIDs = [first.id]
                    focusedID = first.id
                } else if focusedID == nil {
                    focusedID = existing.first?.id
                }
            }
            focusPhotoPane()
        }
        .overlay {
            if preview != nil {
                PreviewOverlay(
                    state: $preview,
                    marked: marks.marked,
                    onIndexChange: { id in
                        focusedID = id
                        selectedIDs = [id]
                    },
                    onToggleMark: { id in
                        toggleMark(id)
                    }
                )
            }
        }
        .onChange(of: preview == nil) { _, closed in
            // 空格关掉预览后，焦点回到中间栏，可以继续用方向键
            if closed { photoFocused = true }
        }
    }

    // MARK: - 左：组卡片网格（只用鼠标）

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
                        GroupCard(
                            group: group,
                            isSelected: group.id == selection,
                            markedCount: group.assets.reduce(0) { $0 + (marks.marked.contains($1.id) ? 1 : 0) }
                        ) {
                            selection = group.id
                            selectedIDs = []
                            focusedID = nil
                            focusPhotoPane()
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
    }

    // MARK: - 中：这一组的照片（键盘导航在这里）

    private var photoPane: some View {
        Group {
            if let group = selectedGroup {
                GroupDetailView(
                    group: group,
                    selectedIDs: selectedIDs,
                    marked: marks.marked,
                    onSelect: { id, additive in
                        select(id, additive: additive)
                    },
                    onOpen: { index in
                        let asset = group.assets[index]
                        selectedIDs = [asset.id]
                        focusedID = asset.id
                        preview = PreviewState(group: group, index: index)
                    },
                    onToggleMark: { id in
                        toggleMark(id)
                    }
                )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($photoFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { movePhoto(-1) }
        .onKeyPress(.rightArrow) { movePhoto(1) }
        .onKeyPress(.space) { openFocusedPhoto() }
        .onKeyPress(.return) { toggleSelectionMark() }
    }

    private func select(_ id: String, additive: Bool) {
        if additive {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        } else {
            selectedIDs = [id]
        }
        focusedID = id
        photoFocused = true
    }

    private func movePhoto(_ delta: Int) -> KeyPress.Result {
        guard let group = selectedGroup, !group.assets.isEmpty else { return .ignored }
        guard let current = focusedID,
              let index = group.assets.firstIndex(where: { $0.id == current }) else {
            let first = group.assets.first
            selectedIDs = first.map { [$0.id] } ?? []
            focusedID = first?.id
            return .handled
        }
        let next = index + delta
        guard group.assets.indices.contains(next) else { return .handled }
        let asset = group.assets[next]
        focusedID = asset.id
        selectedIDs = [asset.id]
        return .handled
    }

    private func openFocusedPhoto() -> KeyPress.Result {
        guard let group = selectedGroup, let id = focusedID,
              let index = group.assets.firstIndex(where: { $0.id == id }) else { return .ignored }
        preview = PreviewState(group: group, index: index)
        return .handled
    }

    /// 把键盘焦点交给中间栏。
    ///
    /// 不能同步赋值：点击本身的焦点处理在这之后跑，会把刚设的值覆盖掉，
    /// 表现就是"点一下没反应、要再点一次中间才生效"。放到下一轮 runloop 才稳。
    private func focusPhotoPane() {
        DispatchQueue.main.async {
            photoFocused = true
        }
    }

    // MARK: - 右：照片信息

    private var infoPane: some View {
        Group {
            if let asset = focusedAsset, let group = selectedGroup {
                AssetInfoView(
                    asset: asset,
                    group: group,
                    isMarked: marks.marked.contains(asset.id)
                )
            } else {
                ContentUnavailableView(
                    "未选择照片",
                    systemImage: "info.circle",
                    description: Text("在中间选一张照片，这里显示它的详细信息")
                )
            }
        }
    }

    // MARK: - 底部状态栏

    private var statusBar: some View {
        HStack(spacing: 10) {
            if runner.scanning {
                ProgressView(value: Double(runner.scanDone), total: Double(max(runner.scanTotal, 1)))
                    .frame(width: 150)
                Text(runner.scanTotal > 0 ? "读取相册 \(runner.scanDone)/\(runner.scanTotal)" : "正在读取相册…")
                    .monospacedDigit()
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

            if !marks.marked.isEmpty {
                Text("待删除 \(marks.marked.count)")
                    .foregroundStyle(.red)
                    .monospacedDigit()
                Divider().frame(height: 12)
            }

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
        if !selectedIDs.isEmpty {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    toggleSelectionMark()
                } label: {
                    Label(
                        allSelectedMarked ? "取消待删除" : "标记待删除",
                        systemImage: allSelectedMarked ? "trash.slash" : "trash"
                    )
                }
                .help(allSelectedMarked
                    ? "把选中的 \(selectedIDs.count) 张移出「\(DeletionAlbum.title)」"
                    : "把选中的 \(selectedIDs.count) 张加进「\(DeletionAlbum.title)」")
            }
        }

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

    private var allSelectedMarked: Bool {
        !selectedIDs.isEmpty && selectedIDs.isSubset(of: marks.marked)
    }

    /// 回车：选中项批量切换待删除标记（全已标记 → 取消，否则 → 标记）。
    private func toggleSelectionMark() -> KeyPress.Result {
        guard !selectedIDs.isEmpty else { return .ignored }
        markSelection(!allSelectedMarked)
        return .handled
    }

    private func markSelection(_ value: Bool) {
        let ids = Array(selectedIDs)
        Task { await marks.setMarked(ids, value) }
    }

    private func toggleMark(_ id: String) {
        Task { await marks.toggle(id) }
    }

    private func scan() {
        busy = true

        Task {
            let loaded = await runner.scanLibrary()
            await marks.refresh()

            let now = Date()
            var counts: [AnalysisRange: Int] = [:]
            for option in AnalysisRange.allCases {
                counts[option] = loaded.filter { option.includes($0, now: now) }.count
            }

            assets = loaded
            rangeCounts = counts
            busy = false
        }
    }

    private func analyze() {
        let now = Date()
        let scope = assets.filter { range.includes($0, now: now) }

        Task {
            await runner.run(assets: scope)
            selection = runner.groups.first?.id
            selectedIDs = []
            focusedID = nil
            photoFocused = true
        }
    }
}

// MARK: - 组卡片

struct GroupCard: View {
    let group: AnalyzedGroup
    let isSelected: Bool
    /// 本组里已标记待删除的张数。为 0 时不显示任何标记。
    let markedCount: Int
    let action: () -> Void

    @State private var thumbnails: [String: CGImage] = [:]

    private var stripIDs: [String] {
        group.assets.prefix(3).map(\.id)
    }

    private var countLine: String {
        String(format: "%d 张 · %.3f", group.assets.count, group.cohesion)
    }

    private var detailLine: String {
        // 列表按“组内最新时间”倒序，所以卡片上把时间摆出来，否则排序依据看不见
        var parts = [Theme.shortDate(group.latestDate)]
        if !group.links.isEmpty {
            parts.append(Theme.links(group.links))
        }
        if group.kind == .screenshot {
            parts.append("截图")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbStrip

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("第 \(group.id + 1) 组")
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 2)

                    if markedCount > 0 {
                        markedBadge
                    }
                }

                Text(countLine)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .monospacedDigit()

                Text(detailLine)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(7)
        // 选中用底色表示，不描边——卡片平时没有框，选中时只是垫一层
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.20) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { action() }
        .help("第 \(group.id + 1) 组 · \(group.assets.count) 张 · 凝聚度 \(String(format: "%.3f", group.cohesion)) · 跨度 \(Theme.duration(group.timeSpan))"
              + (markedCount > 0 ? " · 已标记待删 \(markedCount) 张" : ""))
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

    /// 已标过待删的组在列表里要能一眼看出来：标记是存在 Photos 里的，
    /// 重开 App 也会保留，所以列表必须能反映“这组处理过没有”。
    private var markedBadge: some View {
        let all = markedCount == group.assets.count
        return Text(all ? "整组待删" : "待删 \(markedCount)")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(all ? Color.white : Color.red)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                all ? Color.red.opacity(0.85) : Color.red.opacity(0.15),
                in: Capsule()
            )
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
