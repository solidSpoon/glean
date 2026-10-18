import GleanCore
import SwiftUI

/// 中间一栏：选中那一组的照片。单击选中，双击预览。
struct GroupDetailView: View {
    let group: AnalyzedGroup
    let selectedID: String?
    let onSelect: (String) -> Void
    let onOpen: (Int) -> Void

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
                        isKeeper: offset == 0 && group.isScored,
                        isSelected: asset.id == selectedID
                    ) {
                        onSelect(asset.id)
                    } onOpen: {
                        onOpen(offset)
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
    let isKeeper: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

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

                if isKeeper {
                    Text("留")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .padding(5)
                }
            }
            .frame(width: Theme.cellSide, height: Theme.cellSide)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected ? Color.accentColor : (isKeeper ? Color.accentColor.opacity(0.55) : Color.clear),
                        lineWidth: isSelected ? 3 : (isKeeper ? 2 : 0)
                    )
            )

            Text(asset.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(width: Theme.cellSide, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .help("\(asset.name)\n双击或按空格看大图")
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset.id, target: 320)
        }
    }
}

// MARK: - 右栏：照片信息

struct AssetInfoView: View {
    let asset: AnalyzedAsset
    let group: AnalyzedGroup

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

                if group.isScored {
                    Text(asset.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(asset.score >= 0.999 ? Color.accentColor : .secondary)
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

                section("评分")
                if group.isScored {
                    row("组内得分", String(format: "%.2f", asset.score))
                    row("与保留张", asset.similarityToKeeper.map { String(format: "%.3f", $0) } ?? "—")
                    row("清晰度", String(format: "%.3f", asset.sharpness))
                    row("人脸质量", asset.faceQuality.map { String(format: "%.2f", $0) } ?? "—")
                } else {
                    Text("正在计算…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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

// MARK: - 全屏预览

struct PreviewOverlay: View {
    @Binding var state: PreviewState?
    /// 预览里翻到别张时，同步给外面的选中项。
    var onIndexChange: ((String) -> Void)?

    @State private var image: CGImage?
    @FocusState private var focused: Bool

    private var asset: AnalyzedAsset? { state?.asset }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            if let asset {
                VStack(spacing: 12) {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(24)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                    }

                    HStack(spacing: 14) {
                        Button {
                            _ = step(-1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled((state?.index ?? 0) <= 0)

                        Text("\(asset.name)　\((state?.index ?? 0) + 1)/\(state?.group.assets.count ?? 0)")
                            .font(.system(size: 11))
                            .monospacedDigit()

                        Button {
                            _ = step(1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled((state?.index ?? 0) >= (state?.group.assets.count ?? 1) - 1)

                        Button("关闭") { state = nil }
                            .keyboardShortcut(.cancelAction)
                    }
                    .controlSize(.large)
                    .padding(.bottom, 20)
                }
            }
        }
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .task(id: asset?.id) {
            guard let asset else { return }
            image = nil
            image = await ThumbnailCache.shared.image(for: asset.id, target: 1600)
        }
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(.space) {
            state = nil
            return .handled
        }
        .onKeyPress(.escape) {
            state = nil
            return .handled
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
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
