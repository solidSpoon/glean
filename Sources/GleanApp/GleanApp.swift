import GleanCore
import Photos
import SwiftUI

@main
struct GleanApp: App {
    var body: some Scene {
        WindowGroup("glean") {
            ContentView()
                .frame(minWidth: 720, minHeight: 460)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @State private var status: PHAuthorizationStatus = PhotoAccess.current
    @State private var assets: [GleanAsset] = []
    @State private var log: [String] = []
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            summary
            Spacer(minLength: 0)
            console
        }
        .padding(20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("glean")
                .font(.system(size: 28, weight: .semibold, design: .serif))
            Text("拾穗：从图库里把值得留下的挑出来。")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if status == .notDetermined {
                    Button("请求相册访问权限") {
                        Task {
                            status = await PhotoAccess.request()
                            append("授权结果: \(describe(status))")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                } else if status == .authorized || status == .limited {
                    Button("扫描图库") { scan() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy)

                    Button("试算 30 张特征") { probe() }
                        .disabled(busy || assets.isEmpty)
                } else {
                    Text("需要在系统设置 → 隐私与安全性 → 照片 里允许访问。")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if busy { ProgressView().controlSize(.small) }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("授权状态：\(describe(status))")
            Text("资产数量：\(assets.count)")
            if let burstCount = Optional(assets.filter { $0.burstID != nil }.count), burstCount > 0 {
                Text("其中连拍：\(burstCount)")
            }
            let shots = assets.filter(\.isScreenshot).count
            if shots > 0 { Text("其中截图：\(shots)") }
        }
        .font(.callout)
        .monospacedDigit()
    }

    private var console: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: 160)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func scan() {
        busy = true
        Task {
            let started = Date()
            let loaded = LibraryScanner.loadAssets()
            await MainActor.run {
                assets = loaded
                append("扫描到 \(loaded.count) 张图片，耗时 \(ms(since: started))")
                busy = false
            }
        }
    }

    /// 只为验证整条链路（PhotoKit 取图 → Vision 出向量）能跑通，并量一下真实速度。
    /// 后续这层会被换成「全量 + 增量缓存」的批处理。
    private func probe() {
        busy = true
        Task {
            let sample = Array(assets.prefix(30))
            let started = Date()
            var ok = 0
            var dims = 0
            for asset in sample {
                guard let image = await Thumbnailer.image(for: asset.id) else { continue }
                if let vector = try? FeaturePrintService.vector(for: image) {
                    ok += 1
                    dims = vector.count
                }
            }
            let perItem = Date().timeIntervalSince(started) / Double(max(ok, 1))
            await MainActor.run {
                append("特征提取 \(ok)/\(sample.count) 成功，维度 \(dims)")
                append(String(format: "单张耗时 %.1f ms → 约 %.0f 张/秒", perItem * 1000, 1 / perItem))
                busy = false
            }
        }
    }

    // MARK: - Helpers

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

    private func ms(since start: Date) -> String {
        String(format: "%.0f ms", Date().timeIntervalSince(start) * 1000)
    }

    private func append(_ line: String) {
        log.append(line)
    }
}
