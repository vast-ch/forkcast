"""Research: how much would each climate variant change the grid, and is it more than chance?

Not a build step: it writes only cache/variants/report.md. It compares the
variants built by variants.py (and the strong El Niño / La Niña ones, which
aren't built) with the app's period, per continent, from the per-year fields
of `build years`. The question, method and findings are in
docs/climate-variants.md.

Windows (last 10, last 5 years) are compared with the app's 2011–2025 average
and keep the warming trend, which is what they are for. Phases are averaged
after removing each cell-month's linear trend over all the years analysed,
like the build does.

Two tests per phase, both against random sets of as many years (per month):
- noticeable: the share of land cell-months a rider would notice changing,
  next to the same share for the random sets;
- real: the share of cell-months where the phase beats 90 % of the random
  sets at that very cell (10 % by chance). "Both" is what a variant would
  really add.

Usage (in the data container, after `download oni` and `build years`):
    uv run python -m forkcast_data.variants_research [--from Y0] [--to Y1]
"""

from __future__ import annotations

import argparse
import calendar

import numpy as np

from . import pipeline
from .__main__ import YEARS as APP_PERIOD
from .continents import CONTINENTS
from .pipeline import log
from .variants import DIR, HISTORY, MIN_YEARS, ONI_FILE, RANDOM_SETS, SEED, boxes, enso_months, parse_oni, residuals, year_file

REPORT = DIR / "report.md"
FIELDS = ["tmx", "tmn", "pre", "r1"]
APP_YEARS = list(range(APP_PERIOD[0], APP_PERIOD[1] + 1))
WINDOWS = {"last10": APP_YEARS[-10:], "last5": APP_YEARS[-5:]}


def noticeable(d: np.ndarray, base: np.ndarray, field: str) -> np.ndarray:
    """Where a change `d` from `base` is one a rider would notice (False where there is no data)."""
    with np.errstate(invalid="ignore"):
        if field in ("tmx", "tmn"):
            return np.abs(d) >= 0.5  # the grid's encoding step
        if field == "pre":
            return (np.abs(d) >= 10) & (np.abs(d) >= 0.2 * base)
        return np.abs(d) >= 1  # a rainy day more or less a month


def share(d: np.ndarray, base: np.ndarray, field: str) -> float:
    """Share of land cell-months where a change `d` from `base` is one a rider would notice."""
    ok = np.isfinite(d)
    return float(noticeable(d, base, field)[ok].mean()) if ok.any() else float("nan")


def variant_months(years: list[int], oni: dict) -> dict[str, np.ndarray]:
    """For each variant, which (year, month) it averages, as a (len(years), 12) mask."""
    def mask(pick) -> np.ndarray:
        return np.array([[pick(y, m) for m in range(12)] for y in years])

    out = {name: mask(lambda y, m, ys=ys: y in ys) for name, ys in WINDOWS.items()}
    for name, sign, strong in (("elnino", 1, False), ("lanina", -1, False), ("elnino-strong", 1, True), ("lanina-strong", -1, True)):
        months = enso_months(oni, sign, strong)
        out[name] = mask(lambda y, m, ms=months: (y, m) in ms)
    return out


def analyse(years: list[int]) -> None:
    if missing := [y for y in years if not year_file(y).exists()]:
        raise SystemExit(f"No extracted fields for {missing[0]}. Run: python -m forkcast_data build years")
    if not set(APP_YEARS) <= set(years):
        raise SystemExit(f"The years analysed must include the app's period {APP_YEARS[0]}–{APP_YEARS[-1]}")
    if not ONI_FILE.exists():
        raise SystemExit("No ONI. Run: python -m forkcast_data download oni")
    masks = variant_months(years, parse_oni(ONI_FILE.read_text()))
    phases = [v for v in masks if v not in WINDOWS]
    app = np.array([y in APP_YEARS for y in years])
    z = np.load(year_file(years[0]))
    cut = boxes(z["lat"], z["lon"])
    table: dict = {}
    for field in FIELDS:
        a16 = np.stack([np.load(year_file(y))[field] for y in years])  # (year, month, lat, lon), float16
        table[field] = {}
        for cid, (rs, cs) in cut.items():
            # Counts summed over months: cells, noticeable, real, both, and noticeable for each random set.
            acc = {v: np.zeros(4) for v in masks}
            rnd = {v: np.zeros(RANDOM_SETS) for v in phases}
            mean = {v: [0.0, 0] for v in masks}
            for m in range(12):
                rng = np.random.default_rng([SEED, m])  # the same random sets for every field and continent
                raw = a16[:, m, rs, cs].astype(np.float32)
                base = raw[app].mean(axis=0)
                res = residuals(raw, years)
                ok = np.isfinite(base)
                noise: dict = {}  # k -> (random composites' noticeable hits per set, 90th percentile of |composite| per cell)
                for v, mk in masks.items():
                    sel = mk[:, m]
                    if sel.sum() < MIN_YEARS:
                        continue  # too few to average; the report lists these months
                    d = raw[sel].mean(axis=0) - base if v in WINDOWS else res[sel].mean(axis=0)
                    hit = noticeable(d, base, field) & ok
                    acc[v][0] += ok.sum()
                    acc[v][1] += hit.sum()
                    mean[v][0] += float(np.nansum(d[ok]))
                    mean[v][1] += int(ok.sum())
                    if v in WINDOWS:
                        continue
                    k = int(sel.sum())
                    if k not in noise:
                        comps = np.stack([res[rng.choice(len(years), k, replace=False)].mean(axis=0) for _ in range(RANDOM_SETS)])
                        hits = np.array([(noticeable(c, base, field) & ok).sum() for c in comps])
                        noise[k] = (hits, np.percentile(np.abs(comps), 90, axis=0))
                    hits, p90 = noise[k]
                    real = (np.abs(d) > p90) & ok
                    acc[v][2] += real.sum()
                    acc[v][3] += (real & hit).sum()
                    rnd[v] += hits
            row = {}
            for v in masks:
                n = acc[v][0]
                if n == 0:  # every month left out
                    row[v] = None
                    continue
                r = rnd[v] / n if v in rnd else None
                row[v] = {
                    "noticeable": acc[v][1] / n,
                    "noise": (float(np.median(r)), float(np.percentile(r, 90))) if r is not None else None,
                    "real": acc[v][2] / n if v in rnd else None,
                    "both": acc[v][3] / n if v in rnd else None,
                    "mean": mean[v][0] / mean[v][1],
                }
            table[field][cid] = row
            log(f"  analysed {field} {cid}")
        del a16
    text = report(table, masks, years)
    DIR.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(text)
    print(text)
    log(f"  wrote {REPORT.relative_to(pipeline.ROOT)}")


def report(table: dict, masks: dict[str, np.ndarray], years: list[int]) -> str:
    unit = {"tmx": "°C", "tmn": "°C", "pre": "mm", "r1": "days"}
    test = {
        "tmx": "highs change by ≥ 0.5 °C",
        "tmn": "lows change by ≥ 0.5 °C",
        "pre": "monthly rain changes by ≥ 20 % and ≥ 10 mm",
        "r1": "rainy days (≥ 1 mm) change by ≥ 1 a month",
    }
    conts = [c["id"] for c in CONTINENTS]
    lines = [
        f"# Climate variants, {years[0]}–{years[-1]}",
        "",
        f"Windows are compared with {APP_YEARS[0]}–{APP_YEARS[-1]}; phases with each cell-month's linear trend over {years[0]}–{years[-1]}.",
        "",
        "Years per month in each variant (fewest–most):",
        "",
    ]
    for v, mk in masks.items():
        n = mk.sum(axis=0)
        few = [calendar.month_abbr[m + 1] for m in range(12) if n[m] < MIN_YEARS]
        skipped = f", left out (< {MIN_YEARS} years): {' '.join(few)}" if few else ""
        lines.append(f"- {v}: {int(n.min())}–{int(n.max())}{skipped}")
    lines += [
        "",
        "Each cell: **noticeable**: share of land cell-months where the variant makes the change in the heading;",
        f"for phases, in parentheses, the same for random sets of as many years (median / 90th percentile, {RANDOM_SETS} sets),",
        "✓ where the phase beats that 90th percentile. **real**: share of cell-months where the phase beats 90 % of the",
        "random sets at that cell (10 % by chance). **both**: real and noticeable. In brackets: the mean signed change.",
    ]
    for field in FIELDS:
        lines += ["", f"## {field}: {test[field]}", "", "| variant | " + " | ".join(conts) + " |", "|---|" + "---|" * len(conts)]
        for v in masks:
            cells = []
            for cid in conts:
                r = table[field][cid][v]
                if r is None:
                    cells.append("–")
                    continue
                txt = f"{r['noticeable']:.0%}"
                if r["noise"]:
                    lo, hi = r["noise"]
                    txt += f" ({lo:.0%}/{hi:.0%}){' ✓' if r['noticeable'] > hi else ''}<br>real {r['real']:.0%}, both {r['both']:.0%}"
                cells.append(f"{txt}<br>[{r['mean']:+.2f} {unit[field]}]")
            lines.append(f"| {v} | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(prog="python -m forkcast_data.variants_research", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="y0", type=int, default=HISTORY[0], help="first year analysed")
    ap.add_argument("--to", dest="y1", type=int, default=HISTORY[1], help="last year analysed")
    a = ap.parse_args(argv)
    log("analyse variants")
    analyse(list(range(a.y0, a.y1 + 1)))


if __name__ == "__main__":
    main()
