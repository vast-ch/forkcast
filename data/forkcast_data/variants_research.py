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

`checks` tests two ways of picking cleaner ENSO months, and writes
cache/variants/checks-<from>-<to>.md:
- volcanoes: leave out 1982–83 (El Chichón) and 1991–93 (Pinatubo), from the
  events, the random sets and the trend. Does the signal get clearer?
- IOD companions: El Niño with and without its months that were also IOD+
  (La Niña: IOD−). How much of each ENSO average is the Indian Ocean Dipole?
IOD months come from NOAA PSL's Dipole Mode Index (HadISST), downloaded into
cache/variants/dmi.txt: months in a run of ≥ 3 at |DMI| ≥ 0.4 within May–December.

Usage (in the data container, after `download oni` and `build years`):
    uv run python -m forkcast_data.variants_research [analyse|checks] [--from Y0] [--to Y1]
"""

from __future__ import annotations

import argparse
import calendar

import numpy as np

from . import pipeline
from .__main__ import YEARS as APP_PERIOD
from .continents import CONTINENTS
from .pipeline import ensure, http_get, log
from .variants import DIR, HISTORY, MIN_YEARS, ONI_FILE, RANDOM_SETS, SEED, boxes, enso_months, parse_oni, residuals, year_file

REPORT = DIR / "report.md"
DMI_URL = "https://psl.noaa.gov/gcos_wgsp/Timeseries/Data/dmi.had.long.data"
DMI_FILE = DIR / "dmi.txt"
VOLCANIC = {1982, 1983, 1991, 1992, 1993}  # El Chichón, Pinatubo: years with cooling aerosols
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


# --- Checks: cleaner ENSO months? ----------------------------------------------


def parse_dmi(text: str) -> dict[int, list[float]]:
    """{year: 12 monthly values} from PSL's long-format file (missing months are -9999)."""
    rows = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 13 and parts[0].isdigit():
            rows[int(parts[0])] = [float(x) for x in parts[1:]]
    return rows


def _check_dmi(path) -> None:
    rows = parse_dmi(path.read_text())
    if not {HISTORY[0], HISTORY[1]} <= set(rows):
        raise ValueError(f"DMI covers {min(rows, default=0)}–{max(rows, default=0)}, not {HISTORY[0]}–{HISTORY[1]}")


def iod_months(rows: dict[int, list[float]], sign: int) -> set[tuple[int, int]]:
    """Months (year, 0–11) in a positive (sign +1) or negative (−1) IOD event: ≥ 3 in a row at |DMI| ≥ 0.4, May–December."""
    out: set[tuple[int, int]] = set()
    for y, vals in rows.items():
        run: list[int] = []
        for m in range(4, 13):
            if m < 12 and sign * vals[m] >= 0.4 and vals[m] > -999:
                run.append(m)
                continue
            if len(run) >= 3:
                out.update((y, i) for i in run)
            run = []
    return out


def detrend_on(a: np.ndarray, years: list[int], use: np.ndarray) -> np.ndarray:
    """Departures of (year, …) values from each point's linear trend, fitted on the years in `use` only."""
    t = np.array(years, dtype=np.float32)
    t -= t[use].mean()
    mu = a[use].mean(axis=0)
    slope = np.tensordot(t[use], a[use] - mu, axes=1) / np.float32((t[use] ** 2).sum())
    return a - mu - t.reshape(-1, *[1] * (a.ndim - 1)) * slope


def checks(years: list[int]) -> None:
    oni = parse_oni(ONI_FILE.read_text())
    dmi = parse_dmi(DMI_FILE.read_text())
    nino, nina = enso_months(oni, 1), enso_months(oni, -1)
    iodp, iodn = iod_months(dmi, 1), iod_months(dmi, -1)
    clean = np.array([y not in VOLCANIC for y in years])
    every = np.ones(len(years), bool)

    def mask(months, keep=lambda y, m: True) -> np.ndarray:
        return np.array([[(y, m) in months and keep(y, m) for m in range(12)] for y in years])

    def calm(y, m):
        return y not in VOLCANIC

    # name: (months, years for the trend and the random sets)
    variants = {
        "elnino": (mask(nino), every),
        "elnino −volc": (mask(nino, calm), clean),
        "elnino −volc −iod+": (mask(nino, lambda y, m: calm(y, m) and (y, m) not in iodp), clean),
        "elnino −volc, only iod+": (mask(nino, lambda y, m: calm(y, m) and (y, m) in iodp), clean),
        "lanina": (mask(nina), every),
        "lanina −volc": (mask(nina, calm), clean),
        "lanina −volc −iod−": (mask(nina, lambda y, m: calm(y, m) and (y, m) not in iodn), clean),
        "lanina −volc, only iod−": (mask(nina, lambda y, m: calm(y, m) and (y, m) in iodn), clean),
    }
    pairs = [("elnino −volc", "elnino"), ("elnino −volc −iod+", "elnino −volc"), ("lanina −volc", "lanina"), ("lanina −volc −iod−", "lanina −volc")]
    app = np.array([y in APP_YEARS for y in years])
    z = np.load(year_file(years[0]))
    cut = boxes(z["lat"], z["lon"])
    conts = list(cut)
    out = [f"# ENSO checks, {years[0]}–{years[-1]}", "", "Event months per variant (summed over the years):", ""]
    out += [f"- {n}: {int(mk.sum())} months in {int(mk.any(axis=1).sum())} years" for n, (mk, _) in variants.items()]
    for field in FIELDS:
        a16 = np.stack([np.load(year_file(y))[field] for y in years])
        stats = {}  # (variant, continent) -> [cells, noticeable, real, both, random noticeable per set]
        cmp = {}  # (pair, continent) -> [cells, noticeably different, Σx, Σy, Σx², Σy², Σxy]
        for cid, (rs, cs) in cut.items():
            for m in range(12):
                rng = np.random.default_rng([SEED, m])
                raw = a16[:, m, rs, cs].astype(np.float32)
                base = raw[app].mean(axis=0)
                ok = np.isfinite(base)
                res = {"every": detrend_on(raw, years, every), "clean": detrend_on(raw, years, clean)}
                d = {}
                for name, (mk, pool) in variants.items():
                    sel = mk[:, m]
                    s = stats.setdefault((name, cid), [0, 0, 0, 0, np.zeros(RANDOM_SETS)])
                    if sel.sum() < MIN_YEARS:
                        continue
                    rr = res["clean" if pool is clean else "every"]
                    d[name] = rr[sel].mean(axis=0)
                    comps = np.stack([rr[rng.choice(np.where(pool)[0], int(sel.sum()), replace=False)].mean(axis=0) for _ in range(RANDOM_SETS)])
                    hit = noticeable(d[name], base, field) & ok
                    real = (np.abs(d[name]) > np.percentile(np.abs(comps), 90, axis=0)) & ok
                    s[0] += ok.sum()
                    s[1] += hit.sum()
                    s[2] += real.sum()
                    s[3] += (real & hit).sum()
                    s[4] += np.array([(noticeable(c, base, field) & ok).sum() for c in comps])
                for p in pairs:
                    if p[0] in d and p[1] in d:
                        x, y = d[p[0]][ok], d[p[1]][ok]
                        c = cmp.setdefault((p, cid), np.zeros(7))
                        c += [ok.sum(), noticeable(d[p[0]] - d[p[1]], base, field)[ok].sum(), x.sum(), y.sum(), (x * x).sum(), (y * y).sum(), (x * y).sum()]
            log(f"  checked {field} {cid}")
        out += ["", f"## {field}", "", "real / both (10 % by chance); noticeable (random sets' 90th percentile)", ""]
        out += ["| variant | " + " | ".join(conts) + " |", "|---|" + "---|" * len(conts)]
        for name in variants:
            cells = []
            for cid in conts:
                n, hit, real, both, rnd = stats[(name, cid)]
                cells.append("–" if n == 0 else f"{real / n:.0%} / {both / n:.0%}; {hit / n:.0%} ({np.percentile(rnd / n, 90):.0%})")
            out.append(f"| {name} | " + " | ".join(cells) + " |")
        out += ["", "Pairs: share of cell-months where the two averages differ noticeably; correlation of their patterns", ""]
        out += ["| pair | " + " | ".join(conts) + " |", "|---|" + "---|" * len(conts)]
        for p in pairs:
            cells = []
            for cid in conts:
                if (p, cid) not in cmp:
                    cells.append("–")
                    continue
                n, diff, sx, sy, sxx, syy, sxy = cmp[(p, cid)]
                r = (sxy / n - sx / n * sy / n) / np.sqrt((sxx / n - (sx / n) ** 2) * (syy / n - (sy / n) ** 2))
                cells.append(f"{diff / n:.0%}, r={r:.2f}")
            out.append(f"| {p[0]} vs {p[1]} | " + " | ".join(cells) + " |")
        del a16
    text = "\n".join(out) + "\n"
    path = DIR / f"checks-{years[0]}-{years[-1]}.md"
    path.write_text(text)
    print(text)
    log(f"  wrote {path.relative_to(pipeline.ROOT)}")


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(prog="python -m forkcast_data.variants_research", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="y0", type=int, default=HISTORY[0], help="first year analysed")
    ap.add_argument("--to", dest="y1", type=int, default=HISTORY[1], help="last year analysed")
    ap.add_argument("command", nargs="?", default="analyse", choices=["analyse", "checks"])
    a = ap.parse_args(argv)
    years = list(range(a.y0, a.y1 + 1))
    if a.command == "analyse":
        log("analyse variants")
        analyse(years)
    else:
        log("download DMI")
        log("  " + ensure(DMI_FILE, lambda to: http_get(DMI_URL, to), _check_dmi))
        log("check ENSO months")
        checks(years)


if __name__ == "__main__":
    main()
