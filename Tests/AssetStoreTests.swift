import Foundation

@main
struct AssetStoreTests {
    static func main() throws {
        let mode = CommandLine.arguments[1]
        let base = CommandLine.arguments[2]
        let cache = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let store = try AssetStore(baseString: base, cache: cache)
        let songs = try store.catalog()
        let sample = songs[0].loops[0]
        let file = try store.file(sample.file)
        precondition(!((try? Data(contentsOf: file).isEmpty) ?? true))

        if mode == "online" {
            // A corrupt cached file is fetched again rather than passed to the decoder.
            try Data("corrupt".utf8).write(to: file)
            let repaired = try store.file(sample.file)
            let repairedData = try Data(contentsOf: repaired)
            precondition(repairedData.count > 7)
            do {
                _ = try store.file("../catalog.json")
                fatalError("path traversal was accepted")
            } catch AssetStore.AssetError.invalidCatalog {}
            do {
                _ = try AssetStore(baseString: "http://example.com/", cache: cache)
                fatalError("insecure remote address was accepted")
            } catch AssetStore.AssetError.configuration {}
            let other = try AssetStore(baseString: base + "other-library/", cache: cache)
            do {
                _ = try other.catalog()
                fatalError("a different library reused the cached catalog")
            } catch {}
        } else if mode == "offline" {
            // The catalog and previously downloaded audio remain usable offline.
            try Data("corrupt".utf8).write(to: file)
            do {
                _ = try store.file(sample.file)
                fatalError("corrupt offline audio was accepted")
            } catch {}
        } else { fatalError("unknown test mode") }
        print("AssetStore \(mode) checks passed")
    }
}
