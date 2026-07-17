import Foundation

/// Diacritic- and case-insensitive search over a film's local and original titles.
///
/// Films carry precomputed normalized titles (`nTitle`, `nOv`) from the pipeline, so
/// matching is a plain substring test on the same normalization applied to the query:
/// typing "szepseg" finds "A SZÉPSÉG ÉS A SZÖRNYETEG", "zootopia" finds "ZOOTROPOLIS 2".
enum Search {
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "hu"))
        let scalars = folded.uppercased().unicodeScalars.map { sc -> Character in
            CharacterSet.alphanumerics.contains(sc) ? Character(sc) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    static func filter(_ films: [Film], query: String) -> [Film] {
        let q = normalize(query)
        guard !q.isEmpty else { return films }
        return films.filter { $0.nTitle.contains(q) || $0.nOv.contains(q) }
    }
}
