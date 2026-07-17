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
            }
        }
        .navigationTitle(film.title)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
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
