import SwiftUI

/// Two-series line chart for a film's history: admissions and gross, each on its
/// own independent scale (they differ by orders of magnitude) so both curves stay
/// readable, with month/year labels under the data points.
struct DualLineChart: View {
    let points: [HistoryPoint]
    // Deliberately not tied to the app's accent color: admissions and gross track
    // each other so closely (roughly constant ticket price) that their normalized
    // curves nearly overlap, so the two lines need strong, unrelated hues to stay
    // visually distinct where they coincide — blue/orange is a standard, high-
    // contrast, colorblind-safe pairing.
    var admissionsColor: Color = .blue
    var grossColor: Color = .orange

    private let axisHeight: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legend
            GeometryReader { geo in
                let admValues = points.map { $0.admissions.map(Double.init) }
                let grossValues = points.map { $0.gross.map(Double.init) }
                let aKnown = admValues.compactMap { $0 }
                let gKnown = grossValues.compactMap { $0 }

                if points.count >= 2, let aLo = aKnown.min(), let aHi = aKnown.max(),
                   let gLo = gKnown.min(), let gHi = gKnown.max() {
                    let stepX = geo.size.width / CGFloat(points.count - 1)
                    let chartHeight = geo.size.height - axisHeight

                    ZStack(alignment: .topLeading) {
                        line(admValues, lo: aLo, span: max(aHi - aLo, 1), stepX: stepX, height: chartHeight)
                            .stroke(admissionsColor, style: .init(lineWidth: 2, lineJoin: .round))
                        line(grossValues, lo: gLo, span: max(gHi - gLo, 1), stepX: stepX, height: chartHeight)
                            .stroke(grossColor, style: .init(lineWidth: 2, lineJoin: .round))

                        ForEach(labelIndices(count: points.count), id: \.self) { i in
                            Text(Format.monthYearShort(points[i].date))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .position(
                                    x: clampedX(CGFloat(i) * stepX, in: geo.size.width),
                                    y: chartHeight + axisHeight / 2 + 2
                                )
                        }
                    }
                } else {
                    Text("Nincs elég adat a grafikonhoz")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func line(_ values: [Double?], lo: Double, span: Double, stepX: CGFloat, height: CGFloat) -> Path {
        Path { p in
            var started = false
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                let y = height * (1 - CGFloat((v - lo) / span))
                let pt = CGPoint(x: CGFloat(i) * stepX, y: y)
                if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
            }
        }
    }

    /// At most 5 evenly-spaced axis labels regardless of how many points exist.
    private func labelIndices(count: Int) -> [Int] {
        let maxLabels = 5
        if count <= maxLabels { return Array(0..<count) }
        let step = Double(count - 1) / Double(maxLabels - 1)
        return (0..<maxLabels).map { Int((Double($0) * step).rounded()) }
    }

    /// Keeps edge labels from being clipped by the chart bounds.
    private func clampedX(_ x: CGFloat, in width: CGFloat) -> CGFloat {
        min(max(x, 20), max(width - 20, 20))
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(admissionsColor, "Nézőszám")
            legendItem(grossColor, "Bevétel")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 14, height: 3)
            Text(label)
        }
    }
}
