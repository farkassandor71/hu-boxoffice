"""Fold every monthly snapshot into a single films.json for the app.

Steps:
  1. discover snapshots (newest-first) via the WP REST API
  2. download each into a local cache (skip if already present)
  3. parse each; within a snapshot, resolve duplicate film rows (keep higher gross)
  4. match the same film across snapshots by a stable key
  5. emit current totals + a compact history (points only when admissions or gross changed)

Output: data/films.json  and  data/conflicts.log
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys
import unicodedata

from discover import list_snapshots
from http_util import get
from parse import parse_xls

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(ROOT, "cache")
DATA = os.path.join(ROOT, "data")


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


def dedupe_snapshot(recs: list[dict], log) -> dict[str, dict]:
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


def build(limit: int | None = None) -> dict:
    snaps = list_snapshots()
    snaps.sort(key=lambda s: s["date"])  # oldest-first for chronological history
    if limit:
        snaps = snaps[-limit:]

    log: list[str] = []
    # film_key -> aggregated record
    films: dict[str, dict] = {}

    for snap in snaps:
        date = snap["date"]
        path = download(snap)
        deduped = dedupe_snapshot(parse_xls(path), log)
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
            # latest snapshot always wins for the current-value fields
            f["title"] = rec["title"]
            f["ov_title"] = rec["ov_title"] or f["ov_title"]
            f["distributor"] = rec["distributor"] or f["distributor"]
            f["release"] = rec["release"] or f["release"]
            f["gross"] = rec["gross"]
            f["admissions"] = rec["admissions"]
            adm = rec["admissions"]
            gross = rec["gross"]
            if (adm is not None or gross is not None) and (
                adm != f["_last_adm"] or gross != f["_last_gross"]
            ):
                f["history"].append([date, adm, gross])
                f["_last_adm"] = adm
                f["_last_gross"] = gross

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

    payload = {
        "generated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "source": "filmforgalmazok.hu",
        "snapshot_count": len(snaps),
        "latest_snapshot": snaps[-1]["date"] if snaps else None,
        "film_count": len(out_films),
        "distributors": distributors,
        "films": out_films,
    }

    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, "films.json"), "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(DATA, "conflicts.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log))

    return payload


if __name__ == "__main__":
    lim = int(sys.argv[1]) if len(sys.argv) > 1 else None
    p = build(lim)
    print(
        f"films={p['film_count']} snapshots={p['snapshot_count']} "
        f"latest={p['latest_snapshot']}"
    )
