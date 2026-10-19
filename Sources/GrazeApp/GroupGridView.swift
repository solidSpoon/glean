import AppKit
import GrazeCore
import SwiftUI

/// 中间一栏：选中那一组的照片。单击选中，⌘ 点击多选，双击预览。
struct GroupDetailView: View {
    let group: AnalyzedGroup
    let selectedIDs: Set<String>
    let marked: Set<String>
    let onSelect: (String, Bool) -> Void
    let onOpen: (Int) -> Void
    let onToggleMark: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Theme.cellSide, maximum: 260), spacing: 16)],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(Array(group.assets.enumerated()), id: \.element.id) { offset, asset in
                    AssetCell(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.id),
                        isMarked: marked.contains(asset.id)
                    ) { additive in
                        onSelect(asset.id, additive)
                    } onOpen: {
                        onOpen(offset)
                    } onToggleMark: {
                        onToggleMark(asset.id)
                    }
                }
            }
            .padding(18)
        }
        .background(.background)
    }
}

struct AssetCell: View {
    let asset: AnalyzedAsset
    let isSelected: Bool
    let isMarked: Bool
    let onSelect: (Bool) -> Void
    let onOpen: () -> Void
    let onToggleMark: () -> Void

    @State private var image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)

                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(2)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: Theme.cellSide, height: Theme.cellSide)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: isSelected ? 3 : 0
                    )
            )
            .overlay(alignment: .bottomTrailing) {
                if isMarked {
                    Text("待删")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .padding(5)
                }
            }
            .opacity(isMarked ? 0.72 : 1)

            Text(asset.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(width: Theme.cellSide, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture {
            // Shift / ⌘ 都当多选
            let flags = NSEvent.modifierFlags
            let additive = flags.contains(.command) || flags.contains(.shift)
            onSelect(additive)
        }
        .contextMenu {
            if isMarked {
                Button("取消待删除标记") { onToggleMark() }
            } else {
                Button("标记为待删除") { onToggleMark() }
            }
        }
        .help("\(asset.name)\n单击选中，⌘ 点击多选，双击看大图")
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset.id, target: 320)
        }
    }
}

// MARK: - 右栏：照片信息

struct AssetInfoView: View {
    let asset: AnalyzedAsset
    let group: AnalyzedGroup
    let isMarked: Bool

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(asset.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.bottom, 8)

                if isMarked {
                    Text("已标记待删除")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.bottom, 6)
                }

                section("文件")
                row("类型", asset.fileExtension)
                row("尺寸", "\(asset.pixelWidth) × \(asset.pixelHeight)")
                row("像素", pixelText)
                row("拍摄", format(asset.creationDate))
                if let modified = asset.modificationDate, modified != asset.creationDate {
                    row("修改", format(modified))
                }

                section("属性")
                let labels = asset.attributeLabels
                if labels.isEmpty {
                    row("类型", "普通照片")
                } else {
                    ForEach(labels, id: \.self) { label in
                        row("·", label)
                    }
                }

                if let latitude = asset.latitude, let longitude = asset.longitude {
                    section("位置")
                    row("坐标", String(format: "%.5f, %.5f", latitude, longitude))
                }

                section("相似度")
                if let low = asset.similarityMin, let high = asset.similarityMax {
                    row("与组内其他", String(format: "%.3f ~ %.3f", low, high))
                } else {
                    row("与组内其他", "—")
                }

                section("所属组")
                row("组号", "第 \(group.id + 1) 组")
                row("类型", group.kind == .photo ? "照片" : "截图")
                row("张数", "\(group.assets.count)")
                row("凝聚度", String(format: "%.3f", group.cohesion))
                row("跨度", Theme.duration(group.timeSpan))
                if !group.links.isEmpty {
                    row("连接", Theme.links(group.links))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }

    private var pixelText: String {
        let count = asset.pixelCount
        if count >= 1_000_000 {
            return String(format: "%.1f MP", Double(count) / 1_000_000)
        }
        return "\(count / 1000) K"
    }

    private func format(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Self.dateFormatter.string(from: date)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 全屏预览（底部带一行缩略图，方便连着标）

struct PreviewOverlay: View {
    @Binding var state: PreviewState?
    let marked: Set<String>
    var onIndexChange: ((String) -> Void)?
    var onToggleMark: ((String) -> Void)?

    @State private var image: CGImage?
    @State private var phase: Phase = .loading
    /// 每次取图用一个新 token。左→右换图时上一次下载的进度回调还会继续来，
    /// 不带 token 就会把进度条铺到新照片上。
    @State private var token = UUID()
    @FocusState private var focused: Bool

    /// 大图有三种状态，不能只留一个 `image == nil`：
    /// 「正在从 iCloud 下载」要能看到进度，「下载失败」要能重试。
    /// 只写 `ProgressView()` 的话，取不到图的照片会永远转圈，看起来像死机。
    private enum Phase: Equatable {
        case loading
        case downloading(Double)
        case failed(String)
    }

    private var asset: AnalyzedAsset? { state?.asset }
    private var isCurrentMarked: Bool {
        guard let asset else { return false }
        return marked.contains(asset.id)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            if let state, let asset {
                VStack(spacing: 10) {
                    Spacer(minLength: 0)

                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(.horizontal, 24)
                    } else {
                        placeholder(for: asset)
                    }

                    Spacer(minLength: 0)

                    controls(for: asset, state: state)
                    strip(state: state)
                }
                .padding(.bottom, 14)
            }
        }
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .task(id: asset?.id) {
            guard let asset else { return }
            await loadImage(asset)
        }
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(.return) {
            // 预览里回车 = 切换当前这张的待删除标记，和中间栏保持一致
            if let asset { onToggleMark?(asset.id) }
            return .handled
        }
        .onKeyPress(.space) {
            // 空格只负责开关预览（第一次打开、第二次退出），标记走回车或按钮
            state = nil
            return .handled
        }
        .onKeyPress(.escape) {
            state = nil
            return .handled
        }
    }

    @ViewBuilder
    private func placeholder(for asset: AnalyzedAsset) -> some View {
        VStack(spacing: 14) {
            switch phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)

            case .downloading(let value):
                ProgressView(value: value) {
                    Text("正在从 iCloud 下载… \(Int(value * 100))%")
                        .monospacedDigit()
                }
                .frame(width: 260)

            case .failed(let reason):
                Image(systemName: "icloud.slash")
                    .font(.system(size: 32))
                Text(reason)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Button("重试") {
                    Task { await loadImage(asset) }
                }
            }
        }
        .foregroundStyle(.white.opacity(0.86))
    }

    /// 大图是唯一“用户明确要看这一张”的地方，所以这里允许联网：
    /// 「优化 Mac 储存空间」时原图只在 iCloud，不允许联网就永远只有本地那档小图。
    private func loadImage(_ asset: AnalyzedAsset) async {
        let request = UUID()
        token = request
        image = nil
        phase = .loading

        let outcome = await Thumbnailer.load(
            for: asset.id,
            targetSize: CGSize(width: 1600, height: 1600),
            allowNetwork: true,
            onProgress: { value in
                // 回调已经被 Thumbnailer 转到主线程了
                guard token == request, value < 1 else { return }
                phase = .downloading(value)
            }
        )

        guard token == request else { return }

        if let loaded = outcome.image {
            image = loaded
        } else if outcome.isInCloud {
            phase = .failed("这张只在 iCloud，本地没有下载，刚才拉取也没成功。\n检查网络后点「重试」；也可以先在「照片」App 里打开它，下载一次就好。")
        } else {
            phase = .failed("这张照片取不到图（可能已损坏，或正在 Photos 里编辑）。")
        }
    }

    private func controls(for asset: AnalyzedAsset, state: PreviewState) -> some View {
        HStack(spacing: 12) {
            Button {
                _ = step(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(state.index <= 0)

            Text("\(asset.name)　\(state.index + 1)/\(state.group.assets.count)")
                .font(.system(size: 11))
                .monospacedDigit()

            Button {
                _ = step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(state.index >= state.group.assets.count - 1)

            Button {
                onToggleMark?(asset.id)
                refocus()
            } label: {
                Label(
                    isCurrentMarked ? "取消待删除" : "标记待删除",
                    systemImage: isCurrentMarked ? "trash.slash" : "trash"
                )
            }
            .tint(isCurrentMarked ? .red : nil)

            Button("关闭") { self.state = nil }
                .keyboardShortcut(.cancelAction)
        }
        .controlSize(.large)
    }

    private func strip(state: PreviewState) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(state.group.assets.enumerated()), id: \.element.id) { index, item in
                        StripThumbnail(
                            asset: item,
                            isCurrent: index == state.index,
                            isMarked: marked.contains(item.id)
                        )
                        .id(index)
                        .onTapGesture {
                            self.state = PreviewState(group: state.group, index: index)
                            onIndexChange?(item.id)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
            .frame(height: 62)
            .onAppear {
                proxy.scrollTo(state.index, anchor: .center)
            }
            .onChange(of: state.index) { _, newValue in
                withAnimation(.smooth(duration: 0.18)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        guard let current = state else { return .ignored }
        let next = current.index + delta
        guard current.group.assets.indices.contains(next) else { return .handled }
        state = PreviewState(group: current.group, index: next)
        if let asset = current.group.assets[safe: next] {
            onIndexChange?(asset.id)
        }
        return .handled
    }

    /// 点过按钮后焦点会跑到按钮上，方向键/回车就不再归本视图处理。
    /// 每次交互后把焦点拉回来，保证键盘全程可用。
    private func refocus() {
        DispatchQueue.main.async {
            focused = true
        }
    }
}

private struct StripThumbnail: View {
    let asset: AnalyzedAsset
    let isCurrent: Bool
    let isMarked: Bool

    @State private var image: CGImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.4)
                .overlay {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isCurrent ? Color.white : Color.white.opacity(0.15), lineWidth: isCurrent ? 2 : 1)
                )
                .opacity(isMarked ? 0.45 : 1)

            if isMarked {
                Image(systemName: "trash.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(Color.red, in: Circle())
                    .offset(x: 3, y: -3)
            }
        }
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset.id, target: 120)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
