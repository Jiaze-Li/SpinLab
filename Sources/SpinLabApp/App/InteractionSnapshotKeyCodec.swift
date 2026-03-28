import Foundation

enum InteractionSnapshotKeyCodec {
    static func dictionaryKey(for id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
