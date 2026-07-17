import Foundation

/// Loads film data offline-first, then refreshes from the network.
///
/// Order of precedence on launch:
///   1. a previously downloaded copy in Caches (freshest we have)
///   2. the copy bundled with the app (guarantees the app works on first launch,
///      fully offline, before any network call)
/// A background refresh then fetches the published films.json, using an ETag so the
/// ~550 KB payload is only re-downloaded when the source actually changed.
@MainActor
final class FilmStore: ObservableObject {
    @Published private(set) var films: [Film] = []
    @Published private(set) var latestSnapshot: String?
    @Published private(set) var distributors: [String] = []
    @Published private(set) var isRefreshing = false

    /// Release years present in the data, ascending. Empty until data loads.
    var releaseYearRange: ClosedRange<Int>? {
        let years = films.compactMap { $0.releaseYearMonth?.year }
        guard let lo = years.min(), let hi = years.max() else { return nil }
        return lo...hi
    }

    /// Published data URL — served by GitHub Pages from the hu-boxoffice repo's
    /// data/ directory (see .github/workflows/update.yml).
    static let remoteURL = URL(string: "https://farkassandor71.github.io/hu-boxoffice/films.json")!

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("films.json")
    }()
    private let etagKey = "films.json.etag"

    func load() {
        if let data = try? Data(contentsOf: cacheURL), apply(data) { return }
        if let url = Bundle.main.url(forResource: "films", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            _ = apply(data)
        }
    }

    @discardableResult
    private func apply(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(FilmData.self, from: data) else {
            return false
        }
        films = decoded.films
        latestSnapshot = decoded.latestSnapshot
        distributors = decoded.distributors
        return true
    }

    /// Fetch the latest data if it changed. Returns true when new data was applied.
    @discardableResult
    func refresh() async -> Bool {
        isRefreshing = true
        defer { isRefreshing = false }

        var req = URLRequest(url: Self.remoteURL)
        if let etag = UserDefaults.standard.string(forKey: etagKey) {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 304 { return false }  // unchanged
            guard http.statusCode == 200, apply(data) else { return false }
            try? data.write(to: cacheURL)
            if let etag = http.value(forHTTPHeaderField: "Etag") {
                UserDefaults.standard.set(etag, forKey: etagKey)
            }
            return true
        } catch {
            return false  // offline: keep whatever we already loaded
        }
    }
}
