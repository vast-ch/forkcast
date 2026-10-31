"""Measure how well the data holds up, and keep every result.

The help's Nerd mode shows how precise each number is. Those statements come
from here, measured on the data we have, never typed into the page. Each run
appends its results to out/verify/history.csv (one row per measurement, with
the code that made it) and writes the latest run to out/verify/latest.json,
which the app imports.

What it measures, first cut:

- curve: the seasonal curves the app draws (pack.py) against the monthly
  grids they are fitted to: the fit alone, then with the curves packed into
  bytes as the app gets them. Each month's average of the curve is compared,
  as that is what the monthly grid holds.
- backtest: each climate made of the years before (the last 15, 10, 5 years
  or just the last one) as a forecast of the following year's months: our
  guess against what the weather then did, for each of the BACKTEST target
  years (30, all the data allows: ERA5-Land starts in 1981 and the longest
  climate needs 15 years before its target). The smaller the error, the
  better that choice would have planned a trip. The sample is the years,
  not the cells: neighbouring cells and months share their weather, so
  millions of cell-months would overstate the certainty. Each average gets
  a 95 % interval by resampling the years (bootstrap), and each climate is
  compared with 15 years year by year (paired: the same weather tested both
  ways), with an interval on the difference and the share of years it did
  worse. A difference whose interval spans 0 is not shown to be one.
- enso: the El Niño and La Niña corrections where their effect is well known
  (variants.KNOWN): the mean change there, and whether its sign is right.
- shift: how far each other climate moves the year's average high, by area.

Every value is averaged over land, weighted by each cell's area. Builds stay
offline: this only reads what earlier steps made.

Usage: uv run python -m forkcast_data build verify [--fresh]
"""

from __future__ import annotations

import csv
import json
import sys
import time
from pathlib import Path

import numpy as np

from . import era5land as e
from . import pack, pipeline, variants
from .pipeline import OUT, STAMPS, Stamp, code_hash, log

DIR = OUT / "verify"
HISTORY = DIR / "history.csv"
LATEST = DIR / "latest.json"
COLUMNS = ["date", "code", "grids", "metric", "climate", "field", "area", "stat", "value", "unit"]

FIELDS = {"tmx": "°C", "tmn": "°C", "pre": "mm", "r5": "days"}  # what is measured, per month
AREAS = {"World": None, "Europe": variants.AREAS["Europe"]}
BACKTEST = range(1996, 2026)  # target years; each needs the 15 before it (from 1981)
WINDOWS = {"last15": 15, "last10": 10, "last5": 5, "last1": 1}
EVERY = 4  # the backtest uses every 4th cell each way (1°): plenty for an average, 16 × less memory
BOOTSTRAP = 2000  # resamples of the years for each interval


def outputs() -> list[Path]:
    return [LATEST, HISTORY]


def inputs() -> list[Path]:
    years = range(variants.HISTORY[0], variants.HISTORY[1] + 1)
    grids = [e.grid_file(x) for x in ("bin", "json")] + [variants.grid_file(v, x) for v in variants.VARIANTS for x in ("bin", "json")]
    return grids + [variants.year_file(y) for y in years]


def _weights(lat: np.ndarray, cols: int) -> np.ndarray:
    """Each cell's share of the Earth's surface, (rows, cols)."""
    return np.repeat(np.cos(np.radians(lat))[:, None], cols, axis=1)


def _mask(box, lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
    if box is None:
        return np.ones((len(lat), len(lon)), dtype=bool)
    x0, y0, x1, y1 = box
    return ((lat >= y0) & (lat <= y1))[:, None] & ((lon >= x0) & (lon <= x1))[None, :]


def _stats(err: np.ndarray, w: np.ndarray) -> dict[str, float]:
    """Mean absolute, root mean square and 95th percentile of |err| (…, rows, cols), weighted by w (rows, cols), NaN left out."""
    w = np.broadcast_to(w, err.shape)
    ok = np.isfinite(err)
    a, ww = np.abs(err[ok]), w[ok]
    order = np.argsort(a)
    cum = np.cumsum(ww[order]) / ww.sum()
    return {
        "mae": float(np.sum(a * ww) / ww.sum()),
        "rmse": float(np.sqrt(np.sum(a**2 * ww) / ww.sum())),
        "p95": float(a[order][np.searchsorted(cum, 0.95)]),
    }


def _grid_axes(h: dict) -> tuple[np.ndarray, np.ndarray]:
    lat = h["lat0"] - np.arange(h["rows"]) * h["step"]
    lon = h["lon0"] + np.arange(h["cols"]) * h["step"]
    return lat, lon


def monthly_means(c: np.ndarray, per_day: bool) -> np.ndarray:
    """Coefficients (TERMS, …) → each month's average of the curve (12, …), in the monthly grid's units."""
    out = np.multiply.outer(np.ones(12), c[0])
    for k in range(1, pack.HARMONICS + 1):
        flat = np.sin(np.pi * k / 12) / (np.pi * k / 12)
        t = 2 * np.pi * k * pack.PHASES
        out = out + flat * (np.multiply.outer(np.cos(t), c[2 * k - 1]) + np.multiply.outer(np.sin(t), c[2 * k]))
    return out * pack.MONTH_DAYS.reshape(12, *([1] * (c.ndim - 1))) if per_day else out


def curve(base: variants.BaseGrid) -> list[dict]:
    lat, lon = _grid_axes(base.header)
    w = _weights(lat, len(lon))
    rows = []
    for field, unit in FIELDS.items():
        m = base.field(field).astype(np.float64)
        per_day = field not in ("tmx", "tmn")
        c = pack.fit(m, per_day)
        packed = pack.decode(field, pack.encode(field, c))
        for stage, coef in (("fit", c), ("packed", packed)):
            err = monthly_means(coef, per_day) - m
            for area, box in AREAS.items():
                for stat, v in _stats(np.where(_mask(box, lat, lon), err, np.nan), w).items():
                    rows.append({"metric": f"curve-{stage}", "climate": "last15", "field": field, "area": area, "stat": stat, "value": v, "unit": unit})
    return rows


def per_year_mae(err: np.ndarray, at: np.ndarray, w: np.ndarray) -> np.ndarray:
    """Each target year's mean absolute error over its months and the cells `at`, weighted by area: (target,)."""
    ww = np.where(at, w, 0.0)
    a = np.abs(err)
    ok = np.isfinite(a)
    num = np.sum(np.where(ok, a, 0) * ww, axis=(1, 2, 3))
    return num / np.sum(np.where(ok, 1.0, 0) * ww, axis=(1, 2, 3))


def interval(per_year: np.ndarray, seed: int = 1) -> tuple[float, float]:
    """95 % interval of the mean of per-year values, by resampling the years (BOOTSTRAP times)."""
    rng = np.random.default_rng(seed)
    means = per_year[rng.integers(0, len(per_year), (BOOTSTRAP, len(per_year)))].mean(axis=1)
    lo, hi = np.percentile(means, [2.5, 97.5])
    return float(lo), float(hi)


def backtest() -> list[dict]:
    """Each climate as a forecast of the following year, per target year, so the
    spread between years gives each average an interval. Years are the sample:
    neighbouring cells and months share their weather, so they are not
    independent, but one year's weather says little about the next."""
    first = BACKTEST[0] - max(WINDOWS.values())
    years = list(range(first, BACKTEST[-1] + 1))
    z = np.load(variants.year_file(years[0]))
    keep = np.where(z["lat"] >= e.SOUTH)[0][::EVERY]
    lat, lon = z["lat"][keep], z["lon"][::EVERY]
    w = _weights(lat, len(lon))
    rows = []
    for field, unit in FIELDS.items():
        a = np.stack([np.load(variants.year_file(y))[field][:, keep][:, :, ::EVERY].astype(np.float32) for y in years])
        targets = [years.index(t) for t in BACKTEST]
        for area, box in AREAS.items():
            at = _mask(box, lat, lon)
            per = {}
            for climate, n in WINDOWS.items():
                err = np.stack([a[i - n : i].mean(axis=0) - a[i] for i in targets])  # (target, month, rows, cols)
                per[climate] = per_year_mae(err, at, w)
            for climate, v in per.items():
                common = {"metric": "backtest", "climate": climate, "field": field, "area": area, "unit": unit}
                lo, hi = interval(v)
                rows += [common | {"stat": "mae", "value": float(v.mean())}, common | {"stat": "mae lo95", "value": lo}, common | {"stat": "mae hi95", "value": hi}]
                if climate != "last15":
                    d = v - per["last15"]  # paired by year: the same weather tested both ways
                    lo, hi = interval(d)
                    rows += [
                        common | {"stat": "vs last15", "value": float(d.mean())},
                        common | {"stat": "vs last15 lo95", "value": lo},
                        common | {"stat": "vs last15 hi95", "value": hi},
                        common | {"stat": "worse years", "value": float(np.mean(d > 0)), "unit": "share"},
                    ]
        del a
    rows.append({"metric": "backtest", "climate": "", "field": "", "area": "", "stat": "years", "value": float(len(BACKTEST)), "unit": "years"})
    return rows


def enso(base: variants.BaseGrid) -> list[dict]:
    lat, lon = _grid_axes(base.header)
    w = _weights(lat, len(lon))
    rows = []
    grids = {v: _variant(v) for v in variants.VARIANTS}
    for v, region, field, months, sign in variants.KNOWN:
        at = _mask(variants.REGIONS[region], lat, lon)
        d = grids[v][field][months] - base.field(field)[months]
        ok = np.isfinite(d) & at
        mean = float(np.sum(np.where(ok, d, 0) * w) / np.sum(np.broadcast_to(w, d.shape)[ok]))
        common = {"metric": "enso", "climate": v, "field": field, "area": region}
        rows.append(common | {"stat": f"mean {'+'.join(str(m + 1) for m in months)}", "value": mean, "unit": FIELDS.get(field, "°C")})
        rows.append(common | {"stat": "expected sign", "value": float(sign), "unit": ""})
    for v, g in grids.items():
        d = g["tmx"] - base.field("tmx")
        for area, box in AREAS.items():
            ok = np.isfinite(d) & _mask(box, lat, lon)
            mean = float(np.sum(np.where(ok, d, 0) * w) / np.sum(np.broadcast_to(w, d.shape)[ok]))
            rows.append({"metric": "shift", "climate": v, "field": "tmx", "area": area, "stat": "mean", "value": mean, "unit": "°C"})
    return rows


def _variant(v: str) -> dict[str, np.ndarray]:
    h = json.loads(variants.grid_file(v, "json").read_text())
    n = len(h["vars"]) * 12 * h["rows"] * h["cols"]
    raw = np.frombuffer(variants.grid_file(v, "bin").read_bytes(), dtype=np.uint8)[:n]
    layers = raw.reshape(len(h["vars"]), 12, h["rows"], h["cols"])
    return {name: variants.decode(name, layers[i]) for i, name in enumerate(h["vars"]) if name in FIELDS}


def _grids_code() -> str:
    """The code that built the grids measured: the climate and variants steps' stamps."""
    codes = []
    for step in ("climate", "variants"):
        p = STAMPS / f"{step}.json"
        codes.append(json.loads(p.read_text()).get("code", "?") if p.exists() else "?")
    return "+".join(codes)


def _round(v: float) -> float:
    return float(f"{v:.4g}")


def build(fresh: bool = False) -> None:
    code = code_hash(sys.modules[__name__], pack, e, variants, pipeline)
    stamp = Stamp("verify", inputs(), outputs(), code, {"backtest": [BACKTEST[0], BACKTEST[-1]]})
    if not fresh and stamp.up_to_date():
        log("  measurements are up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing {missing[0].relative_to(pipeline.ROOT)}. Run: build climate, build years, build variants")
    base = variants.BaseGrid()
    rows = []
    for name, step in (("curve", lambda: curve(base)), ("backtest", backtest), ("enso", lambda: enso(base))):
        t0 = time.time()
        rows += step()
        log(f"  {name} measured in {time.time() - t0:.0f} s")
    run = {"date": time.strftime("%Y-%m-%d"), "code": code, "grids": _grids_code()}
    rows = [run | r | {"value": _round(r["value"])} for r in rows]
    DIR.mkdir(parents=True, exist_ok=True)
    is_new = not HISTORY.exists()
    with HISTORY.open("a", newline="") as f:
        out = csv.DictWriter(f, COLUMNS, lineterminator="\n")
        if is_new:
            out.writeheader()
        out.writerows(rows)
    latest = {"run": run, "backtest": [BACKTEST[0], BACKTEST[-1]], "results": [{k: r[k] for k in COLUMNS[3:]} for r in rows]}
    tmp = LATEST.with_name(LATEST.name + ".part")
    tmp.write_text(json.dumps(latest, ensure_ascii=False, indent=1) + "\n")
    tmp.replace(LATEST)
    for r in rows:
        if r["metric"] == "backtest" and r["area"] == "Europe" and r["field"] == "tmx" and r["stat"] in ("mae", "vs last15"):
            log(f"  backtest, Europe's highs: {r['climate']:6} {r['stat']:9} {r['value']:+.3f} °C")
    stamp.done()


# --- Comparing runs ------------------------------------------------------------

HEADLINE = ("mae", "rmse", "p95", "mean")  # the stats compared; intervals and counts only qualify them


def runs(rows: list[dict]) -> list[str]:
    """The runs in the history, oldest first, each named by its date and code."""
    return list(dict.fromkeys(f"{r['date']} {r['code']}" for r in rows))


def compare(baseline: str | None = None) -> None:
    """Print the latest run against a baseline run (by code, date or "date code"; the first by default).

    A backtest change counts only when it is larger than half the baseline's
    95 % interval; anything smaller the 30 years can't tell from chance. The
    other measurements cover the whole grid with nothing left to chance, so
    every change is real (and its size is what matters).
    """
    if not HISTORY.exists():
        raise SystemExit("No measurements yet. Run: build verify")
    with HISTORY.open() as f:
        rows = list(csv.DictReader(f))
    names = runs(rows)
    base = next((n for n in names if baseline and baseline in n), None) if baseline else names[0]
    if base is None:
        raise SystemExit(f"No run {baseline!r}. Runs:\n  " + "\n  ".join(names))
    latest = names[-1]
    of = {name: {(r["metric"], r["climate"], r["field"], r["area"], r["stat"]): float(r["value"]) for r in rows if f"{r['date']} {r['code']}" == name} for name in (base, latest)}
    log(f"{latest} against {base}")
    changed = 0
    for key, v in of[latest].items():
        metric, climate, field, area, stat = key
        if stat not in HEADLINE or key not in of[base]:
            continue
        b = of[base][key]
        d = v - b
        noise = 0.0
        if metric == "backtest":
            lo, hi = of[base].get((*key[:4], f"{stat} lo95")), of[base].get((*key[:4], f"{stat} hi95"))
            noise = (hi - lo) / 2 if lo is not None and hi is not None else 0.0
        if d == 0:
            continue
        changed += 1
        if abs(d) <= noise:
            verdict = "within noise"
        elif stat == "mean":
            verdict = "moved"  # a shift or correction: neither better nor worse
        else:
            verdict = "better" if d < 0 else "worse"
        log(f"  {metric:12} {climate:7} {field:4} {area:22} {stat:5} {b:9.4g} → {v:9.4g} ({d:+.3g}, {verdict})")
    if not changed:
        log("  no change")
