import Foundation

/// One data point in a film's history: a snapshot date with the admissions and
/// gross reported then. Stored in JSON as a compact [date, admissions, gross]
/// triple, so decoding is custom. Either metric may be null in rare source rows.
struct HistoryPoint: Identifiable {
    let date: String
    let admissions: Int?
    let gross: Int?
    var id: String { date }
}

extension HistoryPoint: Decodable {
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        date = try c.decode(String.self)
        admissions = try c.decodeIfPresent(Int.self)
        gross = try c.decodeIfPresent(Int.self)
    }
}

/// A film as served by the pipeline: current totals plus month-over-month history.
struct Film: Identifiable, Decodable {
    let key: String
    let title: String
    let ovTitle: String?
    let distributor: String?
    let release: String?
    let gross: Int?
    let admissions: Int?
    let history: [HistoryPoint]
    let nTitle: String
    let nOv: String

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, title
        case ovTitle = "ov_title"
        case distributor, release, gross, admissions, history
        case nTitle = "n_title"
        case nOv = "n_ov"
    }

    /// Release year, for disambiguating films that share a title.
    var releaseYear: String? {
        guard let release, release.count >= 4 else { return nil }
        return String(release.prefix(4))
    }

    /// Release year-month as an Int (YYYYMM), for month/year filtering. Nil when
    /// the release date is unknown.
    var releaseYearMonth: (year: Int, month: Int)? {
        guard let release, release.count >= 7,
              let y = Int(release.prefix(4)),
              let m = Int(release.dropFirst(5).prefix(2))
        else { return nil }
        return (y, m)
    }

    /// Admissions gained between the two most recent differing snapshots.
    var lastAdmissionsDelta: Int? {
        guard history.count >= 2,
              let last = history.last?.admissions,
              let prev = history[history.count - 2].admissions
        else { return nil }
        return last - prev
    }

    /// Gross gained between the two most recent differing snapshots.
    var lastGrossDelta: Int? {
        guard history.count >= 2,
              let last = history.last?.gross,
              let prev = history[history.count - 2].gross
        else { return nil }
        return last - prev
    }
}

/// Top-level payload of films.json.
struct FilmData: Decodable {
    let generated: String
    let latestSnapshot: String?
    let filmCount: Int
    let distributors: [String]
    let films: [Film]

    enum CodingKeys: String, CodingKey {
        case generated
        case latestSnapshot = "latest_snapshot"
        case filmCount = "film_count"
        case distributors
        case films
    }
}
