"""Parse one AllTimeTop-*.xls into a clean list of film records.

The source is a legacy BIFF8 file, CP1250. Only the 'ÖSSZESÍTETT' sheet matters.
Columns kept: title, ov_title, distributor, release date, gross, admissions.
Print count (kópiaszám) is dropped — the source's print counts are not reliable.

Columns are located by their Hungarian header text, not by fixed position: across
the 95 archived snapshots the layout has changed twice (a leading ID column was
added, and a second machine-readable header row was inserted above the human one),
shifting every column index by one in about a quarter of the files. Locating by
header name handles every layout that has existed without per-era special-casing.

Real hazards handled here (all observed in the live archive):
  - release date may be an Excel serial, a text string in several formats, an
    impossible date (2013.11.31.), a corrupt out-of-range serial, or epoch-zero
    -> normalized to None.
  - a title cell may be numeric; admissions may be stored as text.
  - in some older rows the distributor cell itself contains a date (a source
    corruption, not a real distributor) -> normalized to None.
"""
from __future__ import annotations

import datetime as dt
import re

import xlrd

SHEET = "ÖSSZESÍTETT"

# Hungarian header text -> logical field name. Matched case-insensitively.
_HEADERS = {
    "CÍM": "title",
    "EREDETI CÍM": "ov_title",
    "FORGALMAZÓ": "distributor",
    "BEMUTATÓ": "release",
    "BEVÉTEL": "gross",
    "LÁTOGATÓ": "admissions",
}

# Release dates outside this range are treated as junk (epoch-zero serials, typos,
# or corrupt cells that decode to a nonsense far-future/far-past year).
# The Hungarian theatrical dataset effectively starts in the late 1980s.
_MIN_YEAR = 1985
_MAX_YEAR = dt.date.today().year + 1

# A distributor cell that is itself a bare date (e.g. "2012.10.18") is a known
# source corruption in a handful of older rows — not a real distributor name.
_DATE_LIKE = re.compile(r"^\d{4}[.\-/]\d{1,2}[.\-/]\d{1,2}\.?$")


def _find_header(sheet) -> tuple[int, dict[str, int]]:
    """Locate the header row (within the first few rows) and map field -> column."""
    for r in range(min(4, sheet.nrows)):
        cols: dict[str, int] = {}
        for i, cell in enumerate(sheet.row(r)):
            key = str(cell.value).strip().upper()
            if key in _HEADERS:
                cols[_HEADERS[key]] = i
        if "title" in cols:
            return r, cols
    raise ValueError(f"could not locate header row in {sheet.name!r}")


def _text(cell) -> str:
    """Cell value as a trimmed string, regardless of stored type."""
    v = cell.value
    if isinstance(v, float):
        # integers stored as floats -> drop the .0
        return str(int(v)) if v.is_integer() else str(v)
    return str(v).strip()


def _num(cell):
    """Cell value as an int, or None if empty/non-numeric."""
    v = cell.value
    if isinstance(v, (int, float)):
        return int(round(v))
    s = str(v).strip().replace(" ", "").replace(" ", "")
    if not s:
        return None
    try:
        return int(round(float(s.replace(",", "."))))
    except ValueError:
        return None


def _parse_text_date(s: str) -> dt.date | None:
    """Parse dates the source stored as text: 2016-07-07, 2012.11.22, 2013.11.31."""
    s = s.strip().rstrip(".").strip()
    m = re.match(r"^(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})$", s)
    if not m:
        return None
    y, mo, d = (int(x) for x in m.groups())
    try:
        return dt.date(y, mo, d)
    except ValueError:
        return None  # e.g. Nov 31 -> impossible, discard rather than crash


def _release(cell, datemode: int) -> str | None:
    """Return ISO date string, or None for blank/impossible/epoch-junk values."""
    d: dt.date | None = None
    if cell.ctype in (xlrd.XL_CELL_DATE, xlrd.XL_CELL_NUMBER):
        try:
            d = xlrd.xldate_as_datetime(cell.value, datemode).date()
        except (ValueError, OverflowError, xlrd.XLDateError):
            d = None  # out-of-range serials in older snapshots
    elif cell.ctype == xlrd.XL_CELL_TEXT:
        d = _parse_text_date(cell.value)
    if d is None or not (_MIN_YEAR <= d.year <= _MAX_YEAR):
        return None
    return d.isoformat()


def parse_xls(path: str) -> list[dict]:
    """Return [{title, ov_title, distributor, release, gross, admissions}]."""
    book = xlrd.open_workbook(path)
    sheet = book.sheet_by_name(SHEET)
    dm = book.datemode
    header_row, cols = _find_header(sheet)
    c_title = cols["title"]
    c_ov = cols.get("ov_title")
    c_dist = cols.get("distributor")
    c_release = cols.get("release")
    c_gross = cols.get("gross")
    c_adm = cols.get("admissions")

    rows: list[dict] = []
    for r in range(header_row + 1, sheet.nrows):
        row = sheet.row(r)
        title = _text(row[c_title])
        if not title:
            continue  # a row with no local title is not a film

        distributor = _text(row[c_dist]) if c_dist is not None else ""
        if _DATE_LIKE.match(distributor):
            distributor = ""  # corrupted cell in a handful of older rows
        # a distributor cell must be text; a numeric/date cell here is corrupt
        elif c_dist is not None and row[c_dist].ctype not in (
            xlrd.XL_CELL_TEXT,
            xlrd.XL_CELL_EMPTY,
            xlrd.XL_CELL_BLANK,
        ):
            distributor = ""

        rows.append(
            {
                "title": title,
                "ov_title": (_text(row[c_ov]) or None) if c_ov is not None else None,
                "distributor": distributor or None,
                "release": _release(row[c_release], dm) if c_release is not None else None,
                "gross": _num(row[c_gross]) if c_gross is not None else None,
                "admissions": _num(row[c_adm]) if c_adm is not None else None,
            }
        )
    return rows


if __name__ == "__main__":
    import sys

    recs = parse_xls(sys.argv[1])
    print(f"{len(recs)} records")
    for rec in recs[:3]:
        print(" ", rec)
