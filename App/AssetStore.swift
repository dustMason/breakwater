import Foundation
import CryptoKit

/// Networking and disk access happen on workers, never on the audio callback.
final class AssetStore {
    private let base: URL
    private let cache: URL
    private let session: URLSession

    init(baseString: String, cache: URL? = nil) throws {
        guard var components = URLComponents(string: baseString),
              let scheme = components.scheme?.lowercased(), let host = components.host,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { throw AssetError.configuration }
        let local = ["localhost", "127.0.0.1", "::1"].contains(host)
        guard scheme == "https" || (scheme == "http" && local) else { throw AssetError.configuration }
        if !components.path.hasSuffix("/") { components.path += "/" }
        guard let url = components.url else { throw AssetError.configuration }
        base = url
        let cacheRoot = cache ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Breakwater", isDirectory: true)
        // A failed refresh must never use a different server's cached catalog.
        self.cache = cacheRoot.appendingPathComponent(Self.digest(Data(url.absoluteString.utf8)), isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        session = URLSession(configuration: config)
    }

    func catalog() throws -> [Song] {
        let path = cache.appendingPathComponent("catalog.json")
        do {
            let data = try get(base.appendingPathComponent("catalog.json"))
            let songs = try decodeCatalog(data)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try data.write(to: path, options: .atomic)
            return songs
        } catch {
            if let data = try? Data(contentsOf: path), let songs = try? decodeCatalog(data) { return songs }
            throw error
        }
    }

    private func decodeCatalog(_ data: Data) throws -> [Song] {
        let songs = try JSONDecoder().decode([Song].self, from: data)
        let samples = songs.flatMap(\.loops)
        let ids = samples.map(\.id)
        guard !songs.isEmpty, songs.allSatisfy({ !$0.loops.isEmpty }),
              Set(ids).count == ids.count, ids.allSatisfy({ $0 >= 0 && $0 < 1024 }),
              samples.allSatisfy({ Self.validPath($0.file) &&
                  ($0.parts?.files.allSatisfy(Self.validPath) ?? true) }) else { throw AssetError.invalidCatalog }
        return songs
    }

    private static func validPath(_ path: String) -> Bool {
        path.range(of: #"^objects/[a-f0-9]{64}\.(wav|m4a)$"#, options: .regularExpression) != nil
    }

    func file(_ path: String) throws -> URL {
        guard Self.validPath(path) else { throw AssetError.invalidCatalog }
        let destination = cache.appendingPathComponent(path)
        let expected = String(path.dropFirst("objects/".count).prefix(64))
        if let data = try? Data(contentsOf: destination), Self.digest(data) == expected {
            return destination
        }
        let data = try get(base.appendingPathComponent(path))
        guard Self.digest(data) == expected else { throw AssetError.invalidContent }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func get(_ url: URL) throws -> Data {
        let done = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        let task = session.dataTask(with: url) { data, response, error in
            let value: Result<Data, Error>
            if let error { value = .failure(error) }
            else if let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let data {
                value = .success(data)
            } else { value = .failure(AssetError.request) }
            box.store(value)
            done.signal()
        }
        task.resume()
        guard done.wait(timeout: .now() + 95) == .success else { task.cancel(); throw AssetError.request }
        return try box.load().get()
    }

    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Data, Error>?
        func store(_ value: Result<Data, Error>) { lock.lock(); result = value; lock.unlock() }
        func load() -> Result<Data, Error> {
            lock.lock(); defer { lock.unlock() }
            return result ?? .failure(AssetError.request)
        }
    }

    enum AssetError: LocalizedError {
        case configuration, invalidCatalog, invalidContent, request
        var errorDescription: String? {
            switch self {
            case .configuration: return "The asset library is not configured with a valid HTTPS address."
            case .invalidCatalog: return "The sample catalog is invalid."
            case .invalidContent: return "A downloaded audio file failed its integrity check."
            case .request: return "The sample library could not be reached."
            }
        }
    }
}
