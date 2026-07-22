import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: FilmStore
    @State private var query = ""
    @State private var sort = SortState.default
    @State private var filter = FilterState()
    @State private var showingFilters = false
    #if os(macOS)
    // Two-pane on Mac: selecting a row shows its detail in the trailing column
    // instead of pushing, so there's no back-and-forth to browse several films.
    @State private var selection: String?
    #endif

    private var results: [Film] {
        let searched = Search.filter(store.films, query: query)
        let filtered = filter.apply(to: searched)
        return sort.apply(to: filtered)
    }

    /// "Filmek · 2026. július" — shows which monthly edition is loaded right next
    /// to the screen title, so it's visible without scrolling to the bottom bar.
    private var navigationTitle: String {
        guard let snap = store.latestSnapshot else { return "Filmek" }
        return "Filmek · \(Format.monthYear(snap))"
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            list
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } detail: {
            if let selection, let film = store.films.first(where: { $0.id == selection }) {
                FilmDetailView(film: film)
            } else {
                ContentUnavailableView("Válassz egy filmet a listából", systemImage: "film")
            }
        }
        #else
        NavigationStack {
            list
                .navigationDestination(for: String.self) { id in
                    if let film = store.films.first(where: { $0.id == id }) {
                        FilmDetailView(film: film)
                    }
                }
        }
        #endif
    }

    /// The film list itself, plus every modifier that's identical regardless of
    /// which container (NavigationStack vs. NavigationSplitView) wraps it.
    private var list: some View {
        Group {
            #if os(macOS)
            List(results, selection: $selection) { film in
                FilmRow(film: film).tag(film.id)
            }
            .listStyle(.sidebar)
            #else
            List(results) { film in
                NavigationLink(value: film.id) {
                    FilmRow(film: film)
                }
            }
            .listStyle(.plain)
            #endif
        }
        .navigationTitle(navigationTitle)
        .searchable(text: $query, prompt: "Cím keresése")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .overlay {
            if store.films.isEmpty {
                ContentUnavailableView("Adatok betöltése…", systemImage: "film")
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .refreshable { await store.refresh() }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                filterButton
            }
            ToolbarItem(placement: .bottomBar) {
                filmCountLabel
            }
            #else
            ToolbarItem(placement: .automatic) {
                sortMenu
            }
            ToolbarItem(placement: .automatic) {
                filterButton
            }
            ToolbarItem(placement: .status) {
                filmCountLabel
            }
            #endif
        }
        .sheet(isPresented: $showingFilters) {
            FilterView(filter: $filter, distributors: store.distributors, yearRange: store.releaseYearRange)
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

    private var filterButton: some View {
        Button {
            showingFilters = true
        } label: {
            Image(systemName: filter.isActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
    }

    private var filmCountLabel: some View {
        Text("\(Format.number(store.films.count)) film")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
