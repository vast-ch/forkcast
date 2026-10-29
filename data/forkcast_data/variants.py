"""Climate variants: the other climates a rider can switch the app to.

The app's climate is the average of 2011–2025 (cache/grids/<continent>/climate.bin).
This step builds four more grids per continent, each that grid plus a
correction, in the same format:

  last10, last5   the last 10 or 5 years of the period: the correction is the
                  window's average minus the period's
  elnino, lanina  months in an El Niño or La Niña event: the correction is how
                  far those months departed from the warming trend, measured
                  over HISTORY (1981–2025, about 13 events of each)

ENSO months come from NOAA's Oceanic Niño Index (the `oni` download): a month
is El Niño (La Niña) when it lies in a run of at least 5 overlapping seasons at
≥ +0.5 °C (≤ −0.5 °C). The trend is removed per cell and month first, or
"El Niño" would mostly show which events happen to be recent. Averaging 10–15
events still leaves weather noise, so an ENSO correction is kept only where it
beats random sets of as many years: in full where it is larger than 90 % of
them, fading to nothing at 75 %. Then it is smoothed over 3 × 3 cells.

Corrections are applied as: highs and lows + °C; rain × a ratio (so a dry
month can't go below zero); rainy days + days, kept within the month and
with r10 ≤ r5 ≤ r1. Where nothing changes, a variant equals the 2011–2025 grid
byte for byte.

- download oni: cache/variants/oni.txt.
- build years: each year's monthly fields (highs and lows as the warmest and
  coldest hour of the month's average day, rain, rainy days at 1/5/10 mm) into
  cache/variants/<year>.npz (float16, ~110 MB a year, ~10 s each), one stamp
  per year, so only years whose input or extraction code changed run again.
- build variants: cache/grids/<continent>/climate-<variant>.bin and .json
  (monthly; the pack step publishes them, pack.py). Checks the
  result against known ENSO effects and plausible ranges (`check`) and stops
  if it looks wrong.

Why these variants (and not others) is in docs/climate-variants.md;
variants_research.py measures them.
"""

from __future__ import annotations

import hashlib
import inspect
import json
import sys
from pathlib import Path

import numpy as np

from . import continents, pipeline
from . import era5land as e
from . import era5land_download as dl
from .continents import CONTINENTS
from .pipeline import CACHE, Stamp, code_hash, ensure, http_get, log

DIR = CACHE / "variants"
ONI_URL = "https://www.cpc.ncep.noaa.gov/data/indices/oni.ascii.txt"
ONI_FILE = DIR / "oni.txt"
HISTORY = (1981, 2025)  # years the ENSO corrections are measured over
SEASONS = ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]  # centred on Jan … Dec
FIELDS = e.LAYERS  # tmx tmn pre r1 r5 r10
MONTH_DAYS = np.array([31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31], dtype=np.float32)

VARIANTS = ["last10", "last5", "elnino", "lanina"]
ENSO = {"elnino": 1, "lanina": -1}
RANDOM_SETS = 100
SEED = 1
MIN_YEARS = 2  # an ENSO month seen in fewer years gets no correction
KEEP = (75, 90)  # percentiles of the random sets between which a correction fades in
RATIO = (0.5, 2.0)  # limits of a rain correction
MIN_RAIN = 1.0  # mm a month; drier cell-months keep their rain


def year_file(y: int) -> Path:
    return DIR / f"{y}.npz"


def history_years(app: tuple[int, int]) -> range:
    """The app's period and HISTORY: every year the variants are made from."""
    return range(min(HISTORY[0], app[0]), max(HISTORY[1], app[1]) + 1)


def windows(app: tuple[int, int]) -> dict[str, list[int]]:
    return {"last10": list(range(app[1] - 9, app[1] + 1)), "last5": list(range(app[1] - 4, app[1] + 1))}


def grid_file(cid: str, variant: str, ext: str) -> Path:
    return e.GRIDS / cid / f"climate-{variant}.{ext}"


# --- ONI -----------------------------------------------------------------------


def parse_oni(text: str) -> dict[tuple[int, int], float]:
    """{(year, month 0–11): anomaly} from NOAA's oni.ascii.txt (SEAS YR TOTAL ANOM)."""
    out = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 4 and parts[0] in SEASONS:
            out[(int(parts[1]), SEASONS.index(parts[0]))] = float(parts[3])
    return out


def _check_oni(path: Path) -> None:
    oni = parse_oni(path.read_text())
    if (HISTORY[0], 0) not in oni or (HISTORY[1], 11) not in oni:
        raise ValueError(f"{len(oni)} months of ONI, not covering {HISTORY[0]}–{HISTORY[1]}")


def enso_months(oni: dict[tuple[int, int], float], sign: int, strong: bool = False) -> set[tuple[int, int]]:
    """Months in an El Niño (sign +1) or La Niña (−1) event: ≥ 5 seasons in a row past ±0.5.

    `strong` keeps only the event months that are themselves past ±1.0.
    """
    out: set[tuple[int, int]] = set()
    run: list[tuple[int, int]] = []
    for ym in [*sorted(oni), None]:
        if ym is not None and sign * oni[ym] >= 0.5 and (not run or _next(run[-1]) == ym):
            run.append(ym)
            continue
        if len(run) >= 5:
            out.update(m for m in run if not strong or sign * oni[m] >= 1.0)
        run = [ym] if ym is not None and sign * oni[ym] >= 0.5 else []
    return out


def _next(ym: tuple[int, int]) -> tuple[int, int]:
    y, m = ym
    return (y + 1, 0) if m == 11 else (y, m + 1)


def download(fresh: bool = False) -> None:
    log("  " + ensure(ONI_FILE, lambda to: http_get(ONI_URL, to), _check_oni, fresh))


# --- Years ---------------------------------------------------------------------


def _year_inputs(y: int) -> list[Path]:
    return [dl.rain_file(y), e._next_january(y), dl.temperature_file(y)]


def _fields(y: int) -> dict[str, np.ndarray]:
    """One year's monthly highs, lows, rain and rainy days, (12, lat, lon), NaN at sea."""
    tp = e._open(dl.rain_file(y))
    nxt = e._open(e._next_january(y)).isel(time=slice(0, 1))
    # 00:00 of day D is the total of D-1 (as in era5land.rain).
    mm = np.concatenate([tp.values[1:], nxt.values], axis=0) * 1000.0
    dates = np.concatenate([tp.time.values[1:], nxt.time.values]) - np.timedelta64(1, "D")
    months = dates.astype("datetime64[M]").astype(int) % 12
    land = np.isfinite(mm[0])
    f = {"pre": np.stack([np.nansum(mm[months == m], axis=0) for m in range(12)])}
    for t, key in ((1, "r1"), (5, "r5"), (10, "r10")):
        f[key] = np.stack([(mm[months == m] >= t).sum(axis=0) for m in range(12)]).astype(np.float32)
    del mm
    t = e._open(dl.temperature_file(y))
    if t.shape[1:] != land.shape:
        raise SystemExit(f"{y}: temperature grid {t.shape[1:]} differs from rain grid {land.shape}")
    tm = t.time.values.astype("datetime64[M]").astype(int) % 12
    th = t.time.values.astype("datetime64[h]").astype(int) % 24
    vals = t.values.astype(np.float32) - np.float32(273.15)
    byhour = np.full((12, 24, *vals.shape[1:]), np.nan, dtype=np.float32)
    for i in range(vals.shape[0]):
        byhour[tm[i], th[i]] = vals[i]
    f["tmx"], f["tmn"] = np.nanmax(byhour, axis=1), np.nanmin(byhour, axis=1)
    for v in f.values():
        v[:, ~land] = np.nan
    f["lat"], f["lon"] = tp.lat.values, tp.lon.values
    return f


def extract(years: range, fresh: bool = False) -> None:
    # Only the extraction code counts, so changing the rest of this module doesn't extract every year again.
    code = code_hash(e, dl, pipeline) + hashlib.sha1(inspect.getsource(_fields).encode()).hexdigest()[:12]
    for y in years:
        out = year_file(y)
        stamp = Stamp(f"variants-{y}", _year_inputs(y), [out], code)
        if not fresh and stamp.up_to_date():
            continue
        if missing := stamp.missing_inputs():
            raise SystemExit(f"Missing {missing[0].name} for {y}. Run: download era5land-rain era5land-temperature")
        f = _fields(y)
        out.parent.mkdir(parents=True, exist_ok=True)
        tmp = out.with_name(out.stem + ".part.npz")  # np.savez adds .npz to other names
        np.savez(tmp, **{k: v if k in ("lat", "lon") else v.astype(np.float16) for k, v in f.items()})
        tmp.replace(out)
        stamp.done()
        log(f"  extracted {y}")
    log(f"  {years[0]}–{years[-1]} up to date")


# --- Corrections ---------------------------------------------------------------


def residuals(a: np.ndarray, years: list[int]) -> np.ndarray:
    """Departures of (year, …) values from each point's linear trend over the years."""
    t = np.array(years, dtype=np.float32)
    t -= t.mean()
    slope = np.tensordot(t, a, axes=1) / np.float32((t * t).sum())
    return a - a.mean(axis=0) - t.reshape(-1, *[1] * (a.ndim - 1)) * slope


def keep_weight(d: np.ndarray, random: np.ndarray) -> np.ndarray:
    """How much of a composite `d` to keep, given random composites (set, …) of as many years.

    0 within the random sets' 75th percentile of |d|, 1 beyond their 90th, linear between.
    """
    lo, hi = np.percentile(np.abs(random), KEEP, axis=0)
    with np.errstate(invalid="ignore", divide="ignore"):
        return np.clip((np.abs(d) - lo) / (hi - lo), 0, 1)


def enso_correction(res: np.ndarray, sel: np.ndarray, rng: np.random.Generator, noise: dict) -> np.ndarray:
    """The mean of the selected years' residuals, kept only where it beats chance.

    `res` is (year, …) for one month, `sel` marks the event years. `noise`
    caches the random composites by their number of years, for both phases.
    """
    k = int(sel.sum())
    if k < MIN_YEARS:
        return np.zeros(res.shape[1:], dtype=np.float32)
    if k not in noise:
        noise[k] = np.stack([res[rng.choice(len(res), k, replace=False)].mean(axis=0) for _ in range(RANDOM_SETS)])
    d = res[sel].mean(axis=0)
    return e._smooth(d * keep_weight(d, noise[k])).astype(np.float32)


def apply(field: str, base: np.ndarray, d: np.ndarray, ref: np.ndarray, month: int) -> np.ndarray:
    """One month of `base` with correction `d`; `ref` is the rain `d` was measured against."""
    if field in ("tmx", "tmn"):
        return base + d
    if field == "pre":
        with np.errstate(invalid="ignore", divide="ignore"):
            ratio = np.where(ref >= MIN_RAIN, np.clip((ref + d) / ref, *RATIO), 1.0)
        return base * ratio
    return np.clip(base + d, 0, MONTH_DAYS[month])


# --- Grids ---------------------------------------------------------------------


def decode(name: str, b: np.ndarray) -> np.ndarray:
    """The inverse of era5land.encode."""
    enc = e.ENCODING[name]
    v = (b / enc["scale"]) ** 2 if enc["kind"] == "sqrt" else b / enc["scale"] + enc["offset"]
    return np.where(b == e.NODATA, np.nan, v).astype(np.float32)


class BaseGrid:
    """A continent's monthly grid of the app's period (era5land.grid_file)."""

    def __init__(self, cid: str):
        self.header = h = json.loads(e.grid_file(cid, "json").read_text())
        n = len(h["vars"]) * 12 * h["rows"] * h["cols"]
        raw = np.frombuffer(e.grid_file(cid, "bin").read_bytes(), dtype=np.uint8)
        self.layers = dict(zip(h["vars"], raw[:n].reshape(len(h["vars"]), 12, h["rows"], h["cols"]), strict=True))
        self.static = raw[n:]

    def field(self, name: str) -> np.ndarray:
        return decode(name, self.layers[name])


def boxes(lat: np.ndarray, lon: np.ndarray) -> dict[str, tuple[slice, slice]]:
    """Each continent's rows and columns of the world grid, cut as the climate build cuts them."""
    out = {}
    for c in CONTINENTS:
        x0, ya, x1, yb = c["bbox"]
        r = np.where((lat >= ya) & (lat <= yb))[0]
        k = np.where((lon >= x0) & (lon <= x1))[0]
        out[c["id"]] = (slice(int(r[0]), int(r[-1]) + 1), slice(int(k[0]), int(k[-1]) + 1))
    return out


def outputs() -> list[Path]:
    return [grid_file(c["id"], v, x) for c in CONTINENTS for v in VARIANTS for x in ("bin", "json")]


def inputs(app: tuple[int, int]) -> list[Path]:
    files = [year_file(y) for y in history_years(app)] + [ONI_FILE]
    return files + [e.grid_file(c["id"], x) for c in CONTINENTS for x in ("bin", "json")]


def build(app: tuple[int, int], fresh: bool = False) -> None:
    code = code_hash(sys.modules[__name__], e, continents, pipeline)
    stamp = Stamp("variants", inputs(app), outputs(), code, {"years": list(app), "history": list(HISTORY)})
    if not fresh and stamp.up_to_date():
        log("  climate variants are up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing {missing[0].relative_to(pipeline.ROOT)}. Run: download oni, build climate, build years")
    years = history_years(app)
    months = {v: enso_months(parse_oni(ONI_FILE.read_text()), s) for v, s in ENSO.items()}
    picks = {v: np.array([y in ys for y in years]) for v, ys in windows(app).items()}
    picks |= {v: np.array([[(y, m) in ms for m in range(12)] for y in years]) for v, ms in months.items()}
    is_app = np.array([app[0] <= y <= app[1] for y in years])
    z = np.load(year_file(years[0]))
    lat, lon = z["lat"], z["lon"]
    cut = boxes(lat, lon)
    bases = {cid: BaseGrid(cid) for cid in cut}
    for cid, (rs, cs) in cut.items():
        h = bases[cid].header
        if (rs.stop - rs.start, cs.stop - cs.start) != (h["rows"], h["cols"]):
            raise SystemExit(f"{cid}: climate.bin is {h['rows']}x{h['cols']}, the extracted years' cut differs. Rebuild climate.")
    regions = {cid: {n: _region(box, lat[rs], lon[cs]) for n, (box, c) in REGIONS.items() if c == cid} for cid, (rs, cs) in cut.items()}
    quirks = {cid: {n: _region(box, lat[rs], lon[cs]) for n, (box, c, _) in QUIRKS.items() if c == cid} for cid, (rs, cs) in cut.items()}
    usual = {cid: _outside(quirks[cid].values(), (rs.stop - rs.start, cs.stop - cs.start)) for cid, (rs, cs) in cut.items()}
    layers = {(v, cid): {} for v in VARIANTS for cid in cut}  # encoded, per field
    stats: dict = {}  # what `check` needs of the corrections
    for field in FIELDS:
        a16 = np.stack([np.load(year_file(y))[field] for y in years])  # (year, month, lat, lon)
        for cid, (rs, cs) in cut.items():
            base = bases[cid].field(field)
            out = {v: np.empty_like(base) for v in VARIANTS}
            for m in range(12):
                raw = a16[:, m, rs, cs].astype(np.float32)
                res = residuals(raw, years)
                rng = np.random.default_rng([SEED, m])
                noise: dict = {}
                for v, pick in picks.items():
                    if v in ENSO:
                        d, ref = enso_correction(res, pick[:, m], rng, noise), raw.mean(axis=0)
                    else:
                        ref = raw[is_app].mean(axis=0)
                        d = raw[pick].mean(axis=0) - ref
                    out[v][m] = apply(field, base[m], d, ref, m)
                    stats[(v, cid, field, m)] = (float(np.nanmean(d)), _largest(d[usual[cid]]))
                    for name, at in regions[cid].items():
                        stats[(v, name, field, m)] = float(np.nanmean(d[at]))
                    for name, at in quirks[cid].items():
                        stats[(v, name, field, m)] = _largest(d[at])
            for v in VARIANTS:
                layers[(v, cid)][field] = e.encode(field, out[v])
        log(f"  {field}")
        del a16
    check(stats, list(cut))
    for (v, cid), enc in layers.items():
        # Rainy days share one encoding, so r10 ≤ r5 ≤ r1 can be kept on the bytes (sea is 255 in all three).
        enc["r5"] = np.minimum(enc["r5"], enc["r1"])
        enc["r10"] = np.minimum(enc["r10"], enc["r5"])
        b = bases[cid]
        _write(grid_file(cid, v, "bin"), np.stack([enc[k] for k in b.header["vars"]]).tobytes() + b.static.tobytes())
        # "years" stays the period the grid is a correction of; what was averaged is added.
        h = dict(b.header, variant=v)
        if v in ENSO:
            h["enso"] = {"years": list(HISTORY), "months": len(months[v])}
        else:
            h["window"] = [windows(app)[v][0], app[1]]
        _write(grid_file(cid, v, "json"), json.dumps(h, separators=(",", ":")).encode())
    for v in VARIANTS:
        changed = np.mean([(layers[(v, cid)]["tmx"] != bases[cid].layers["tmx"]).mean() for cid in cut])
        log(f"  {v:7} highs differ from {app[0]}–{app[1]} in {changed:.0%} of cell-months")
    stamp.done()


def _largest(d: np.ndarray) -> float:
    return float(np.nanmax(np.abs(d), initial=0))


def _outside(regions, shape: tuple[int, int]) -> np.ndarray:
    """True for the cells of a continent outside every one of `regions`."""
    out = np.ones(shape, dtype=bool)
    for at in regions:
        out[at] = False
    return out


def _region(box: tuple[float, float, float, float], lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
    x0, y0, x1, y1 = box
    return np.ix_((lat >= y0) & (lat <= y1), (lon >= x0) & (lon <= x1))


def _write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".part")
    tmp.write_bytes(data)
    tmp.replace(path)


# --- Checks --------------------------------------------------------------------

# Well-established ENSO effects (NOAA CPC, Australia's BoM), as (variant,
# region, field, months 0–11, sign of the mean correction there). A sign,
# month or region mix-up anywhere in the chain flips some of them.
KNOWN = [
    ("elnino", "eastern Australia", "pre", [8, 9, 10], -1),  # dry spring
    ("lanina", "eastern Australia", "pre", [8, 9, 10], +1),
    ("elnino", "northern South America", "pre", [11, 0, 1], -1),  # dry Amazon and Colombia
    ("lanina", "northern South America", "pre", [11, 0, 1], +1),
    ("elnino", "southern Africa", "pre", [11, 0, 1], -1),  # weak summer rains
    ("elnino", "western Canada", "tmx", [11, 0, 1], +1),  # mild winter
    ("lanina", "western Canada", "tmx", [11, 0, 1], -1),
    ("elnino", "southern US", "pre", [11, 0, 1], +1),  # wet winter along the Gulf
]
REGIONS = {  # (lon_min, lat_min, lon_max, lat_max), continent
    "eastern Australia": ((140, -38, 154, -20), "oceania"),
    "northern South America": ((-75, -10, -50, 8), "south-america"),
    "southern Africa": ((20, -30, 35, -15), "africa"),
    "western Canada": ((-125, 49, -105, 60), "north-america"),
    "southern US": ((-98, 26, -80, 34), "north-america"),
}
# A continent's mean change in highs per variant, °C: windows show the warming, phases average out.
MEAN_TMX = {"last10": (-0.3, 0.8), "last5": (-0.5, 1.2), "elnino": (-0.4, 0.4), "lanina": (-0.4, 0.4)}
MAX_TEMP = 6.0  # no cell's highs or lows may move further, °C (except in QUIRKS)
# Known flaws of the source data, with their own limit, °C. On the Tibetan
# Plateau, ERA5-Land's winter highs and lows jump by up to 14 °C from 2021 on
# (e.g. 31.5° N 100.75° E, January lows about −25 °C until 2020, −11 °C after),
# most likely its snow cover; so the last 5 years warm it by up to ~7.5 °C.
QUIRKS = {"Tibetan Plateau": ((84, 27, 104, 36), "asia", 10.0)}


def check(stats: dict, cids: list[str]) -> None:
    """Stop the build if the corrections contradict known ENSO effects or are implausibly large."""
    problems = []
    for v, region, field, ms, sign in KNOWN:
        mean = float(np.mean([stats[(v, region, field, m)] for m in ms]))
        if not sign * mean > 0:
            problems.append(f"{v} in {region}: mean {field} correction {mean:+.2f}, expected {'more' if sign > 0 else 'less'}")
    for cid in cids:
        for v, (lo, hi) in MEAN_TMX.items():
            mean = float(np.mean([stats[(v, cid, "tmx", m)][0] for m in range(12)]))
            if not lo <= mean <= hi:
                problems.append(f"{v} in {cid}: mean change in highs {mean:+.2f} °C, outside {lo}…{hi}")
            worst = max(stats[(v, cid, f, m)][1] for f in ("tmx", "tmn") for m in range(12))
            if worst > MAX_TEMP:
                problems.append(f"{v} in {cid}: highs or lows move by up to {worst:.1f} °C")
    for name, (_, cid, limit) in QUIRKS.items():
        if cid not in cids:
            continue
        for v in VARIANTS:
            worst = max(stats[(v, name, f, m)] for f in ("tmx", "tmn") for m in range(12))
            if worst > limit:
                problems.append(f"{v} on the {name}: highs or lows move by up to {worst:.1f} °C")
    if problems:
        raise SystemExit("Climate variants failed their checks:\n  " + "\n  ".join(problems))
    log(f"  checks passed: {len(KNOWN)} known ENSO effects, temperature ranges on {len(cids)} continents")
