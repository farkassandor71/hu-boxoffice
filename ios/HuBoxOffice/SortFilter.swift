import Foundation

/// A sortable field, with a sensible default direction (newest/most/first vs. A-Z).
enum SortField: String, CaseIterable, Identifiable {
    case releaseDate, title, admissions, gross
    var id: Self { self }

    var label: String {
        switch self {
        case .releaseDate: return "Bemutató dátuma"
        case .title: return "Cím"
        case .admissions: return "Nézőszám"
        case .gross: return "Bevétel"
        }
    }

    /// Descending for numeric/date fields (biggest/newest first); ascending for title (A-Z).
    var defaultDescending: Bool { self != .title }
}

struct SortState: Equatable {
    var field: SortField = .releaseDate
    var descending: Bool = true

    static let `default` = SortState()

    mutating func select(_ field: SortField) {
        if self.field == field {
            descending.toggle()
        } else {
            self.field = field
            descending = field.defaultDescending
        }
    }

    func apply(to films: [Film]) -> [Film] {
        let sorted: [Film]
        switch field {
        case .title:
            sorted = films.sorted { $0.nTitle < $1.nTitle }
        case .admissions:
            sorted = films.sorted { ($0.admissions ?? -1) < ($1.admissions ?? -1) }
        case .gross:
            sorted = films.sorted { ($0.gross ?? -1) < ($1.gross ?? -1) }
        case .releaseDate:
            sorted = films.sorted { ($0.release ?? "") < ($1.release ?? "") }
        }
        return descending ? sorted.reversed() : sorted
    }
}

/// Stackable structured filters — all set conditions combine with AND, and stack
/// with the free-text search independently applied on top.
struct FilterState: Equatable {
    var year: Int?
    var month: Int?  // 1...12, independent of year: "any November"
    var admissionsMin: Int?
    var admissionsMax: Int?
    var grossMin: Int?
    var grossMax: Int?
    var distributor: String?

    var isActive: Bool {
        year != nil || month != nil || admissionsMin != nil || admissionsMax != nil
            || grossMin != nil || grossMax != nil || distributor != nil
    }

    var activeCount: Int {
        [year != nil, month != nil, admissionsMin != nil || admissionsMax != nil,
         grossMin != nil || grossMax != nil, distributor != nil]
            .filter { $0 }.count
    }

    func matches(_ film: Film) -> Bool {
        if year != nil || month != nil {
            guard let ym = film.releaseYearMonth else { return false }
            if let year, ym.year != year { return false }
            if let month, ym.month != month { return false }
        }
        if let admissionsMin, (film.admissions ?? Int.min) < admissionsMin { return false }
        if let admissionsMax, (film.admissions ?? Int.max) > admissionsMax { return false }
        if let grossMin, (film.gross ?? Int.min) < grossMin { return false }
        if let grossMax, (film.gross ?? Int.max) > grossMax { return false }
        if let distributor, film.distributor != distributor { return false }
        return true
    }

    func apply(to films: [Film]) -> [Film] {
        isActive ? films.filter(matches) : films
    }
}
