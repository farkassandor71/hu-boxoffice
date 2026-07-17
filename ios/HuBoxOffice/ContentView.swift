import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: FilmStore
    @State private var query = ""
    @State private var sort = SortState.default
    @State private var filter = FilterState()
    @State private var showingFilters = false

    private var results: [Film] {
        let searched = Search.filter(store.films, query: query)
        let filtered = filter.apply(to: searched)
        return sort.apply(to: filtered)
    }

    var body: some View {
        NavigationStack {
            List(results) { film in
                NavigationLink(value: film.id) {
                    FilmRow(film: film)
                }
            }
            .navigationDestination(for: String.self) { id in
                if let film = store.films.first(where: { $0.id == id }) {
                    FilmDetailView(film: film)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Filmek")
            .searchable(text: $query, prompt: "Cím keresése")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .overlay {
                if store.films.isEmpty {
                    ContentUnavailableView("Adatok betöltése…", systemImage: "film")
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: filter.isActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                }
                if let snap = store.latestSnapshot {
                    ToolbarItem(placement: .bottomBar) {
                        Text("\(Format.monthYear(snap)) · \(store.films.count) film")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterView(filter: $filter, distributors: store.distributors, yearRange: store.releaseYearRange)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortField.allCases) { field in
                Button {
                    sort.select(field)
                } label: {
                    HStack {
                        Text(field.label)
                        if sort.field == field {
                            Image(systemName: sort.descending ? "chevron.down" : "chevron.up")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
    }
}

/// A single search-result row. The subtitle disambiguates the ~116 shared titles
/// by original title, release year, and distributor.
struct FilmRow: View {
    let film: Film

    private var subtitle: String {
        var parts: [String] = []
        if let ov = film.ovTitle, Search.normalize(ov) != film.nTitle { parts.append(ov) }
        if let y = film.releaseYear { parts.append(y) }
        if let d = film.distributor { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(film.title).font(.body)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label(Format.number(film.admissions), systemImage: "person.2.fill")
                if let d = film.lastAdmissionsDelta, d > 0 {
                    Text(Format.delta(d)).foregroundStyle(.green)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
