"""Measurements against weather stations' own records (GHCN-Daily, ghcnd.py).

Part of `build verify`. Gridded data (CPC, CRU) are themselves interpolated
between stations and disagree with each other (CPC's lows run 0.8 °C warmer
than CRU's), so the stations are the truth here: at each, the app's value is
worked out as the app does for a route point there (bilinear over the land
cells around it, then the altitude correction for the station's height
against the cells'), and compared with the station's days of 2011–2025.

The climate measured is the period's own (2011–2025, not brought forward by
warming.py), as the days are the period's; the backtest measures the shift.

- station: per station, its average high and low minus ours, as the mean and
  the mean absolute over stations: as the app has it, without the altitude
  correction (does it help?), and for lows, at the highs' seasonal rate.
- lapse: the rate the stations show, month by month (the slope of station
  minus cells against the station's height above its cells), next to the
  app's. The lows' LOW_LAPSE_RATE is this fit on fold 0, rounded;
  lapse-test is what it changes on fold 1, station by station.
- station-range, station-extremes, station-rainy: as verify_days', at the
  stations, their own days and 20 random trips each. Rain at one point is
  not a 25 km cell's average, so rainy days are expected to differ.

Each station has a fold (ghcnd.py): what is tuned is tuned on fold 0 and
reported on fold 1; the measurements here are over all stations unless the
area says "fold 1". Intervals resample stations.
"""

from __future__ import annotations

import numpy as np

from . import era5land as e
from . import ghcnd, pack, variants, verify_days

AREAS = {"World": None, "Europe": variants.AREAS["Europe"]}
LAPSE_RATES = np.array([0.0045, 0.005, 0.0058, 0.0064, 0.0067, 0.0068, 0.0068, 0.0066, 0.006, 0.0054, 0.0048, 0.0044])  # the app's, highs
LOW_LAPSE_RATE = 0.003  # the app's, lows


def lapse_rate_at(phase: np.ndarray) -> np.ndarray:
    """The app's lapseRateAt: between mid-month values, °C per m."""
    x = phase * 12 - 0.5
    m0 = np.floor(x).astype(int)
    t = x - m0
    return LAPSE_RATES[m0 % 12] + (LAPSE_RATES[(m0 + 1) % 12] - LAPSE_RATES[m0 % 12]) * t


def neighbours(header: dict, lat: np.ndarray, lon: np.ndarray, land: np.ndarray):
    """The app's bilinear interpolation: the four cells around each point and their weights, sea cells weighted 0."""
    fx = (lon - header["lon0"]) / header["step"]
    fy = (header["lat0"] - lat) / header["step"]
    c0, r0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - c0, fy - r0
    cells, weights = [], []
    for dr, dc, wgt in ((0, 0, (1 - tx) * (1 - ty)), (0, 1, tx * (1 - ty)), (1, 0, (1 - tx) * ty), (1, 1, tx * ty)):
        r = np.clip(r0 + dr, 0, header["rows"] - 1)
        c = (c0 + dc) % header["cols"]
        cells.append((r, c))
        weights.append(np.where(land[r, c], wgt, 0.0))
    total = np.sum(weights, axis=0)
    return cells, [w / np.where(total > 0, total, np.nan) for w in weights]


def at_points(values: np.ndarray, cells, weights) -> np.ndarray:
    """(…, rows, cols) → (…, points), interpolated."""
    return sum(np.nan_to_num(values[..., r, c]) * w for (r, c), w in zip(cells, weights, strict=True))


def measure(base: variants.BaseGrid) -> list[dict]:
    z = np.load(ghcnd.OUT)
    h = base.header
    coef, static = pack.curves(e.grid_file("bin").read_bytes(), h)
    land = ~np.isnan(coef["tmx"][0])
    coef |= pack.spread(land)
    elev = np.where(static[0] == e.NODATA, np.nan, static[0] / e.ENCODING["elev"]["scale"]).astype(np.float64)
    lat, lon, st_elev = z["lat"], z["lon"], z["elev"].astype(float)
    inside = (lat <= h["lat0"]) & (lat >= e.SOUTH)
    cells, weights = neighbours(h, lat, lon, land)
    ok = inside & np.isfinite(weights[0]) & (st_elev > -400)  # −999.9: height unknown
    idx = np.where(ok)[0]
    cells = [(r[idx], c[idx]) for r, c in cells]
    weights = [w[idx] for w in weights]
    d = verify_days.dates()
    ph = verify_days.phases(d)
    at = {}
    for name, c in coef.items():
        packed = pack.decode(name, pack.encode(name, c))
        cur = pack.evaluate(at_points(packed, cells, weights), ph)  # (day, station): curves are linear, so interpolate the coefficients
        at[name] = np.clip(cur, 0, 1) if name in ("r1", "r5", "r10") else cur
    cell_elev = at_points(np.nan_to_num(elev), cells, weights)
    above = st_elev[idx] - cell_elev  # m the station sits above its cells
    shift = -lapse_rate_at(ph)[:, None] * above[None, :]
    flat = {k: at[k].copy() for k in ("tmx", "tmn")}
    at["tmx"], at["tmn"] = at["tmx"] + shift, at["tmn"] - LOW_LAPSE_RATE * above[None, :]
    lows_at_highs_rate = flat["tmn"] + shift
    real = {"tmx": z["tmax"][:, idx], "tmn": z["tmin"][:, idx]}
    rain = z["prcp"][:, idx]
    rng = np.random.default_rng(verify_days.SEED)
    rows: list[dict] = []
    for area, box in AREAS.items():
        sel = np.ones(len(idx), bool) if box is None else _inside(box, lat[idx], lon[idx])
        sub = lambda a, sel=sel: a[:, sel]  # noqa: E731
        ours = {"": at, ", no altitude correction": flat, ", lows at the highs' rate": {"tmn": lows_at_highs_rate}}
        rows += _bias(area, {label: {k: sub(v) for k, v in o.items() if k in ("tmx", "tmn")} for label, o in ours.items()}, {k: sub(v) for k, v in real.items()}, rng)
        test = sel & (z["fold"][idx] == 1)
        rows += _lapse_test(area, at["tmn"][:, test], lows_at_highs_rate[:, test], real["tmn"][:, test], rng)
        rows += verify_days._range(area, {k: sub(v) for k, v in at.items()}, {k: sub(v) for k, v in real.items()}, rng, prefix="station-")
        rows += verify_days._trips(area, {k: sub(v) for k, v in at.items()}, {k: sub(v) for k, v in real.items()}, sub(rain), len(d), rng, prefix="station-")
        rows.append({"metric": "sample", "climate": "", "field": "", "area": f"{area} stations", "stat": "places", "value": float(sel.sum()), "unit": "places"})
    rows += _lapse(flat, real, above, z["fold"][idx], d)
    return rows


def _inside(box, lat, lon) -> np.ndarray:
    x0, y0, x1, y1 = box
    return (lat >= y0) & (lat <= y1) & (lon >= x0) & (lon <= x1)


def _per_station(real: np.ndarray, ours: np.ndarray) -> np.ndarray:
    """Each station's average over its days minus ours."""
    return np.nanmean(np.where(np.isfinite(real), real - ours, np.nan), axis=0)


def _bias(area: str, ours: dict[str, dict], real: dict, rng) -> list[dict]:
    """Each station's average high (low) minus ours, for each way of making ours ({label: {field: (day, station)}})."""
    rows = []
    for label, by in ours.items():
        for field, v in by.items():
            diff = _per_station(real[field], v)
            rows += verify_days._rows("station", field, area, "bias" + label, diff, "°C", rng)
            rows += verify_days._rows("station", field, area, "abs bias" + label, np.abs(diff), "°C", rng)
    return rows


def _lapse_test(area: str, ours: np.ndarray, before: np.ndarray, real: np.ndarray, rng) -> list[dict]:
    """On the fold LOW_LAPSE_RATE wasn't fitted on: how much closer each station's average low is with it than at the
    highs' rate (negative: closer), and the share of stations it brings closer."""
    change = np.abs(_per_station(real, ours)) - np.abs(_per_station(real, before))
    rows = verify_days._rows("lapse-test", "tmn", area, "abs bias change", change, "°C", rng)
    rows += verify_days._rows("lapse-test", "tmn", area, "closer", np.where(np.isfinite(change), change < 0, np.nan), "share", rng)
    rows.append({"metric": "sample", "climate": "", "field": "", "area": f"{area} stations, fold 1", "stat": "places", "value": float(np.isfinite(change).sum()), "unit": "places"})
    return rows


def _slope(x: np.ndarray, y: np.ndarray) -> float:
    """Least squares: °C per m."""
    return float(np.sum(x * (y - y.mean())) / np.sum(x * (x - x.mean())))


def _monthly(real: dict, flat: dict, field: str, months: np.ndarray, sel: np.ndarray):
    """Per month: each station's average minus its cells' (uncorrected), and which stations to fit on."""
    for m in range(12):
        diff = np.nanmean((real[field] - flat[field])[months == m], axis=0)
        yield diff, sel & np.isfinite(diff)


def _lapse(flat: dict, real: dict, above: np.ndarray, fold: np.ndarray, d: np.ndarray) -> list[dict]:
    """The lapse rate the stations show per month: how much colder (°C per 1,000 m) a station is than its cells'
    value, per metre it sits above them, by least squares over stations at least 100 m off; next to the app's."""
    months = d.astype("datetime64[M]").astype(int) % 12
    rows = []
    far = np.abs(above) >= 100
    for field in ("tmx", "tmn"):
        for m, (diff, ok) in enumerate(_monthly(real, flat, field, months, far)):
            rows.append({"metric": "lapse", "climate": "", "field": field, "area": "World stations", "stat": f"month {m + 1}", "value": -_slope(above[ok], diff[ok]) * 1000, "unit": "°C per km"})
        if field == "tmn":
            fit0 = [_slope(above[ok], diff[ok]) for diff, ok in _monthly(real, flat, field, months, far & (fold == 0))]
            rows.append({"metric": "lapse", "climate": "", "field": field, "area": "World stations, fold 0", "stat": "year", "value": -float(np.mean(fit0)) * 1000, "unit": "°C per km"})
    for m in range(12):
        rows.append({"metric": "lapse", "climate": "", "field": "app tmx", "area": "", "stat": f"month {m + 1}", "value": float(LAPSE_RATES[m] * 1000), "unit": "°C per km"})
    rows.append({"metric": "lapse", "climate": "", "field": "app tmn", "area": "", "stat": "year", "value": LOW_LAPSE_RATE * 1000, "unit": "°C per km"})
    return rows
