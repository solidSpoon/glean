import GleanCore
import SwiftUI

// MARK: - 组区块

struct GroupSectionView: View {
    let index: Int
    let group: AnalyzedGroup
    @Binding var preview: PreviewItem?

    private var subtitle: String {
        var parts = [
            "\(group.assets.count) 张",
            String(format: "凝聚度 %.3f", group.cohesion),
            Self.duration(group.timeSpan),
        ]
        if !group.links.isEmpty {
            parts.append(Self.links(group.links))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("第 \(index) 组")
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 116), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(Array(group.assets.enumerated()), id: \.element.id) { offset, asset in
                    AssetCell(asset: asset, isKeeper: offset == 0)
                        .onTapGesture {
                            preview = PreviewItem(id: asset.id, name: asset.name)
                        }
                }
            }
        }
        .padding(.vertical, 6)
    }

    static func duration(_ interval: TimeInterval) -> String {
        if interval < 60 { return String(format: "跨度 %.0fs", interval) }
        if interval < 3600 { return String(format: "跨度 %.0fmin", interval / 60) }
        return String(format: "跨度 %.1fh", interval / 3600)
    }

    static func links(_ links: Set<Grouping.Link>) -> String {
        var parts: [String] = []
        if links.contains(.burst) { parts.append("连拍") }
        if links.contains(.visual) { parts.append("视觉") }
        if links.contains(.crossSession) { parts.append("跨会话") }
        return parts.joined(separator: "+")
    }
}

// MARK: - 单元格

struct AssetCell: View {
    let asset: AnalyzedAsset
    let isKeeper: Bool

    @State private var image: CGImage?

    private let side: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(.quaternary.opacity(0.35))

                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(2)
                } else {
                    ProgressView().controlSize(.small)
                }

                if isKeeper {
                    VStack {
                        HStack {
                            Text("留")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isKeeper ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            Text(asset.name)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isKeeper ? .primary : .secondary)

            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.tertiary)
        }
        .frame(width: side, alignment: .leading)
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset.id, target: 256)
        }
    }

    /// 清晰度用两位小数显示。之前用 %.0f，真实量级 0.2–3 被印成了 "0"/"1"，看起来像坏了。
    private var detail: String {
        String(format: "%.2f · 清晰 %.2f", asset.score, asset.sharpness)
    }
}

// MARK: - 放大预览

struct PreviewSheet: View {
    let item: PreviewItem

    @State private var image: CGImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Color.black.opacity(0.92)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    ProgressView()
                }
            }
            .frame(minWidth: 640, minHeight: 480)

            HStack {
                Text(item.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .task(id: item.id) {
            image = await ThumbnailCache.shared.image(for: item.id, target: 1400)
        }
    }
}
