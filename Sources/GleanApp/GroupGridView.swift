import GleanCore
import SwiftUI

/// 右侧：选中那一组的照片。
struct GroupDetailView: View {
    let group: AnalyzedGroup
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Theme.cellSide), spacing: 16)],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(Array(group.assets.enumerated()), id: \.element.id) { offset, asset in
                    AssetCell(asset: asset, isKeeper: offset == 0) {
                        onSelect(offset)
                    }
                }
            }
            .padding(20)
        }
        .background(.background)
    }
}

struct AssetCell: View {
    let asset: AnalyzedAsset
    let isKeeper: Bool
    let action: () -> Void

    @State private var image: CGImage?

    var body: some View {
        Button(action: action) {
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
                            isKeeper ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )

                Text(asset.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isKeeper ? .primary : .secondary)

                Text(detail)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .frame(width: Theme.cellSide, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("\(asset.name)\n\(asset.pixelWidth)×\(asset.pixelHeight)\n\(asset.reason)")
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset.id, target: 320)
        }
    }

    private var detail: String {
        String(format: "%.2f · 清晰 %.2f", asset.score, asset.sharpness)
    }
}

// MARK: - 预览

struct PreviewOverlay: View {
    @Binding var state: PreviewState?

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
        return .handled
    }
}
