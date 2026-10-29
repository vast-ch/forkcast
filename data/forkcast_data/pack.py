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

Output per continent and climate: out/<continent>/climate[-<variant>].bin and
.json. One byte per value (255 = no data), laid out [layer][term][row][col],
then the static layers [row][col] as in the monthly grid. Terms are the mean,
then cos and sin of each wave. Each term has its own encoding, value =
byte / scale + offset (or (byte / scale)² for "sqrt"); rain's waves are
"relative": a share of the cell's mean rain, so dry places keep their
precision.

Usage: uv run python -m forkcast_data build pack [--fresh]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

from . import continents, pipeline, variants
from . import era5land as e
from .continents import CONTINENTS
from .pipeline import OUT, Stamp, code_hash, log

HARMONICS = 3
TERMS = 1 + 2 * HARMONICS
MONTH_DAYS = np.array([31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31], dtype=np.float64)
PHASES = (np.arange(12) + 0.5) / 12


def _temp(low: float) -> list[dict]:
    """Highs or lows: the mean from `low` °C in 0.25 °C steps (63.5 °C of range)."""
    return [
        {"kind": "linear", "scale": 4, "offset": low},
        *[{"kind": "linear", "scale": 5, "offset": -38}] * 2,  # yearly wave, −38 … +12.8 °C (Siberia's winters), 0.2 °C steps
        *[{"kind": "linear", "scale": 20, "offset": -6.35}] * 4,  # shorter waves, ±6.35 °C, 0.05 °C steps
    ]


_DAYS = [
    {"kind": "linear", "scale": 254, "offset": 0},  # share of rainy days, 0 … 1
    *[{"kind": "linear", "scale": 200, "offset": -0.635}] * 6,  # ±0.635
]
_RAIN = [
    {"kind": "sqrt", "scale": 40},  # mm per day, up to 40
    *[{"kind": "linear", "scale": 63.5, "offset": -2, "relative": True}] * 6,  # ±2 × the mean
]
# Mean highs run from about −19 to +40 °C, mean lows from −26 to +28 °C.
ENCODING = {"tmx": _temp(-22), "tmn": _temp(-31), "pre": _RAIN, "r1": _DAYS, "r5": _DAYS, "r10": _DAYS}


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
    """Coefficients (TERMS, …) → bytes; a cell without data is NODATA in every term."""
    out = np.empty(c.shape, dtype=np.uint8)
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
    """The inverse of encode (and what the app does)."""
    out = np.empty(b.shape, dtype=np.float64)
    for i, enc in enumerate(ENCODING[name]):
        x = b[i].astype(np.float64)
        out[i] = (x / enc["scale"]) ** 2 if enc["kind"] == "sqrt" else x / enc["scale"] + enc["offset"]
        if enc.get("relative"):
            out[i] *= out[0]
    out[:, b[0] == e.NODATA] = np.nan
    return out


def _sources(cid: str) -> list[tuple[str, Path, Path]]:
    """(published name, monthly bin, monthly json) of each climate of a continent."""
    base = [("climate", e.grid_file(cid, "bin"), e.grid_file(cid, "json"))]
    return base + [(f"climate-{v}", variants.grid_file(cid, v, "bin"), variants.grid_file(cid, v, "json")) for v in variants.VARIANTS]


def outputs() -> list[Path]:
    return [OUT / c["id"] / f"{n}.{x}" for c in CONTINENTS for n, _, _ in _sources(c["id"]) for x in ("bin", "json")]


def inputs() -> list[Path]:
    return [p for c in CONTINENTS for _, b, j in _sources(c["id"]) for p in (b, j)]


def pack(monthly: bytes, header: dict) -> tuple[bytes, dict]:
    """One monthly grid (era5land.py's layout) → the published grid and its header."""
    names, cells = header["vars"], header["rows"] * header["cols"]
    raw = np.frombuffer(monthly, dtype=np.uint8)
    layers = raw[: len(names) * 12 * cells].reshape(len(names), 12, header["rows"], header["cols"])
    packed = [encode(n, fit(variants.decode(n, layers[i]).astype(np.float64), n not in ("tmx", "tmn"))) for i, n in enumerate(names)]
    out = dict(header, terms=TERMS, encoding={n: ENCODING[n] for n in names} | {s: e.ENCODING[s] for s in header.get("static", [])})
    return np.stack(packed).tobytes() + raw[len(names) * 12 * cells :].tobytes(), out


def _write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".part")
    tmp.write_bytes(data)
    tmp.replace(path)


def build(fresh: bool = False) -> None:
    code = code_hash(sys.modules[__name__], e, variants, continents, pipeline)
    stamp = Stamp("pack", inputs(), outputs(), code)
    if not fresh and stamp.up_to_date():
        log("  packed grids are up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing {missing[0].relative_to(pipeline.ROOT)}. Run: build climate, build variants")
    for c in CONTINENTS:
        for name, b, j in _sources(c["id"]):
            data, header = pack(b.read_bytes(), json.loads(j.read_text()))
            _write(OUT / c["id"] / f"{name}.bin", data)
            _write(OUT / c["id"] / f"{name}.json", json.dumps(header, separators=(",", ":")).encode())
        log(f"  {c['id']:14} {len(data) / 1e6:.1f} MB per climate")
    stamp.done()
