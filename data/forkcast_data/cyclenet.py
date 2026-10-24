"""Cycle network: OpenStreetMap's international bicycle routes, for drawing
routes that follow them (the app snaps clicks to it and routes along it).

- download: the ways of every international bicycle route relation (network
  icn; in Europe essentially EuroVelo, elsewhere little) from the Overpass API,
  one query per 20° × 20° tile of each continent, one at a time with a pause
  between. Each tile is cached on its own in
  cache/cyclenet/<continent>/<networks>/<tile>.json.gz as
  {"ways": {id: [[lon, lat], …]}}, so an interrupted run picks up where it
  stopped, and a different choice of networks starts its own cache. National
  (ncn) and regional (rcn) routes are left out for now; see data/README.md for
  what they would weigh.
- build: out/<continent>/cyclenet.json, {"lines": [[[lon, lat], …], …]}: every
  way once (ways cross tile edges), joined end to end into long lines where
  exactly two meet (OSM splits routes into many short ways), simplified to
  about 300 m and rounded to 0.001° (about 100 m). The app fetches a
  continent's file only when that continent is shown and the rider draws with
  snapping on.

Data © OpenStreetMap contributors, ODbL: credited on the map and the help page.

Usage: uv run python -m forkcast_data download cyclenet | build cyclenet [--fresh]
"""

import gzip
import json
import math
import sys
import time
import urllib.parse
from pathlib import Path

from . import continents, pipeline
from .continents import CONTINENTS
from .pipeline import CACHE, OUT, Stamp, code_hash, ensure, http_get, log

DIR = CACHE / "cyclenet"
OVERPASS = "https://overpass-api.de/api/interpreter"
NETWORKS = ("icn",)
TILE = 20.0  # degrees: few queries, and a failed one only redoes its tile
PAUSE = 5.0  # seconds between queries, to share the public server politely
SIMPLIFY = 0.003  # degrees, about 300 m


def _continents() -> list[dict]:
    return CONTINENTS


def tiles(bbox) -> list[tuple[float, float, float, float]]:
    """Tiles (south, west, north, east) covering a continent's box."""
    w0, s0, e0, n0 = bbox
    out = []
    lat = math.floor(s0 / TILE) * TILE
    while lat < n0:
        lon = math.floor(w0 / TILE) * TILE
        while lon < e0:
            out.append((lat, lon, lat + TILE, lon + TILE))
            lon += TILE
        lat += TILE
    return out


def tile_file(continent_id: str, tile) -> Path:
    s, w, _, _ = tile
    return DIR / continent_id / "-".join(NETWORKS) / f"{s:+06.1f}_{w:+07.1f}.json.gz"


def _query(tile) -> str:
    s, w, n, e = tile
    networks = "|".join(NETWORKS)
    return (
        "[out:json][timeout:900][maxsize:1073741824];"
        f'relation["type"="route"]["route"="bicycle"]["network"~"^({networks})$"]({s},{w},{n},{e});'
        "way(r);out geom;"
    )


def _fetch(tile):
    def fetch(to: Path) -> None:
        raw = to.with_name(to.name + ".raw")
        http_get(f"{OVERPASS}?data={urllib.parse.quote(_query(tile))}", raw, timeout=1000)
        data = json.loads(raw.read_text())
        raw.unlink()
        # Overpass answers 200 with a "remark" when a query hits its limits.
        remark = data.get("remark", "")
        if "error" in remark.lower():
            raise RuntimeError(remark)
        ways = {
            str(el["id"]): [[p["lon"], p["lat"]] for p in el["geometry"]]
            for el in data.get("elements", [])
            if el.get("type") == "way" and el.get("geometry")
        }
        with gzip.open(to, "wt") as f:
            json.dump({"ways": ways}, f, separators=(",", ":"))
        time.sleep(PAUSE)

    return fetch


def _validate(path: Path) -> None:
    with gzip.open(path, "rt") as f:
        if "ways" not in json.load(f):
            raise ValueError(f"no ways in {path.name}")


def download(fresh: bool = False) -> None:
    for c in _continents():
        ts = tiles(c["bbox"])
        log(f"  {c['id']}: {len(ts)} tiles of {TILE:g}°")
        for i, t in enumerate(ts, 1):
            status = ensure(tile_file(c["id"], t), _fetch(t), _validate, fresh)
            log(f"  [{i:3}/{len(ts)}] {status}")


def files() -> list[Path]:
    return [tile_file(c["id"], t) for c in _continents() for t in tiles(c["bbox"])]


def outputs() -> list[Path]:
    return [OUT / c["id"] / "cyclenet.json" for c in _continents()]


def _simplify(line: list, tol: float) -> list:
    """Douglas–Peucker in degrees: keep the points that bend the line."""
    if len(line) < 3:
        return line
    keep = [False] * len(line)
    keep[0] = keep[-1] = True
    stack = [(0, len(line) - 1)]
    while stack:
        a, b = stack.pop()
        (x1, y1), (x2, y2) = line[a], line[b]
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy) or 1e-12
        far, at = 0.0, -1
        for i in range(a + 1, b):
            x, y = line[i]
            d = abs(dy * (x - x1) - dx * (y - y1)) / length
            if d > far:
                far, at = d, i
        if far > tol:
            keep[at] = True
            stack += [(a, at), (at, b)]
    return [p for p, k in zip(line, keep) if k]


def _join(ways: list[list]) -> list[list]:
    """Join ways end to end where exactly two meet, so a route that OSM splits
    into many short ways becomes one long line (simplifying then works, and
    the file shrinks). Junctions of three or more stay line ends."""
    key = lambda p: (round(p[0], 6), round(p[1], 6))  # noqa: E731
    ends: dict[tuple, list[int]] = {}
    for i, w in enumerate(ways):
        for p in (w[0], w[-1]):
            ends.setdefault(key(p), []).append(i)
    used = [False] * len(ways)
    lines = []
    for start in range(len(ways)):
        if used[start]:
            continue
        used[start] = True
        line = list(ways[start])
        for forward in (True, False):
            while True:
                tip = key(line[-1] if forward else line[0])
                nxt = [j for j in ends.get(tip, []) if not used[j]]
                if len(ends.get(tip, [])) != 2 or not nxt:
                    break
                j = nxt[0]
                used[j] = True
                w = ways[j]
                if forward:
                    # Append: the way must start at the tip.
                    line += (w if key(w[0]) == tip else w[::-1])[1:]
                else:
                    # Prepend: the way must end at the tip.
                    line = (w if key(w[-1]) == tip else w[::-1])[:-1] + line
        lines.append(line)
    return lines


def build(fresh: bool = False) -> None:
    stamp = Stamp("cyclenet", files(), outputs(), code_hash(sys.modules[__name__], continents, pipeline))
    if not fresh and stamp.up_to_date():
        log("  cycle network is up to date")
        return
    if stamp.missing_inputs():
        raise SystemExit("Missing cycle-network tiles. Run: download cyclenet")
    for c in _continents():
        ways: dict[str, list] = {}
        for t in tiles(c["bbox"]):
            with gzip.open(tile_file(c["id"], t), "rt") as f:
                ways.update(json.load(f)["ways"])
        lines = []
        points = 0
        for coords in _join(list(ways.values())):
            line = [[round(x, 3), round(y, 3)] for x, y in _simplify(coords, SIMPLIFY)]
            line = [p for i, p in enumerate(line) if i == 0 or p != line[i - 1]]
            if len(line) > 1:
                lines.append(line)
                points += len(line)
        path = OUT / c["id"] / "cyclenet.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"lines": lines}, separators=(",", ":")))
        gz = len(gzip.compress(path.read_bytes(), 9))
        log(f"  {c['id']:14} {len(ways):6} ways -> {len(lines)} lines, {points} points, {path.stat().st_size / 1e6:.1f} MB ({gz / 1e6:.1f} MB gzipped)")
    stamp.done()
