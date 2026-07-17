# Box Office HU

An iPhone app to search the Hungarian theatrical box-office list published by the
Association of Distributors (filmforgalmazok.hu), with month-over-month history the
source `.xls` file cannot show — fully usable offline.

The source posts one all-time `.xls` per month ("Filmenkénti összesítés"). Downloading
and searching that 2.6 MB file by hand — especially on a phone — is the problem this
solves.

## How it works

```
GitHub Actions (daily)                     iPhone app (SwiftUI)
  discover.py  → list snapshots via WP API   FilmStore  → loads bundled JSON,
  parse.py     → read each .xls (xlrd)                    refreshes over network (ETag)
  build.py     → dedupe + delta history      Search     → diacritic-insensitive
               → films.json                  Filter/Sort → year/month/admissions/
  GitHub Pages → serves films.json ──────────┘             gross/distributor, stackable
                                              Detail     → totals + dual-line history chart
```

The phone never parses `.xls`, and never needs a network connection to search — the full
dataset is bundled into the app and kept in an on-disk cache, so search, sort, and filter
all work offline. The pipeline turns 95 monthly snapshots (back to Feb 2018) into one
`films.json` (~2 MB, ~475 KB gzipped) covering 7,135 films.

## Pipeline (`pipeline/`)

| File | Role |
|------|------|
| `discover.py` | Enumerate snapshots via the site's open WordPress REST API. De-dupes re-uploaded months. |
| `parse.py` | Read one `.xls` with `xlrd`. Locates columns by their Hungarian header text rather than fixed position — the layout has changed twice across the archive (a leading ID column was added, then a second header row) and position-based parsing silently misreads ~24% of the older files. Tolerant of the source's other real quirks: text/impossible/overflowing dates → null, a distributor cell that's actually a corrupted date/serial → null. Print count (kópiaszám) is dropped — not reliable in the source. |
| `build.py` | Merges new snapshots into `films.json`. Resolves duplicate rows (keeps higher gross, logs to `conflicts.log`), assigns a stable per-film key (`normalized title + release month`), and records a history point whenever admissions or gross changed. |
| `http_util.py` | HTTPS with `certifi` (needed on python.org macOS builds). |

**Incremental by default.** `build.py` tracks which snapshots are already folded into
`films.json` (`processed_snapshots`) and, each run, downloads and merges only the ones
that aren't — in practice just the newest month, since a film's last history point
already encodes everything needed to detect whether the next snapshot changed it. No
historical `.xls` files need to be re-read after the initial backfill. Verified by
comparing an incremental merge against a from-scratch rebuild — byte-identical output.

Run locally:

```bash
pip install -r pipeline/requirements.txt
python pipeline/build.py                  # merge only new snapshots (the normal case)
python pipeline/build.py --full           # rebuild from every archived snapshot —
                                           # needed after a parser fix, or if films.json
                                           # predates the "processed_snapshots" field
python pipeline/build.py --full --limit 3 # full rebuild, but only the 3 latest snapshots
                                           # (fast, for testing)
```

Downloaded `.xls` files are cached in `cache/` (git-ignored); `--full` reuses whatever's
already there and only fetches what's missing.

### Why these choices

- **Column lookup by header text, not position.** Verified by scanning all 95 cached
  files: the header text is stable but its column index and row is not. Position-based
  parsing was initially shipped and produced ~3,000 phantom duplicate "films" from
  misread columns before this was caught and fixed.
- **Stable key excludes distributor.** The source renames distributors over time
  (`FORUM` ↔ `FÓRUM HUNGARY`), which would otherwise split one film's history in two.
- **Delta history, not full series.** Naively storing every film × every snapshot is
  ~680k points; recording only changes keeps it small — long-tail films collapse to one
  point, only films still in cinemas carry a real curve.
- **Titles are not unique** (116 repeat, e.g. `MICHAEL` ×3). The app disambiguates by
  original title, year, and distributor.
- **Incremental merge, not incremental download-only.** A tempting simpler design is
  "just re-download and re-parse everything, but only actually fetch the new file" —
  that avoids bandwidth waste but not compute, and doesn't solve the real risk: silently
  resuming from a `films.json` whose provenance you don't know. The fix here is
  `processed_snapshots` as an explicit ledger, checked before any merge.

## App (`ios/`)

SwiftUI, iOS 17+, no third-party dependencies. Open `ios/HuBoxOffice.xcodeproj`.

- **Offline-first:** ships with `films.json` bundled and keeps a refreshed copy in the
  on-disk cache, so search/sort/filter never need a network call; a background refresh
  pulls updates using an ETag (re-downloads only on real change).
- **Search** folds diacritics and case and matches both local and original titles, so
  `szepseg` finds *A SZÉPSÉG ÉS A SZÖRNYETEG* and `zootopia` finds *ZOOTROPOLIS 2*.
- **Sort** by title, admissions, gross, or release date (default — newest first).
- **Filters**, all stackable with each other and with search: release year, release
  month (independent of year — "every November"), admissions above/below a threshold,
  gross above/below a threshold, distributor.
- **Detail** shows admissions, gross (Ft), release, and distributor, plus a dual-line
  history chart — admissions and gross on independent scales, month/year labels on the
  x-axis — with the latest month-over-month delta for each.
- **Database version label** in the list footer reads e.g. "2026. július", derived from
  the newest snapshot's filename date; it advances on its own as new monthly files arrive
  (next month it reads "2026. augusztus" with no code change).
- **Background refresh** (`BGAppRefreshTask`) checks occasionally and posts a local
  notification when a new monthly snapshot appears — no push server needed.

## Hosting

Repo: [github.com/farkassandor71/hu-boxoffice](https://github.com/farkassandor71/hu-boxoffice)
(public — required for free GitHub Pages on a Free account).

Pages is enabled (source: GitHub Actions). `.github/workflows/update.yml` runs daily,
rebuilds `films.json` only when the source actually changed, and deploys it to
`https://farkassandor71.github.io/hu-boxoffice/films.json` — which `FilmStore.remoteURL`
already points at.

## Remaining setup (needs your accounts)

### Put it on your iPhone (Apple Developer, $99/yr)
- The simulator needs nothing. To install on your own phone, set your team in Xcode
  (Signing & Capabilities) and run to the device.
- Without a paid account a sideloaded build stops opening after 7 days and must be
  re-signed; the paid account removes that and is required for background refresh + the
  App Store.

## Data source & attribution

Data © the films' distributors, compiled by filmforgalmazok.hu. This project reformats the
publicly posted monthly files for personal search; verify figures against the source.
