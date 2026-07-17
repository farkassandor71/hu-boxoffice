"""Merge new monthly snapshots into films.json.

Default (incremental) mode: load the existing data/films.json, work out which
archived snapshots aren't reflected in it yet (tracked via "processed_snapshots"),
and fold in only those — typically just the newest one file per run. A film's
last history point already encodes everything needed to detect whether the next
snapshot changed it, so no historical .xls files need to be re-read.

--full mode: ignore any existing films.json and rebuild from every archived
snapshot. Only needed for the initial backfill, or after a parser fix that should
be applied retroactively to history already baked into films.json.

Output: data/films.json  and  data/conflicts.log
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import unicodedata

from discover import list_snapshots
from http_util import get
from parse import parse_xls

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(ROOT, "cache")
DATA = os.path.join(ROOT, "data")
FILMS_JSON = os.path.join(DATA, "films.json")

_MERGE_FIELDS = (
    "key", "title", "ov_title", "distributor", "release", "gross", "admissions", "history",
)


def normalize(s: str) -> str:
    """Uppercase, strip accents, collapse non-alphanumerics — for keys and search."""
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.upper()
    return " ".join("".join(c if c.isalnum() else " " for c in s).split())


def film_key(rec: dict) -> str:
    """Stable identity across snapshots: normalized title + release year-month.

    rekordSorszam is blank on half the rows and titles are not unique, so neither
    works alone. Distributor is intentionally excluded — the source renames
    distributors over time, which would fracture a single film's history.
    """
    ym = rec["release"][:7] if rec.get("release") else "----"
    return f"{normalize(rec['title'])}|{ym}"


def dedupe_snapshot(recs: list[dict], log: list[str]) -> dict[str, dict]:
    """Collapse rows sharing a film_key within one snapshot, keeping higher gross."""
    by_key: dict[str, dict] = {}
    for rec in recs:
        k = film_key(rec)
        prev = by_key.get(k)
        if prev is None:
            by_key[k] = rec
            continue
        a = rec.get("gross") or 0
        b = prev.get("gross") or 0
        keep, drop = (rec, prev) if a > b else (prev, rec)
        by_key[k] = keep
        log.append(
            f"DUP {k!r}: kept gross={keep.get('gross')} "
            f"dropped gross={drop.get('gross')} title={rec['title']!r}"
        )
    return by_key


def download(snap: dict) -> str:
    """Fetch a snapshot into the cache (named by its snapshot date). Returns path."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"AllTimeTop-{snap['date']}.xls")
    if not os.path.exists(path):
        with open(path, "wb") as f:
            f.write(get(snap["url"]))
    return path


def merge_snapshot(films: dict[str, dict], date: str, deduped: dict[str, dict]) -> None:
    """Fold one already-deduped snapshot into the running `films` dict, in place."""
    for key, rec in deduped.items():
        f = films.get(key)
        if f is None:
            f = films[key] = {
                "key": key,
                "title": rec["title"],
                "ov_title": rec["ov_title"],
                "distributor": rec["distributor"],
                "release": rec["release"],
                "gross": rec["gross"],
                "admissions": rec["admissions"],
                "history": [],  # [[date, admissions, gross], ...] only when changed
                "_last_adm": None,
                "_last_gross": None,
            }
        # latest snapshot processed always wins for the current-value fields
        f["title"] = rec["title"]
        f["ov_title"] = rec["ov_title"] or f["ov_title"]
        f["distributor"] = rec["distributor"] or f["distributor"]
        f["release"] = rec["release"] or f["release"]
        f["gross"] = rec["gross"]
        f["admissions"] = rec["admissions"]
        adm, gross = rec["admissions"], rec["gross"]
        if (adm is not None or gross is not None) and (
            adm != f["_last_adm"] or gross != f["_last_gross"]
        ):
            f["history"].append([date, adm, gross])
            f["_last_adm"] = adm
            f["_last_gross"] = gross


def _load_existing() -> tuple[dict[str, dict], list[str]]:
    """Load films.json (if present) into the internal merge representation.

    A film's "_last_{adm,gross}" tracking fields are reconstructed from its last
    history point — the compact history already carries everything needed to
    resume merging without re-reading any historical .xls files.

    A file predating "processed_snapshots" (schema migration) is deliberately
    NOT reused here: its history may already reflect any number of snapshots
    that we can no longer identify, so resuming with an empty `processed` list
    would re-merge already-applied snapshots on top of themselves and duplicate
    every history point. Safer to report no existing state, which makes the
    caller do an effective full rebuild.
    """
    if not os.path.exists(FILMS_JSON):
        return {}, []
    with open(FILMS_JSON, encoding="utf-8") as fh:
        payload = json.load(fh)
    if "processed_snapshots" not in payload:
        return {}, []
    films: dict[str, dict] = {}
    for f in payload["films"]:
        history = f["history"]
        films[f["key"]] = {
            **{k: f[k] for k in _MERGE_FIELDS},
            "_last_adm": history[-1][1] if history else None,
            "_last_gross": history[-1][2] if history else None,
        }
    return films, payload.get("processed_snapshots", [])


def _check_history_invariant(films: dict[str, dict]) -> None:
    """Every film's history must have strictly increasing, non-repeating dates.

    A violation means a snapshot got merged twice (e.g. a stale/missing
    "processed_snapshots" causing re-merge on top of already-baked-in history) —
    fail loudly rather than silently ship duplicated history points.
    """
    for key, f in films.items():
        dates = [p[0] for p in f["history"]]
        if dates != sorted(set(dates)):
            raise AssertionError(
                f"history invariant violated for {key!r}: dates not strictly "
                f"increasing / contain duplicates: {dates}"
            )


def _finalize(films: dict[str, dict], processed: list[str]) -> dict:
    _check_history_invariant(films)
    out_films = []
    for f in films.values():
        f.pop("_last_adm", None)
        f.pop("_last_gross", None)
        # searchable normalized forms, precomputed so the app needn't strip accents
        f["n_title"] = normalize(f["title"])
        f["n_ov"] = normalize(f["ov_title"]) if f["ov_title"] else ""
        out_films.append(f)
    out_films.sort(key=lambda x: (x["gross"] is None, -(x["gross"] or 0)))

    distributors = sorted(
        {f["distributor"] for f in out_films if f["distributor"]}, key=normalize
    )

    return {
        "generated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "source": "filmforgalmazok.hu",
        "snapshot_count": len(processed),
        "latest_snapshot": processed[-1] if processed else None,
        "film_count": len(out_films),
        "distributors": distributors,
        "processed_snapshots": processed,
        "films": out_films,
    }


def build(full: bool = False, limit: int | None = None) -> dict:
    all_snaps = list_snapshots()
    all_snaps.sort(key=lambda s: s["date"])  # oldest-first for chronological history

    if full:
        films: dict[str, dict] = {}
        processed: list[str] = []
        todo = all_snaps
    else:
        films, processed = _load_existing()
        already_done = set(processed)
        todo = [s for s in all_snaps if s["date"] not in already_done]

    if limit:
        todo = todo[-limit:]

    log: list[str] = []
    for snap in todo:
        path = download(snap)
        deduped = dedupe_snapshot(parse_xls(path), log)
        merge_snapshot(films, snap["date"], deduped)
        processed.append(snap["date"])
    processed.sort()

    print(f"merged {len(todo)} new snapshot(s)" if not full else f"rebuilt from {len(todo)} snapshot(s)")

    payload = _finalize(films, processed)

    os.makedirs(DATA, exist_ok=True)
    with open(FILMS_JSON, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(DATA, "conflicts.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log))

    return payload


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--full", action="store_true",
        help="rebuild from every archived snapshot instead of merging incrementally",
    )
    ap.add_argument(
        "--limit", type=int, default=None,
        help="only process the N most recent not-yet-processed snapshots (or, "
             "with --full, the N most recent snapshots overall)",
    )
    args = ap.parse_args()
    p = build(full=args.full, limit=args.limit)
    print(
        f"films={p['film_count']} snapshots_total={p['snapshot_count']} "
        f"latest={p['latest_snapshot']}"
    )
