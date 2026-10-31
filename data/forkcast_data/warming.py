"""The warming: each climate's highs and lows brought forward to the year after its period.

An average of past years lags the climate it describes: 2011–2025 is centred
on 2018, and a trip next year meets a warmer world. Backtested over 1996–2025
(each year forecast from the years before it only), the plain 15-year average
came out 0.41 °C too cold for highs in Europe, 0.30 °C over the world. Correcting it
with each cell's own trend made the forecasts worse: 15–20 years of weather
give a trend too noisy to use. What works is a trend that is long and broad:

    rate = each cell's straight-line trend of the year's average high (low)
           over every year of HISTORY, averaged over SMOOTH° × SMOOTH° of land

and each climate is shifted by rate × (next year − the middle of its years).
That cut the cold bias to about 0.1 °C and the typical error of a month by
0.03 °C in Europe, closer in 80–93% of years (verify's backtest keeps
measuring it, against `last15 unshifted`). Rain isn't shifted: its trend didn't help.

- build warming: cache/grids/warming.npz, `tmx` and `tmn` in °C per year on
  the climate's grid, from the extracted years (`build years`), computed at
  1° and interpolated.
- The pack step applies it (pack.py), so the published climates carry it and
  the app needs nothing more; it costs no bytes.

Usage: uv run python -m forkcast_data build warming [--fresh]
"""

from __future__ import annotations

import json
import sys
import warnings
from pathlib import Path

import numpy as np

from . import era5land as e
from . import pipeline, variants
from .pipeline import Stamp, code_hash, log

OUT = e.GRIDS / "warming.npz"
SMOOTH = 21  # degrees (cells at 1°) of the box the trend is averaged over
EVERY = 4  # 0.25° cells per 1° cell
FIELDS = ("tmx", "tmn")


def smooth(a: np.ndarray, k: int) -> np.ndarray:
    """The NaN-aware mean over k × k cells around each cell of (…, rows, cols); columns wrap round the globe."""
    from numpy.lib.stride_tricks import sliding_window_view

    p = k // 2
    pad = np.pad(a, [(0, 0)] * (a.ndim - 2) + [(p, p), (0, 0)], constant_values=np.nan)
    pad = np.concatenate([pad[..., -p:], pad, pad[..., :p]], axis=-1)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)  # all-sea windows
        return np.nanmean(sliding_window_view(pad, (k, k), axis=(-2, -1)), axis=(-2, -1))


def rate(annual: np.ndarray, years: list[int]) -> np.ndarray:
    """(year, rows, cols) yearly averages → each cell's trend (°C per year), smoothed over SMOOTH cells; NaN at sea."""
    t = np.array(years, dtype=np.float64)
    t -= t.mean()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        mean = np.nanmean(annual, axis=0)
    slope = np.tensordot(t, np.nan_to_num(annual - mean), axes=1) / (t * t).sum()
    slope = np.where(np.isfinite(mean), slope, np.nan)
    return np.where(np.isfinite(mean), smooth(slope, SMOOTH), np.nan)


def shift_years(climate: str, app: tuple[int, int]) -> float:
    """How many years a climate is brought forward: from the middle of its years to the year after the period."""
    target = app[1] + 1
    if climate == variants.YEAR:
        return 0.0  # the one year, as it was
    window = variants.windows(app).get(climate, list(range(app[0], app[1] + 1)))
    return target - (window[0] + window[-1]) / 2


def _annual(field: str, years: range) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    z = np.load(variants.year_file(years[0]))
    keep = np.where(z["lat"] >= e.SOUTH)[0]
    lat, lon = z["lat"][keep][::EVERY], z["lon"][::EVERY]
    a = np.stack([np.load(variants.year_file(y))[field][:, keep][:, ::EVERY, ::EVERY].astype(np.float32).mean(axis=0) for y in years])
    return a, lat, lon


def to_grid(coarse: np.ndarray, header: dict) -> np.ndarray:
    """A 1° field (every EVERY-th row and column of the grid) onto the full grid, bilinear."""
    rows, cols = header["rows"], header["cols"]
    r = np.arange(rows) / EVERY
    c = np.arange(cols) / EVERY
    r0 = np.clip(np.floor(r).astype(int), 0, coarse.shape[0] - 1)
    c0 = np.floor(c).astype(int) % coarse.shape[1]
    r1 = np.clip(r0 + 1, 0, coarse.shape[0] - 1)
    c1 = (c0 + 1) % coarse.shape[1]
    tr, tc = (r - r0)[:, None], (c - np.floor(c))[None, :]
    filled = np.where(np.isfinite(coarse), coarse, smooth(coarse, 5))  # coast: borrow from nearby land
    filled = np.nan_to_num(filled)
    return (
        filled[np.ix_(r0, c0)] * (1 - tr) * (1 - tc)
        + filled[np.ix_(r0, c1)] * (1 - tr) * tc
        + filled[np.ix_(r1, c0)] * tr * (1 - tc)
        + filled[np.ix_(r1, c1)] * tr * tc
    ).astype(np.float32)


def inputs() -> list[Path]:
    return [variants.year_file(y) for y in range(variants.HISTORY[0], variants.HISTORY[1] + 1)] + [e.grid_file("json")]


def build(fresh: bool = False) -> None:
    code = code_hash(sys.modules[__name__], variants, e, pipeline)
    stamp = Stamp("warming", inputs(), [OUT], code, {"smooth": SMOOTH, "history": list(variants.HISTORY)})
    if not fresh and stamp.up_to_date():
        log("  warming is up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing {missing[0].relative_to(pipeline.ROOT)}. Run: build climate, build years")
    header = json.loads(e.grid_file("json").read_text())
    years = range(variants.HISTORY[0], variants.HISTORY[1] + 1)
    out = {}
    for field in FIELDS:
        annual, lat, _ = _annual(field, years)
        coarse = rate(annual, list(years))
        out[field] = to_grid(coarse, header)
        w = np.cos(np.radians(lat))[:, None] * np.isfinite(coarse)
        log(f"  {field}: {np.nansum(coarse * w) / w.sum() * 10:+.2f} °C per decade over land")
    tmp = OUT.with_name(OUT.stem + ".part.npz")
    np.savez(tmp, **out)
    tmp.replace(OUT)
    stamp.done()
