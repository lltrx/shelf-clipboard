import XCTest
@testable import Shelf

/// Each test gets its own Store in a throwaway folder, never the real
/// ~/Library/Application Support/Shelf (which holds the user's clipboard history).
class StoreTestCase: XCTestCase {
    var dir: URL!
    var store: Store!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfTests-\(UUID().uuidString)", isDirectory: true)
        store = try Store(directory: dir)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    func makeStore() throws -> (Store, URL) {
        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: other) }
        return (try Store(directory: other), other)
    }

    func text(_ s: String, formats: [(type: String, data: Data)] = []) -> Capture {
        Capture(kind: .text, text: s, hash: Monitor.digest("text", Data(s.utf8)),
                sourceBundle: "com.example.app", sourceName: "Example", formats: formats)
    }

    func image(_ bytes: [UInt8]) -> Capture {
        let data = Data(bytes)
        return Capture(kind: .image, imageData: data, detail: "1 × 1", hash: Monitor.digest("image", data))
    }

    func permissions(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
