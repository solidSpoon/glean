import Foundation

/// 落盘日志。
///
/// 之前所有诊断都只能靠"跑一下看界面"，出问题无从查证。现在每次运行写两份：
///   ~/Library/Logs/graze/graze.log    人能读的行日志
///   ~/Library/Logs/graze/graze.jsonl  一行一个 JSON，方便 grep / jq
///
/// 让 agent（或你）在 App 之外直接读文件定位问题，不用截图。
public final class GrazeLog: @unchecked Sendable {
    public static let shared = GrazeLog()

    public let directory: URL

    public var textURL: URL { directory.appendingPathComponent("graze.log") }
    public var jsonURL: URL { directory.appendingPathComponent("graze.jsonl") }

    private let queue = DispatchQueue(label: "com.spoon.graze.log")
    private let stamp: DateFormatter
    private var textHandle: FileHandle?
    private var jsonHandle: FileHandle?

    /// 单个文件超过这个大小就轮转一次（保留上一份为 .1）。
    private let maxBytes = 8 * 1024 * 1024

    private init() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        directory = library.appendingPathComponent("Logs/graze", isDirectory: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        stamp = formatter
    }

    /// 每次运行开头打一条，方便在同一个文件里切分不同次运行。
    public func begin(_ tag: String) {
        queue.sync {
            open()
            emit(level: "info", message: "===== \(tag) =====", fields: ["event": "begin"])
        }
    }

    public func info(_ message: String, _ fields: [String: Any] = [:]) {
        queue.sync {
            open()
            emit(level: "info", message: message, fields: fields)
        }
    }

    public func debug(_ message: String, _ fields: [String: Any] = [:]) {
        queue.sync {
            open()
            emit(level: "debug", message: message, fields: fields)
        }
    }

    // MARK: - Private

    private func open() {
        guard textHandle == nil else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        rotateIfNeeded(textURL)
        rotateIfNeeded(jsonURL)

        if !fm.fileExists(atPath: textURL.path) {
            fm.createFile(atPath: textURL.path, contents: nil)
        }
        if !fm.fileExists(atPath: jsonURL.path) {
            fm.createFile(atPath: jsonURL.path, contents: nil)
        }

        textHandle = try? FileHandle(forWritingTo: textURL)
        jsonHandle = try? FileHandle(forWritingTo: jsonURL)
        textHandle?.seekToEndOfFile()
        jsonHandle?.seekToEndOfFile()
    }

    private func rotateIfNeeded(_ url: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > maxBytes else { return }
        let backup = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    /// 调用方已经持有 queue。
    private func emit(level: String, message: String, fields: [String: Any]) {
        let now = Date()
        let line = "\(stamp.string(from: now)) [\(level)] \(message)"
            + (fields.isEmpty ? "" : " " + fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
        if let data = (line + "\n").data(using: .utf8) {
            try? textHandle?.write(contentsOf: data)
        }

        var payload = fields
        payload["ts"] = ISO8601DateFormatter().string(from: now)
        payload["level"] = level
        payload["msg"] = message
        // JSONSerialization 不接受 Swift 的 Optional，调用方要把 nil 传成 NSNull()
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8),
           let bytes = (json + "\n").data(using: .utf8) {
            try? jsonHandle?.write(contentsOf: bytes)
        }
    }
}
