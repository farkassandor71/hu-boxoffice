import Foundation

/// Hungarian-style number and date formatting for display.
enum Format {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{00A0}"   // non-breaking space, as used locally
        f.maximumFractionDigits = 0
        return f
    }()

    static func number(_ n: Int?) -> String {
        guard let n else { return "–" }
        return grouped.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Gross box office in forints, e.g. "2 358 453 846 Ft".
    static func forint(_ n: Int?) -> String {
        guard let n else { return "–" }
        return "\(number(n))\u{00A0}Ft"
    }

    /// Signed delta, e.g. "+12 400" / "0".
    static func delta(_ n: Int?) -> String {
        guard let n else { return "" }
        let sign = n > 0 ? "+" : ""
        return "\(sign)\(number(n))"
    }

    /// Signed delta in forints, e.g. "+12 400 Ft".
    static func forintDelta(_ n: Int?) -> String {
        guard let n else { return "" }
        let sign = n > 0 ? "+" : ""
        return "\(sign)\(forint(n))"
    }

    /// "2022-12-15" -> "2022. 12. 15." (Hungarian date order is already the ISO order).
    static func date(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "–" }
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[0]). \(parts[1]). \(parts[2])."
    }

    private static let hungarianMonths = [
        "január", "február", "március", "április", "május", "június",
        "július", "augusztus", "szeptember", "október", "november", "december",
    ]

    /// "2026-07-02" -> "2026. július". Used to label which monthly snapshot the
    /// data comes from — the source publishes one edition per month.
    static func monthYear(_ iso: String?) -> String {
        guard let iso, iso.count >= 7,
              let year = Int(iso.prefix(4)),
              let month = Int(iso.dropFirst(5).prefix(2)),
              (1...12).contains(month)
        else { return "–" }
        return "\(year). \(hungarianMonths[month - 1])"
    }

    /// Compact month/year for chart axis labels, e.g. "2026 júl.".
    static func monthYearShort(_ iso: String) -> String {
        guard iso.count >= 7,
              let year = Int(iso.prefix(4)),
              let month = Int(iso.dropFirst(5).prefix(2)),
              (1...12).contains(month)
        else { return iso }
        return "\(year) \(hungarianMonths[month - 1].prefix(3))."
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Parses a "YYYY-MM-DD" string, for date-arithmetic call sites.
    static func isoDate(_ iso: String) -> Date? {
        isoFormatter.date(from: String(iso.prefix(10)))
    }
}
