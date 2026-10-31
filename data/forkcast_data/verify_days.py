"""Measurements against single real days: does what the app says about a day or a trip hold?

Part of `build verify` (verify.py), for what needs daily data: NOAA CPC's
station-based daily highs and lows, and ERA5-Land's daily rain, 2011–2025.

The sample: PLACES random land cells over the world (and EUROPE_PLACES more
in Europe), drawn with a chance proportional to their area, among those where
CPC has data. At each place the app's curves (last15, packed as the app gets
them) are evaluated for every day of 2011–2025 and TRIPS random trips of 7 to
60 days are taken. Places are the sample unit for intervals: a place's days
and trips share its weather, but random places are far apart. Each share
gets a 95 % interval by resampling the places (bootstrap).

- range: does the usual range (mean ± 1.28 spreads) hold 8 in 10 of the
  station highs and lows? The share below it and above it (10 % each, if
  right), and how far the station days' average is from ours (bias).
  The spread itself was measured on these same CPC days (cpc.py), so this
  checks the shape (are days normal enough?) and our averages against the
  stations', not the spread on unseen data.
- extremes: does half of real trips get a lower lowest low than the app's
  "lowest low, likely" (and a higher highest high)? Also with every day
  counted as its own try, to show what the spells change.
- rainy: does the rainy-day range hold 8 trips in 10 (10 % below, 10 % above),
  at each threshold, and how far is the expected count from the real one?

likely_extreme and rainy_days_range are the app's (web/app/utils/itinerary.ts),
ported; tests pin both to the same values as the app's tests.
"""

from __future__ import annotations

import math

import numpy as np

from . import cpc, pack, variants
from . import era5land as e
from . import era5land_download as dl

YEARS = range(2011, 2026)
PLACES = 1000
EUROPE_PLACES = 300
TRIPS = 20  # per place
TRIP_DAYS = (7, 60)
SEED = 1
BOOTSTRAP = 2000
USUAL_Z = 1.2816  # the app's: 8 days in 10 within ± this many spreads
EXTREME_SPELL = {"lowest": 2.0, "highest": 2.5}  # the app's
SPELL_FACTOR = {1: 2.0, 5: 1.6, 10: 1.5}  # the app's
RANGE_TAIL = 0.1  # the app's
THRESHOLDS = (1, 5, 10)
ALPS = (5.0, 44.0, 16.0, 48.5)  # lon_min, lat_min, lon_max, lat_max
WINTER = (11, 0, 1)  # Dec, Jan, Feb


# --- The app's formulas ----------------------------------------------------------


def _cdf(z: float) -> float:
    return 0.5 * (1 + math.erf(z / math.sqrt(2)))


def likely_extreme(days: list[tuple[float, float]], side: str, spell: float | None = None) -> float:
    """The app's likelyExtreme: the lowest (highest) value a trip is as likely to beat as not."""
    known = [(m, s) for m, s in days if not math.isnan(m) and s > 0]
    if not known:
        return math.nan
    sign = -1 if side == "lowest" else 1
    target = min(EXTREME_SPELL[side] if spell is None else spell, len(known)) * math.log(0.5)

    def log_mild(x: float) -> float:
        return sum(math.log(max(1e-300, _cdf((x - sign * m) / s))) for m, s in known)

    lo = min(sign * m - 6 * s for m, s in known)
    hi = max(sign * m + 6 * s for m, s in known)
    for _ in range(50):
        mid = (lo + hi) / 2
        if log_mild(mid) < target:
            lo = mid
        else:
            hi = mid
    return sign * (lo + hi) / 2


def rainy_days_range(chances: list[float], threshold: int) -> tuple[int, int]:
    """The app's rainyDaysRange: the fewest and most rainy days in 8 trips out of 10."""
    n = len(chances)
    p = sum(chances) / (n or 1)
    if n == 0 or p <= 0:
        return 0, 0
    if p >= 1:
        return n, n
    independent = sum(c * (1 - c) for c in chances)
    target = SPELL_FACTOR.get(threshold, 2.0) * independent
    rho = max(0.0, (target / (n * p * (1 - p)) - 1) / (n - 1)) if n > 1 else 0.0
    pmf = [0.0] * (n + 1)
    if rho < 1e-9:
        pmf[0] = (1 - p) ** n
        for k in range(n):
            pmf[k + 1] = pmf[k] * (n - k) * p / ((k + 1) * (1 - p))
    else:
        a, b = p * (1 / rho - 1), (1 - p) * (1 / rho - 1)
        pmf[0] = 1.0
        for i in range(n):
            pmf[0] *= (b + i) / (a + b + i)
        for k in range(n):
            pmf[k + 1] = pmf[k] * (n - k) * (a + k) / ((k + 1) * (b + n - k - 1))
    low, high, total = 0, n, 0.0
    for k in range(n + 1):
        before = total
        total += pmf[k]
        if before < RANGE_TAIL <= total:
            low = k
        if before < 1 - RANGE_TAIL <= total:
            high = k
    return low, high


# --- Data at the places ----------------------------------------------------------


def dates() -> np.ndarray:
    return np.arange(np.datetime64(f"{YEARS[0]}-01-01"), np.datetime64(f"{YEARS[-1] + 1}-01-01"))


def phases(d: np.ndarray) -> np.ndarray:
    """The app's phaseOfDate for each day: how far through its year it starts."""
    years = d.astype("datetime64[Y]")
    length = ((years + 1).astype("datetime64[D]") - years.astype("datetime64[D]")).astype(float)
    return (d - years.astype("datetime64[D]")).astype(float) / length


def pick_places(land: np.ndarray, lat: np.ndarray, lon: np.ndarray, has_cpc: np.ndarray) -> dict[str, tuple[np.ndarray, np.ndarray]]:
    """Random land cells with station data, by area: the world's and Europe's, (rows, cols) each."""
    rng = np.random.default_rng(SEED)
    ok = land & has_cpc
    w = np.where(ok, np.cos(np.radians(lat))[:, None], 0.0)
    out = {}
    for area, n, box in (("World", PLACES, None), ("Europe", EUROPE_PLACES, variants.AREAS["Europe"])):
        ww = w.copy()
        if box is not None:
            x0, y0, x1, y1 = box
            ww *= ((lat >= y0) & (lat <= y1))[:, None] & ((lon >= x0) & (lon <= x1))[None, :]
        flat = rng.choice(ww.size, n, replace=False, p=(ww / ww.sum()).ravel())
        out[area] = np.unravel_index(flat, ww.shape)
    return out


def cpc_has_data(lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
    """Which of our cells have a CPC cell with data (from one summer day)."""
    import xarray as xr

    with xr.open_dataset(cpc.file("tmax", YEARS[0])) as ds:
        day = ds["tmax"].isel(time=200).values  # (360, 720), 89.75 … −89.75, 0.25 … 359.75
    r, c = _cpc_index(lat, lon)
    return np.isfinite(day[np.ix_(r, c)])


def _cpc_index(lat: np.ndarray, lon: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    r = np.clip(np.floor((90 - lat) / 0.5).astype(int), 0, 359)
    c = np.floor((np.mod(lon, 360)) / 0.5).astype(int) % 720
    return r, c


def cpc_days(kind: str, lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
    """CPC's daily highs or lows at points, (day, point), over YEARS."""
    import xarray as xr

    r, c = _cpc_index(lat, lon)
    out = []
    for y in YEARS:
        with xr.open_dataset(cpc.file(kind, y)) as ds:
            a = ds[kind].values  # (days, 360, 720)
        out.append(a[:, r, c])
    return np.concatenate(out).astype(np.float32)


def rain_days(rows: np.ndarray, cols: np.ndarray) -> np.ndarray:
    """ERA5-Land's daily rain at cells, mm, (day, point), over YEARS; the last day NaN (its total is in the next year's file)."""
    out = []
    for y in YEARS:
        a = e._open(dl.rain_file(y)).values  # (days, rows, cols); 00:00 of day D holds D−1's total
        out.append(a[:, rows, cols] * 1000.0)
    tp = np.concatenate(out)
    mm = np.full_like(tp, np.nan)
    mm[:-1] = tp[1:]
    return mm.astype(np.float32)


def curves_at(coef: dict[str, np.ndarray], rows: np.ndarray, cols: np.ndarray, ph: np.ndarray) -> dict[str, np.ndarray]:
    """The app's curves at cells and days, (day, point): packed and decoded, as the app gets them."""
    out = {}
    for name, c in coef.items():
        packed = pack.decode(name, pack.encode(name, c[:, rows, cols]))
        v = pack.evaluate(packed, ph)
        out[name] = np.clip(v, 0, 1) if name in ("r1", "r5", "r10") else v
    return out


# --- Measurements -------------------------------------------------------------------


def _interval(per_place: np.ndarray, rng: np.random.Generator) -> tuple[float, float]:
    """95 % interval of the mean over places, by resampling them."""
    v = per_place[np.isfinite(per_place)]
    means = v[rng.integers(0, len(v), (BOOTSTRAP, len(v)))].mean(axis=1)
    lo, hi = np.percentile(means, [2.5, 97.5])
    return float(lo), float(hi)


def _rows(metric: str, field: str, area: str, stat: str, per_place: np.ndarray, unit: str, rng) -> list[dict]:
    """A measurement averaged over places, with its interval."""
    lo, hi = _interval(per_place, rng)
    common = {"metric": metric, "climate": "last15", "field": field, "area": area, "unit": unit}
    return [
        common | {"stat": stat, "value": float(np.nanmean(per_place))},
        common | {"stat": f"{stat} lo95", "value": lo},
        common | {"stat": f"{stat} hi95", "value": hi},
    ]


def trips(n_days: int, n_places: int, rng: np.random.Generator) -> list[tuple[int, int, int]]:
    """(place, first day, length) of TRIPS random trips per place."""
    out = []
    for p in range(n_places):
        for _ in range(TRIPS):
            length = int(rng.integers(TRIP_DAYS[0], TRIP_DAYS[1] + 1))
            out.append((p, int(rng.integers(0, n_days - length - 1)), length))
    return out


def measure(base: variants.BaseGrid) -> list[dict]:
    h = base.header
    lat = h["lat0"] - np.arange(h["rows"]) * h["step"]
    lon = h["lon0"] + np.arange(h["cols"]) * h["step"]
    coef, _ = pack.curves(e.grid_file("bin").read_bytes(), h)
    land = ~np.isnan(coef["tmx"][0])
    coef |= pack.spread(land)
    places = pick_places(land, lat, lon, cpc_has_data(lat, lon))
    d = dates()
    ph = phases(d)
    rng = np.random.default_rng(SEED)
    rows: list[dict] = []
    for area, (r, c) in places.items():
        at = curves_at(coef, r, c, ph)
        station = {"tmx": cpc_days("tmax", lat[r], lon[c]), "tmn": cpc_days("tmin", lat[r], lon[c])}
        rain = rain_days(r, c)
        rows += _range(area, at, station, rng)
        rows += _bias_alps(area, at, station, lat[r], lon[c], d, rng)
        rows += _trips(area, at, station, rain, len(d), rng)
        rows.append({"metric": "sample", "climate": "", "field": "", "area": area, "stat": "places", "value": float(len(r)), "unit": "places"})
    rows.append({"metric": "sample", "climate": "", "field": "", "area": "", "stat": "trips per place", "value": float(TRIPS), "unit": "trips"})
    return rows


def _range(area: str, at: dict, station: dict, rng) -> list[dict]:
    rows = []
    for field, sd in (("tmx", "tmxsd"), ("tmn", "tmnsd")):
        mean, spread, real = at[field], at[sd], station[field]
        ok = np.isfinite(real) & np.isfinite(mean) & np.isfinite(spread)
        below = np.where(ok, real < mean - USUAL_Z * spread, np.nan)
        above = np.where(ok, real > mean + USUAL_Z * spread, np.nan)
        rows += _rows("range", field, area, "below", np.nanmean(below, axis=0), "share", rng)
        rows += _rows("range", field, area, "above", np.nanmean(above, axis=0), "share", rng)
        rows += _rows("range", field, area, "bias", np.nanmean(np.where(ok, real - mean, np.nan), axis=0), "°C", rng)
    return rows


def _bias_alps(area: str, at: dict, station: dict, plat: np.ndarray, plon: np.ndarray, d: np.ndarray, rng) -> list[dict]:
    """Our winter highs and lows against the stations' in the Alps (Europe's sample only)."""
    if area != "Europe":
        return []
    x0, y0, x1, y1 = ALPS
    inside = (plat >= y0) & (plat <= y1) & (plon >= x0) & (plon <= x1)
    winter = np.isin(d.astype("datetime64[M]").astype(int) % 12, WINTER)
    rows = []
    for field in ("tmx", "tmn"):
        diff = (station[field] - at[field])[winter][:, inside]
        rows += _rows("winter-bias", field, "Alps", "bias", np.nanmean(diff, axis=0), "°C", rng)
    rows.append({"metric": "sample", "climate": "", "field": "", "area": "Alps", "stat": "places", "value": float(inside.sum()), "unit": "places"})
    return rows


def _trips(area: str, at: dict, station: dict, rain: np.ndarray, n_days: int, rng) -> list[dict]:
    plan = trips(n_days, at["tmx"].shape[1], rng)
    n = at["tmx"].shape[1]
    lows = {k: np.full(n, 0.0) for k in ("spell", "every")}
    highs = {k: np.full(n, 0.0) for k in ("spell", "every")}
    counted = np.zeros(n)
    rainy = {t: {"below": np.zeros(n), "above": np.zeros(n), "diff": np.zeros(n), "n": np.zeros(n)} for t in THRESHOLDS}
    for p, start, length in plan:
        days = slice(start, start + length)
        tmn, tmx = station["tmn"][days, p], station["tmx"][days, p]
        if np.isfinite(tmn).all() and np.isfinite(tmx).all():
            nights = list(zip(at["tmn"][days, p].tolist(), at["tmnsd"][days, p].tolist(), strict=True))
            rides = list(zip(at["tmx"][days, p].tolist(), at["tmxsd"][days, p].tolist(), strict=True))
            counted[p] += 1
            lows["spell"][p] += tmn.min() < likely_extreme(nights, "lowest")
            lows["every"][p] += tmn.min() < likely_extreme(nights, "lowest", spell=1)
            highs["spell"][p] += tmx.max() > likely_extreme(rides, "highest")
            highs["every"][p] += tmx.max() > likely_extreme(rides, "highest", spell=1)
        mm = rain[days, p]
        if np.isfinite(mm).all():
            for t in THRESHOLDS:
                chances = at[f"r{t}"][days, p].tolist()
                lo, hi = rainy_days_range(chances, t)
                real = int((mm >= t).sum())
                s = rainy[t]
                s["below"][p] += real < lo
                s["above"][p] += real > hi
                s["diff"][p] += real - sum(chances)
                s["n"][p] += 1
    rows = []
    with np.errstate(invalid="ignore"):
        for k, label in (("spell", "beaten"), ("every", "beaten, every day a try")):
            rows += _rows("extremes", "tmn", area, label, lows[k] / counted, "share", rng)
            rows += _rows("extremes", "tmx", area, label, highs[k] / counted, "share", rng)
        for t, s in rainy.items():
            rows += _rows("rainy", f"r{t}", area, "below", s["below"] / s["n"], "share", rng)
            rows += _rows("rainy", f"r{t}", area, "above", s["above"] / s["n"], "share", rng)
            rows += _rows("rainy", f"r{t}", area, "real minus expected", s["diff"] / s["n"], "days", rng)
    return rows
