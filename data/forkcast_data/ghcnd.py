"""Weather stations' own daily records (NOAA GHCN-Daily), the truth `verify` measures against.

The climate is built from gridded data (ERA5-Land, CRU, CPC), so testing it
against more gridded data only compares datasets. GHCN-Daily is the stations
themselves: each one's daily maximum, minimum and rain, at a known place and
height, which is what a rider meets.

- download ghcnd: the station list and the yearly files of every station's
  records (by_year/<year>.csv.gz, ~175 MB each) for YEARS, into cache/ghcnd/.
- build stations: the stations with nearly complete highs, lows and rain over
  YEARS (≥ MIN_COVERAGE of days, quality flags clear), thinned to at most
  PER_BOX per 2° box so dense networks (the US, Europe) don't swamp the rest,
  into cache/ghcnd/stations.npz: id, lat, lon, elevation (m) and
  tmax, tmin (°C), prcp (mm) as (day, station), NaN where missing. Each
  station gets a fold, 0 or 1, at random: a change to how the numbers are
  made is tuned on fold 0 and judged on fold 1.

Data: Menne, M.J. et al. (2012), Global Historical Climatology Network - Daily
(GHCN-Daily), Version 3, NOAA National Centers for Environmental Information.
Public domain.
"""

from __future__ import annotations

import gzip
import sys
from pathlib import Path

import numpy as np

from . import pipeline
from .pipeline import CACHE, Stamp, code_hash, ensure, http_get, log

DIR = CACHE / "ghcnd"
SERVER = "https://www.ncei.noaa.gov/pub/data/ghcn/daily/"
YEARS = range(2011, 2026)
STATIONS = DIR / "ghcnd-stations.txt"
OUT = DIR / "stations.npz"
ELEMENTS = ("TMAX", "TMIN", "PRCP")
MIN_COVERAGE = 0.8  # share of days each element must have
PER_BOX = 2  # stations kept per 2° × 2° box
SEED = 1


def year_file(y: int) -> Path:
    return DIR / f"{y}.csv.gz"


def files() -> list[Path]:
    return [STATIONS] + [year_file(y) for y in YEARS]


def _check_stations(path: Path) -> None:
    n = sum(1 for _ in path.open())
    if n < 100_000:
        raise ValueError(f"{n} stations, expected over 100,000")


def _check_year(y: int):
    def validate(path: Path) -> None:
        with gzip.open(path, "rt") as f:
            first = f.readline().split(",")
        if len(first) < 7 or not first[1].startswith(str(y)):
            raise ValueError(f"not a {y} GHCN-Daily file: {first[:3]}")
        with gzip.open(path, "rb") as f:  # the whole file decompresses: not truncated
            while f.read(1 << 24):
                pass

    return validate


def download(fresh: bool = False) -> None:
    log("  " + ensure(STATIONS, lambda to: http_get(SERVER + STATIONS.name, to), _check_stations, fresh))
    for y in YEARS:
        log("  " + ensure(year_file(y), lambda to, y=y: http_get(f"{SERVER}by_year/{y}.csv.gz", to, timeout=3600), _check_year(y), fresh))


def parse_stations(text: str) -> dict[str, tuple[float, float, float]]:
    """{id: (lat, lon, elevation m)} from ghcnd-stations.txt (fixed columns)."""
    out = {}
    for line in text.splitlines():
        if len(line) < 37:
            continue
        try:
            out[line[0:11]] = (float(line[12:20]), float(line[21:30]), float(line[31:37]))
        except ValueError:
            continue
    return out


def _read_year(y: int, keep: set[str] | None) -> dict[str, dict[str, np.ndarray]]:
    """{element: {station: values for each day of the year}} from a by_year file, quality-flagged values left out."""
    import pandas as pd

    days = (np.datetime64(f"{y + 1}-01-01") - np.datetime64(f"{y}-01-01")).astype(int)
    out: dict[str, dict[str, np.ndarray]] = {k: {} for k in ELEMENTS}
    cols = ["id", "date", "element", "value", "mflag", "qflag", "sflag", "time"]
    for chunk in pd.read_csv(year_file(y), names=cols, usecols=range(6), dtype={"id": str, "date": str, "element": str, "value": float, "mflag": str, "qflag": str}, chunksize=5_000_000):
        chunk = chunk[chunk["element"].isin(ELEMENTS) & chunk["qflag"].isna()]
        if keep is not None:
            chunk = chunk[chunk["id"].isin(keep)]
        day = (pd.to_datetime(chunk["date"], format="%Y%m%d").values.astype("datetime64[D]") - np.datetime64(f"{y}-01-01")).astype(int)
        chunk = chunk.assign(day=day)
        for (el, sid), g in chunk.groupby(["element", "id"]):
            a = out[el].setdefault(sid, np.full(days, np.nan, dtype=np.float32))
            a[g["day"].values] = g["value"].values / 10.0  # tenths of °C, tenths of mm
    return out


def build(fresh: bool = False) -> None:
    code = code_hash(sys.modules[__name__], pipeline)
    stamp = Stamp("stations", files(), [OUT], code, {"min_coverage": MIN_COVERAGE, "per_box": PER_BOX})
    if not fresh and stamp.up_to_date():
        log("  stations are up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing {missing[0].relative_to(pipeline.ROOT)}. Run: download ghcnd")
    meta = parse_stations(STATIONS.read_text())
    # Pass 1: how many good days each station has, per element.
    count: dict[str, dict[str, int]] = {k: {} for k in ELEMENTS}
    total = 0
    for y in YEARS:
        year = _read_year(y, None)
        total += (np.datetime64(f"{y + 1}-01-01") - np.datetime64(f"{y}-01-01")).astype(int)
        for el, by in year.items():
            for sid, a in by.items():
                count[el][sid] = count[el].get(sid, 0) + int(np.isfinite(a).sum())
        log(f"  counted {y}")
    good = [s for s in count["TMAX"] if s in meta and all(count[el].get(s, 0) >= MIN_COVERAGE * total for el in ELEMENTS)]
    log(f"  {len(good)} stations with ≥ {MIN_COVERAGE:.0%} of days of highs, lows and rain")
    # Thin to PER_BOX per 2° box, at random.
    rng = np.random.default_rng(SEED)
    rng.shuffle(good)
    per: dict[tuple[int, int], int] = {}
    kept = []
    for s in good:
        lat, lon, _ = meta[s]
        box = (int(np.floor(lat / 2)), int(np.floor(lon / 2)))
        if per.get(box, 0) < PER_BOX:
            per[box] = per.get(box, 0) + 1
            kept.append(s)
    kept.sort()
    log(f"  {len(kept)} kept, at most {PER_BOX} per 2° box")
    # Pass 2: their records.
    series = {el: [] for el in ELEMENTS}
    for y in YEARS:
        year = _read_year(y, set(kept))
        days = (np.datetime64(f"{y + 1}-01-01") - np.datetime64(f"{y}-01-01")).astype(int)
        for el in ELEMENTS:
            series[el].append(np.stack([year[el].get(s, np.full(days, np.nan, dtype=np.float32)) for s in kept], axis=1))
        log(f"  read {y}")
    folds = rng.integers(0, 2, len(kept))
    DIR.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_name(OUT.stem + ".part.npz")
    np.savez_compressed(
        tmp,
        id=np.array(kept),
        lat=np.array([meta[s][0] for s in kept]),
        lon=np.array([meta[s][1] for s in kept]),
        elev=np.array([meta[s][2] for s in kept]),
        fold=folds,
        first=np.datetime64(f"{YEARS[0]}-01-01"),
        **{el.lower(): np.concatenate(series[el]) for el in ELEMENTS},
    )
    tmp.replace(OUT)
    stamp.done()
