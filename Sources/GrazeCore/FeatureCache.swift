import Foundation
import Vision

/// 特征向量落盘缓存。
///
/// FeaturePrint 是整条管线里唯一真正贵的一步：全库 7624 张约 42 秒，占一次分析
/// 的 95%（分组只要 0.5 秒）。同一张照片只要没被改过，Vision 给出的特征就不会变，
/// 所以这里按「资产 id + 修改时间 + 像素尺寸」把结果记下来，第二次分析直接读盘，
/// 同一份图库反复换范围分析也不用再算一遍。
///
/// 两个细节值得说明：
///   · **Vision 版本要参与校验**。`VNGenerateImageFeaturePrintRequest` 的 revision
///     变了，向量空间也就换了——旧向量和新向量算余弦是纯噪声。所以文件头里存
///     revision，对不上就整份作废，不能只比 id。
///   · **浮点存 Float16**。存进来的是单位向量，Float16 的相对误差约 5e-4，
///     传到余弦上只有 1e-4，远小于阈值之间的间距（0.65 / 0.70 / 0.78 / 0.88），
///     但体积省一半：7624 张 768 维从 23MB 降到 12MB。
public final class FeatureCache: @unchecked Sendable {
    public static let shared = FeatureCache()

    /// 磁盘格式版本。改了布局或指纹规则就加一，旧的缓存文件自动失效。
    private static let formatVersion: UInt32 = 1
    private static let magic: [UInt8] = Array("GRAZEFP1".utf8)

    private struct Entry {
        let fingerprint: String
        let vector: [Float]
    }

    private let fileURL: URL
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var loaded = false
    private var storedSinceSave = 0

    /// 攒够这么多条就落一次盘。太少会让写盘频率跟着分块走，太多则一次崩溃丢太多。
    private let saveBatch = 1024

    public var filePath: String { fileURL.path }

    private convenience init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        self.init(directory: caches.appendingPathComponent("graze", isDirectory: true))
    }

    /// 指定目录建一份独立缓存。测试用它，避免踩真实缓存文件。
    init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("featureprints.v1.bin")
    }

    // MARK: - 查询

    /// 把资产分成「缓存里已有」和「必须重算」两堆。
    public func partition(_ assets: [GrazeAsset]) -> (cached: [String: [Float]], pending: [GrazeAsset]) {
        lock.lock()
        loadIfNeeded()
        var cached: [String: [Float]] = [:]
        var pending: [GrazeAsset] = []
        cached.reserveCapacity(assets.count)
        pending.reserveCapacity(assets.count)
        for asset in assets {
            if let entry = entries[asset.id], entry.fingerprint == Self.fingerprint(asset) {
                cached[asset.id] = entry.vector
            } else {
                pending.append(asset)
            }
        }
        lock.unlock()
        return (cached, pending)
    }

    public var count: Int {
        lock.lock()
        loadIfNeeded()
        let total = entries.count
        lock.unlock()
        return total
    }

    // MARK: - 写入

    /// 计算完一批就记进来。攒够 `saveBatch` 条自动落盘，崩溃后不会白算。
    public func store(_ prints: [String: [Float]], for assets: [GrazeAsset]) {
        guard !prints.isEmpty else { return }

        lock.lock()
        loadIfNeeded()
        for asset in assets {
            guard let vector = prints[asset.id], !vector.isEmpty else { continue }
            entries[asset.id] = Entry(fingerprint: Self.fingerprint(asset), vector: vector)
        }
        storedSinceSave += prints.count
        let shouldSave = storedSinceSave >= saveBatch
        lock.unlock()

        if shouldSave { save() }
    }

    /// 丢掉已经被删掉的照片，别让缓存跟着图库无限长大。扫完图库后调用一次。
    public func retain(ids: Set<String>) {
        lock.lock()
        loadIfNeeded()
        let before = entries.count
        entries = entries.filter { ids.contains($0.key) }
        let removed = before - entries.count
        lock.unlock()

        guard removed > 0 else { return }
        GrazeLog.shared.info("featurecache.prune", ["removed": removed, "kept": count])
        save()
    }

    public func removeAll() {
        lock.lock()
        entries = [:]
        loaded = true
        storedSinceSave = 0
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 丢掉内存里的那份，下次查询时重新读盘。测试用。
    public func reload() {
        lock.lock()
        entries = [:]
        loaded = false
        storedSinceSave = 0
        lock.unlock()
    }

    public func save() {
        lock.lock()
        loadIfNeeded()
        let snapshot = entries
        storedSinceSave = 0
        lock.unlock()
        persist(snapshot)
    }

    // MARK: - 指纹

    /// 指纹只回答一个问题：这张照片的「内容」有没有可能变过。
    /// 修改时间覆盖编辑，像素尺寸覆盖替换成不同分辨率的版本；创建时间一起带上，
    /// 万一 Photos 把 localIdentifier 复用到别的照片上也能识别出来。
    private static func fingerprint(_ asset: GrazeAsset) -> String {
        let modified = asset.modificationDate.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        let created = asset.creationDate.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        return "\(modified)|\(created)|\(asset.pixelWidth)x\(asset.pixelHeight)"
    }

    // MARK: - 磁盘格式
    //
    //   "GRAZEFP1"                        8 字节 magic
    //   UInt32 formatVersion
    //   UInt32 visionRevision
    //   UInt32 count
    //   条目 × count：
    //     UInt16 idLength,  id utf8
    //     UInt16 fpLength,  指纹 utf8
    //     UInt16 维度,      Float16 × 维度（bitPattern）
    //
    // 全部小端、无对齐填充。用扁平二进制而不是 JSON/Codable：几十万条也要秒读。

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        guard let data = try? Data(contentsOf: fileURL) else { return }

        var reader = ByteReader(bytes: Array(data))
        guard let header = reader.bytes(8), header == Self.magic,
              reader.uint32() == Self.formatVersion,
              reader.uint32() == UInt32(VNGenerateImageFeaturePrintRequest.currentRevision),
              let count = reader.uint32() else {
            GrazeLog.shared.info("featurecache.discard", ["reason": "header", "path": fileURL.path])
            return
        }

        var parsed: [String: Entry] = [:]
        parsed.reserveCapacity(Int(count))

        for _ in 0..<count {
            guard let idLength = reader.uint16(),
                  let id = reader.string(length: Int(idLength)),
                  let fpLength = reader.uint16(),
                  let fingerprint = reader.string(length: Int(fpLength)),
                  let dimensions = reader.uint16() else {
                break
            }

            var vector = [Float]()
            vector.reserveCapacity(Int(dimensions))
            var complete = true
            for _ in 0..<dimensions {
                guard let bits = reader.uint16() else {
                    complete = false
                    break
                }
                vector.append(Float(Float16(bitPattern: bits)))
            }
            if !complete { break }
            parsed[id] = Entry(fingerprint: fingerprint, vector: vector)
        }

        entries = parsed
        GrazeLog.shared.info("featurecache.load", [
            "entries": parsed.count,
            "expected": count,
            "path": fileURL.path,
        ])
    }

    private func persist(_ snapshot: [String: Entry]) {
        var data = Data()
        data.reserveCapacity(16 + snapshot.count * 1_600)
        data.append(contentsOf: Self.magic)
        data.appendLittleEndian(Self.formatVersion)
        data.appendLittleEndian(UInt32(VNGenerateImageFeaturePrintRequest.currentRevision))
        data.appendLittleEndian(UInt32(snapshot.count))

        for (id, entry) in snapshot {
            let idBytes = Array(id.utf8)
            let fingerprintBytes = Array(entry.fingerprint.utf8)
            data.appendLittleEndian(UInt16(truncatingIfNeeded: idBytes.count))
            data.append(contentsOf: idBytes)
            data.appendLittleEndian(UInt16(truncatingIfNeeded: fingerprintBytes.count))
            data.append(contentsOf: fingerprintBytes)
            data.appendLittleEndian(UInt16(truncatingIfNeeded: entry.vector.count))
            for value in entry.vector {
                data.appendLittleEndian(Float16(value).bitPattern)
            }
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            GrazeLog.shared.info("featurecache.save", [
                "entries": snapshot.count,
                "bytes": data.count,
                "path": fileURL.path,
            ])
        } catch {
            GrazeLog.shared.debug("featurecache.save.failed", [
                "error": String(describing: error),
                "path": fileURL.path,
            ])
        }
    }
}

// MARK: - 小工具

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }
}

/// 顺序读取扁平二进制。越界一律返回 nil，让调用方按「文件坏了」处理。
private struct ByteReader {
    let bytes: [UInt8]
    private var offset = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func uint16() -> UInt16? {
        guard offset + 2 <= bytes.count else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    mutating func uint32() -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        defer { offset += 4 }
        var value: UInt32 = 0
        for index in (0..<4).reversed() {
            value = value << 8 | UInt32(bytes[offset + index])
        }
        return value
    }

    mutating func bytes(_ length: Int) -> [UInt8]? {
        guard offset + length <= bytes.count else { return nil }
        defer { offset += length }
        return Array(bytes[offset..<(offset + length)])
    }

    mutating func string(length: Int) -> String? {
        guard let raw = bytes(length) else { return nil }
        return String(decoding: raw, as: UTF8.self)
    }
}
