import SwiftUI

/// Sheet for the stackable structured filters: release year, release month
/// (independent of year), admissions/gross thresholds, and distributor.
struct FilterView: View {
    @Binding var filter: FilterState
    let distributors: [String]
    let yearRange: ClosedRange<Int>?
    @Environment(\.dismiss) private var dismiss

    private static let months = [
        "január", "február", "március", "április", "május", "június",
        "július", "augusztus", "szeptember", "október", "november", "december",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Bemutató") {
                    Picker("Év", selection: $filter.year) {
                        Text("Bármelyik").tag(Int?.none)
                        if let yearRange {
                            ForEach(Array(yearRange).reversed(), id: \.self) { y in
                                Text(String(y)).tag(Int?.some(y))
                            }
                        }
                    }
                    Picker("Hónap", selection: $filter.month) {
                        Text("Bármelyik").tag(Int?.none)
                        ForEach(1...12, id: \.self) { m in
                            Text(Self.months[m - 1].capitalized).tag(Int?.some(m))
                        }
                    }
                }

                Section("Nézőszám") {
                    numberField("Legalább", value: $filter.admissionsMin)
                    numberField("Legfeljebb", value: $filter.admissionsMax)
                }

                Section("Bevétel (Ft)") {
                    numberField("Legalább", value: $filter.grossMin)
                    numberField("Legfeljebb", value: $filter.grossMax)
                }

                Section("Forgalmazó") {
                    NavigationLink {
                        DistributorPickerView(distributors: distributors, selection: $filter.distributor)
                    } label: {
                        HStack {
                            Text("Forgalmazó")
                            Spacer()
                            Text(filter.distributor ?? "Bármelyik")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if filter.isActive {
                    Section {
                        Button("Szűrők törlése", role: .destructive) {
                            filter = FilterState()
                        }
                    }
                }
            }
            .navigationTitle("Szűrők")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kész") { dismiss() }
                }
            }
        }
    }

    private func numberField(_ label: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: intProxy(value))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
        }
    }

    private func intProxy(_ value: Binding<Int?>) -> Binding<String> {
        Binding<String>(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0.filter(\.isNumber)) }
        )
    }
}

private struct DistributorPickerView: View {
    let distributors: [String]
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? distributors
            : distributors.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Button {
                selection = nil
                dismiss()
            } label: {
                HStack {
                    Text("Bármelyik")
                    Spacer()
                    if selection == nil { Image(systemName: "checkmark") }
                }
            }
            ForEach(filtered, id: \.self) { d in
                Button {
                    selection = d
                    dismiss()
                } label: {
                    HStack {
                        Text(d)
                        Spacer()
                        if selection == d { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .searchable(text: $query, prompt: "Forgalmazó keresése")
        .navigationTitle("Forgalmazó")
        .navigationBarTitleDisplayMode(.inline)
    }
}
