import Foundation
import GrazeCore

/// 「待删除」标记的唯一事实来源就是 Photos 里那个相册。
/// 这里只是把它缓存成 Set 方便 UI 判断，每次操作后立即回读真值。
@MainActor
final class MarkStore: ObservableObject {
    @Published private(set) var marked: Set<String> = []
    @Published private(set) var lastError: String?

    func refresh() async {
        marked = DeletionAlbum.markedIdentifiers()
    }

    func setMarked(_ identifiers: [String], _ value: Bool) async {
        guard !identifiers.isEmpty else { return }
        do {
            try await DeletionAlbum.setMarked(identifiers, marked: value)
            if value {
                marked.formUnion(identifiers)
            } else {
                marked.subtract(identifiers)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggle(_ identifier: String) async {
        await setMarked([identifier], !marked.contains(identifier))
    }
}
