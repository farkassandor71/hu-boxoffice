import SwiftUI

struct FilmDetailView: View {
    let film: Film

    var body: some View {
        List {
            Section {
                stat("Látogató", Format.number(film.admissions), delta: film.lastAdmissionsDelta)
                stat("Bevétel", Format.forint(film.gross), delta: film.lastGrossDelta, deltaFormat: Format.forintDelta)
                stat("Bemutató", Format.date(film.release))
                if let d = film.distributor { stat("Forgalmazó", d) }
            }

            if film.history.count >= 2 {
                Section("Alakulás") {
                    DualLineChart(points: film.history)
                        .frame(height: 170)
                        .padding(.vertical, 8)
                }
            } else if let note = staleSingleValueNote {
                Section("Alakulás") {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
            // A single history point with a release close to that point's date is
            // simply too new to chart yet -- no section shown, same as before.
        }
        .navigationTitle(film.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    /// For a film with exactly one history point far removed from its release
    /// date: its numbers were already fixed before that point was recorded, so
    /// there's nothing to chart -- explain why instead of showing nothing.
    private var staleSingleValueNote: String? {
        guard film.history.count == 1,
              let release = film.release, let pointDate = film.history.first?.date,
              let releaseDate = Format.isoDate(release), let asOf = Format.isoDate(pointDate),
              asOf.timeIntervalSince(releaseDate) > 90 * 86400
        else { return nil }
        return "A nézőszám és a bevétel \(Format.monthYear(pointDate)) óta nem változott — "
            + "nincs újabb adatpont, amit ábrázolni lehetne."
    }

    private func stat(
        _ label: String, _ value: String, delta: Int? = nil,
        deltaFormat: (Int?) -> String = Format.delta
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).monospacedDigit().multilineTextAlignment(.trailing)
                if let delta, delta != 0 {
                    Text(deltaFormat(delta))
                        .font(.caption2)
                        .foregroundStyle(delta > 0 ? .green : .secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
