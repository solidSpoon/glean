import GleanCore
import SwiftUI

// MARK: - 组卡片

struct GroupCardView: View {
    let index: Int
    let group: AnalyzedGroup
    let onSelect: (Int) -> Void

    private var subtitle: String {
        var parts = [
            "\(group.assets.count) 张",
            String(format: "凝聚 %.3f", group.cohesion),
            "跨度 " + Theme.duration(group.timeSpan),
        ]
        if !group.links.isEmpty {
            parts.append(Theme.links(group.links))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text("第 \(index) 组")
                    .font(.system(size: 13, weight: .semibold))

                GlassTag(
                    text: group.kind == .photo ? "照片" : "截图",
                    systemImage: group.kind == .photo ? "photo" : "iphone",
                    tint: group.kind == .screenshot ? Color.cyan.opacity(0.30) : nil
                )

                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Theme.cellSide), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(Array(group.assets.enumerated()), id: \.element.id) { offset, asset in
                    AssetCell(asset: asset, isKeeper: offset == 0) {
                        onSelect(offset)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - 单元格

struct AssetCell: View {
    let asset: AnalyzedAsset
    let isKeeper: Bool
    let action: () -> Void

    @State private var image: CGImage?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.06))

                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(3)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if isKeeper {
                        Text("留")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .padding(5)
                    }
                }
                .frame(width: Theme.cellSide, height: Theme.cellSide)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isKeeper ? Color.accentColor : Color.white.opacity(0.10),
                            lineWidth: isKeeper ? 2.5 : 1
                        )
                )
                .shadow(color: isKeeper ? Color.accentColor.opacity(0.35) : .clear, radius: 9)

                Text(asset.name)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isKeeper ? .primary : .secondary)

                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .frame(width: Theme.cellSide, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("\(asset.name)\n\(asset.pixelWidth)×\(asset.pixelHeight)\n\(asset.reason)")
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset.id, target: 256)
        }
    }

    /// 清晰度保留两位小数。原来用 %.0f，真实量级 0.2–3 被印成 "0"/"1"，看起来像坏了。
    private var detail: String {
        String(format: "%.2f · 清晰 %.2f", asset.score, asset.sharpness)
    }
}

// MARK: - 全屏预览

struct PreviewOverlay: View {
    @Binding var state: PreviewState?

    @State private var image: CGImage?
    @FocusState private var focused: Bool

    private var asset: AnalyzedAsset? { state?.asset }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture { state = nil }

            if let asset {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(26)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                    }

                    Spacer(minLength: 0)
                    controls(for: asset)
                        .padding(.bottom, 18)
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
        .onKeyPress(.escape) {
            state = nil
            return .handled
        }
    }

    private func controls(for asset: AnalyzedAsset) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    _ = step(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.glass)
                .disabled((state?.index ?? 0) <= 0)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(asset.name)　\((state?.index ?? 0) + 1)/\(state?.group.assets.count ?? 0)")
                        .font(.system(size: 11, design: .monospaced))
                    Text("\(asset.pixelWidth)×\(asset.pixelHeight) · \(asset.reason)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)

                Button {
                    _ = step(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.glass)
                .disabled((state?.index ?? 0) >= (state?.group.assets.count ?? 1) - 1)

                Button("关闭") { state = nil }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        guard let current = state, let asset = current.asset else { return .ignored }
        _ = asset
        let next = current.index + delta
        guard current.group.assets.indices.contains(next) else { return .handled }
        state = PreviewState(group: current.group, index: next)
        return .handled
    }
}
