"""Pack the monthly climate grids into the seasonal curves the app draws.

The climate and variants builds make 12 monthly values per layer (cache/grids/,
see era5land.py). The app never uses those months directly: it turns each
cell's 12 values into a smooth seasonal curve, the yearly mean plus three
yearly waves (12-, 6- and 4-month cycles), 7 numbers. This step does that fit
here and publishes the 7 numbers instead of the 12 months: the same curves,
42% fewer bytes.

The fit (the app's, before this step moved it here): temperatures as they
are; rain as mm per day and rainy days as the share of days, each month's
total divided by its length, so months of different lengths compare fairly.
A month's average flattens each wave a little compared with its value at
mid-month (by sin(πk/12) / (πk/12) for the k-th wave), so the fitted waves are
scaled back up by that factor.

Output per climate (`last15` and each variant): out/climate/<climate>.json,
the header, and out/climate/<climate>/ with a file per 10° tile with land
(<lat>_<lon>.bin, by its south-west corner, 41 × 41 cells sharing its edges
with its neighbours). One byte per value
(255 = no data), laid out [layer][term][row][col], then the static layers
[row][col] as in the monthly grid. Terms are the mean,
then cos and sin of each wave; a layer stores as many as its encoding lists
(7, or 3 for the spread of single days' highs and lows from cpc.py, added to
every climate). The wind's components (wind.py) come last, each climate's own. Each term has its own encoding, value =
byte / scale + offset (or (byte / scale)² for "sqrt"); rain's waves are
"relative": a share of the cell's mean rain, so dry places keep their
precision.

Usage: uv run python -m forkcast_data build pack [--fresh]
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import numpy as np

from . import cpc, pipeline, variants, wind
from . import era5land as e
from .pipeline import OUT, Stamp, code_hash, log

HARMONICS = 3
TERMS = 1 + 2 * HARMONICS
MONTH_DAYS = np.array([31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31], dtype=np.float64)
PHASES = (np.arange(12) + 0.5) / 12


def _temp(low: float) -> list[dict]:
    """Highs or lows: the mean from `low` °C in 0.29 °C steps (72.6 °C of range)."""
    return [
        {"kind": "linear", "scale": 3.5, "offset": low},
        *[{"kind": "linear", "scale": 5, "offset": -38}] * 2,  # yearly wave, −38 … +12.8 °C (Siberia's winters), 0.2 °C steps
        *[{"kind": "linear", "scale": 20, "offset": -6.35}] * 4,  # shorter waves, ±6.35 °C, 0.05 °C steps
    ]


_DAYS = [
    {"kind": "linear", "scale": 254, "offset": 0},  # share of rainy days, 0 … 1
    *[{"kind": "linear", "scale": 200, "offset": -0.635}] * 6,  # ±0.635
]
_RAIN = [
    {"kind": "sqrt", "scale": 40},  # mm per day, up to 40
    # ±2.25 × the mean: the most a wave can be, with all of a year's rain in one
    # month, is 2 / (sin(πk/12) / (πk/12)), 2.22 for the 4-month wave (2025 has such cells).
    *[{"kind": "linear", "scale": 56.4, "offset": -2.25, "relative": True}] * 6,
]
# How far single days stray (cpc.py), a standard deviation in °C: the mean
# and the yearly wave only. It hardly changes faster, and the monthly values
# it is fitted to are noisier than the shorter waves (0.5 °C RMS off them).
_SPREAD = [
    {"kind": "linear", "scale": 16, "offset": 0},  # 0 … 15.9 °C (Siberia's winter nights reach 15)
    *[{"kind": "linear", "scale": 20, "offset": -6.35}] * 2,  # ±6.35 °C (high plateaus swing 5 °C and more)
]
# The prevailing wind in riding hours (wind.py), east and north components, m/s.
# ±10 m/s in 0.08 m/s steps, mean and waves alike: Patagonia's westerlies
# average 9 m/s, and monsoons reverse by as much.
_WIND = [{"kind": "linear", "scale": 12.7, "offset": -10}] * TERMS
# Mean highs run from about −25 °C (Greenland's ice) to +39 °C, mean lows from −35 to +28 °C.
ENCODING = {
    "tmx": _temp(-28),
    "tmn": _temp(-38),
    "pre": _RAIN,
    "r1": _DAYS,
    "r5": _DAYS,
    "r10": _DAYS,
    "tmxsd": _SPREAD,
    "tmnsd": _SPREAD,
    "u10": _WIND,
    "v10": _WIND,
}


def fit(monthly: np.ndarray, per_day: bool) -> np.ndarray:
    """(12, …) monthly values → (TERMS, …) seasonal-curve coefficients."""
    m = monthly / MONTH_DAYS.reshape(12, *([1] * (monthly.ndim - 1))) if per_day else monthly
    out = [m.mean(axis=0)]
    for k in range(1, HARMONICS + 1):
        flat = np.sin(np.pi * k / 12) / (np.pi * k / 12)
        for wave in (np.cos, np.sin):
            out.append(np.tensordot(wave(2 * np.pi * k * PHASES), m, axes=1) / 6 / flat)
    return np.stack(out)


def evaluate(c: np.ndarray, phase: np.ndarray) -> np.ndarray:
    """Coefficients (TERMS, …) at positions in the year (P,) → (P, …)."""
    v = np.multiply.outer(np.ones_like(phase), c[0])
    for k in range(1, HARMONICS + 1):
        t = 2 * np.pi * k * phase
        v = v + np.multiply.outer(np.cos(t), c[2 * k - 1]) + np.multiply.outer(np.sin(t), c[2 * k])
    return v


def encode(name: str, c: np.ndarray) -> np.ndarray:
    """Coefficients (TERMS, …) → bytes, as many terms as its encoding has; a cell without data is NODATA in every term."""
    out = np.empty((len(ENCODING[name]), *c.shape[1:]), dtype=np.uint8)
    mean = c[0]
    for i, enc in enumerate(ENCODING[name]):
        v = c[i] / np.where(mean > 0, mean, np.inf) if enc.get("relative") else c[i]
        b = np.sqrt(np.clip(v, 0, None)) * enc["scale"] if enc["kind"] == "sqrt" else (v - enc["offset"]) * enc["scale"]
        b = np.round(np.nan_to_num(b))
        if (clipped := np.sum(((b < 0) | (b > e.NODATA - 1)) & ~np.isnan(mean))) > 0:
            raise SystemExit(f"{name} term {i}: {clipped} values outside the encoding's range; widen it in pack.ENCODING")
        out[i] = np.clip(b, 0, e.NODATA - 1)
    out[:, np.isnan(mean)] = e.NODATA
    return out


def decode(name: str, b: np.ndarray) -> np.ndarray:
    """The inverse of encode (and what the app does): (TERMS, …), the terms not stored 0."""
    out = np.zeros((TERMS, *b.shape[1:]), dtype=np.float64)
    for i, enc in enumerate(ENCODING[name]):
        x = b[i].astype(np.float64)
        out[i] = (x / enc["scale"]) ** 2 if enc["kind"] == "sqrt" else x / enc["scale"] + enc["offset"]
        if enc.get("relative"):
            out[i] *= out[0]
    out[:, b[0] == e.NODATA] = np.nan
    return out


def extras(climate: str, land: np.ndarray) -> dict[str, np.ndarray]:
    """The layers built outside the monthly grid, as coefficients (TERMS, rows, cols) on land, NaN elsewhere:
    the spread of single days (the same in every climate: how far days stray hardly depends on the years)
    and the climate's own wind."""
    out = {}
    for path, names in ((cpc.OUT, cpc.LAYERS.values()), (wind.grid_file(climate), wind.COMPONENTS.values())):
        z = np.load(path)
        for name in names:
            c = fit(z[name], False).astype(np.float32)
            c[:, ~land] = np.nan
            out[name] = c
    return out


TILE = 10  # degrees; tiles start at multiples of it
DIR = OUT / "climate"
CLIMATES = ["last15", *variants.VARIANTS]


def _source(climate: str, ext: str) -> Path:
    return e.grid_file(ext) if climate == "last15" else variants.grid_file(climate, ext)


def header_file(climate: str) -> Path:
    return DIR / f"{climate}.json"


def tile_id(lat: int, lon: int) -> str:
    """A tile by its south-west corner, e.g. "40_10" for 40–50° N, 10–20° E."""
    return f"{lat}_{lon}"


def outputs() -> list[Path]:
    return [header_file(c) for c in CLIMATES]


def inputs() -> list[Path]:
    return [_source(c, x) for c in CLIMATES for x in ("bin", "json")] + [cpc.OUT] + [wind.grid_file(c) for c in CLIMATES]


def curves(monthly: bytes, header: dict) -> tuple[dict[str, np.ndarray], np.ndarray]:
    """A monthly grid (era5land.py's layout) → each layer's coefficients (TERMS, rows, cols) and the static bytes (static, rows, cols)."""
    names, rows, cols = header["vars"], header["rows"], header["cols"]
    raw = np.frombuffer(monthly, dtype=np.uint8)
    n = len(names) * 12 * rows * cols
    layers = raw[:n].reshape(len(names), 12, rows, cols)
    coef = {name: fit(variants.decode(name, layers[i]).astype(np.float32), name not in ("tmx", "tmn")).astype(np.float32) for i, name in enumerate(names)}
    return coef, raw[n:].reshape(-1, rows, cols)


def tiles(header: dict) -> dict[str, tuple[np.ndarray, np.ndarray]]:
    """Each tile's rows and columns of the world grid: the cells whose centres
    lie on or inside its edges, so neighbouring tiles share their edge cells
    and a point anywhere in a tile can be interpolated from it alone. Columns
    wrap round at 180°."""
    lat0, lon0, step = header["lat0"], header["lon0"], header["step"]
    rows, cols, size = header["rows"], header["cols"], round(TILE / step) + 1
    south = lat0 - (rows - 1) * step
    out = {}
    for lat in range(int(np.floor(south / TILE)) * TILE, int(lat0) + 1, TILE):
        r0 = round((lat0 - (lat + TILE)) / step)  # the tile's northern edge
        r = np.arange(r0, r0 + size)
        if r[-1] < 0 or r[0] >= rows:
            continue
        for lon in range(-180, 180, TILE):
            c0 = round((lon - lon0) / step)
            out[tile_id(lat, lon)] = (r, np.arange(c0, c0 + size) % cols)
    return out


def _write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".part")
    tmp.write_bytes(data)
    tmp.replace(path)


def _cut(a: np.ndarray, r: np.ndarray, c: np.ndarray) -> np.ndarray:
    """A tile's cells of (…, rows, cols) bytes; rows beyond the grid (towards the poles) are sea."""
    out = np.full((*a.shape[:-2], len(r), len(c)), e.NODATA, dtype=np.uint8)
    ok = (r >= 0) & (r < a.shape[-2])
    out[..., ok, :] = a[..., r[ok][:, None], c[None, :]]
    return out


def pack(climate: str) -> None:
    """Publish one climate: its tiles and their header."""
    header = json.loads(_source(climate, "json").read_text())
    coef, static = curves(_source(climate, "bin").read_bytes(), header)
    land = ~np.isnan(coef["tmx"][0])
    coef |= extras(climate, land)
    names = [*header["vars"], *cpc.LAYERS.values(), *wind.COMPONENTS.values()]
    enc = {name: encode(name, c) for name, c in coef.items()}  # (its terms, rows, cols) bytes
    folder = DIR / climate
    if folder.exists():
        shutil.rmtree(folder)  # tiles of an earlier build that are no longer land
    ids = []
    for tid, (r, c) in tiles(header).items():
        inside = r[(r >= 0) & (r < header["rows"])]
        if not land[np.ix_(inside, c)].any():
            continue
        data = np.concatenate([_cut(enc[n], r, c) for n in names]).tobytes() + _cut(static, r, c).tobytes()
        _write(folder / f"{tid}.bin", data)
        ids.append(tid)
    meta = {k: v for k, v in header.items() if k not in ("lon0", "lat0", "rows", "cols", "encoding")}
    meta |= {
        "vars": names,
        "terms": TERMS,  # the most a layer has; each has as many as its encoding
        "tile": TILE,
        "size": round(TILE / header["step"]) + 1,
        "tiles": sorted(ids),
        "encoding": {n: ENCODING[n] for n in names} | {s: e.ENCODING[s] for s in header.get("static", [])},
    }
    _write(header_file(climate), json.dumps(meta, separators=(",", ":")).encode())
    size = sum(p.stat().st_size for p in folder.iterdir())
    log(f"  {climate:7} {len(ids)} tiles, {size / 1e6:.1f} MB")


def build(fresh: bool = False) -> None:
    code = code_hash(sys.modules[__name__], e, variants, cpc, wind, pipeline)
    stamp = Stamp("pack", inputs(), outputs(), code)
    if not fresh and stamp.up_to_date():
        log("  packed grids are up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing {missing[0].relative_to(pipeline.ROOT)}. Run: build climate, build variants, build spread, build wind")
    for climate in CLIMATES:
        pack(climate)
    stamp.done()
