"""Discover all AllTimeTop .xls snapshots via the filmforgalmazok.hu WordPress REST API.

The site exposes an open, unauthenticated media endpoint. Each monthly snapshot is a
media item whose source_url ends in AllTimeTop-YYYYMMDD.xls. Enumerating via the API
avoids guessing URLs and handles real-world irregularities (e.g. -1 suffixes).
"""
from __future__ import annotations

import datetime as dt
import re
import json

from http_util import get as _get

API = "https://filmforgalmazok.hu/wp-json/wp/v2/media"

# AllTimeTop-20260702.xls  or  AllTimeTop-20180208-1.xls
_FN = re.compile(r"AllTimeTop-(\d{8})(?:-\d+)?\.xls$", re.IGNORECASE)


def snapshot_date(source_url: str) -> dt.date | None:
    """Parse the YYYYMMDD stamped into the filename (the snapshot's real date)."""
    m = _FN.search(source_url)
    if not m:
        return None
    try:
        return dt.datetime.strptime(m.group(1), "%Y%m%d").date()
    except ValueError:
        return None


def list_snapshots() -> list[dict]:
    """Return snapshots newest-first: [{date: 'YYYY-MM-DD', url: str}, ...].

    De-duplicates on the filename date, keeping the first (newest by API order)
    when the site has re-uploaded the same month (the -1 case).
    """
    url = (
        f"{API}?search=AllTimeTop&per_page=100"
        "&orderby=date&order=desc&_fields=source_url,date"
    )
    items = json.loads(_get(url))
    seen: set[dt.date] = set()
    out: list[dict] = []
    for it in items:
        src = it.get("source_url", "")
        d = snapshot_date(src)
        if d is None or d in seen:
            continue
        seen.add(d)
        out.append({"date": d.isoformat(), "url": src})
    out.sort(key=lambda s: s["date"], reverse=True)
    return out


if __name__ == "__main__":
    snaps = list_snapshots()
    print(f"{len(snaps)} snapshots")
    for s in snaps[:3] + snaps[-2:]:
        print(f"  {s['date']}  {s['url']}")
