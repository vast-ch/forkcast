"""Cycle network: OpenStreetMap's international bicycle routes, for drawing
routes that follow them (the app snaps clicks to it and routes along it).

Fetched from the public Overpass API by route, not by area, so no query has to
scan a large region (those are what time out on a busy server):

- download:
  1. index: one small query lists every international bicycle route relation
     (network icn; in Europe essentially EuroVelo, elsewhere little) with its
     id, version and bounding box: cache/cyclenet/<networks>/index.json.gz.
  2. routes: the ways of each route, fetched BATCH routes per query (Overpass
     `foreach` keeps them apart) and cached per route and version in
     cache/cyclenet/<networks>/rel-<id>-v<version>.json.gz, so a rerun fetches
     only new or changed routes (rerun with --fresh to refresh the index).
  Every request goes to the first Overpass server that answers, waits when a
  server asks it to (429), backs off with jitter, and gives up on a single route
  only after all tries; a batch that keeps failing is retried route by route.
  Routes that still fail are listed and skipped, never stopping the run: the
  next run fetches just those.
- build: out/<continent>/cyclenet.json, {"lines": [[[lon, lat], …], …]}: the
  ways of every route whose box touches the continent, each way once, joined
  end to end into long lines where exactly two meet, simplified to about 300 m
  and rounded to 0.001° (about 100 m). Missing routes are reported, not fatal.
  The app fetches a continent's file only when that continent is shown and the
  rider draws with snapping on.

Data © OpenStreetMap contributors, ODbL: credited on the map and the help page.

Usage: uv run python -m forkcast_data download cyclenet | build cyclenet [--fresh]
"""

import gzip
import json
import math
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from . import continents, pipeline
from .continents import CONTINENTS
from .pipeline import CACHE, OUT, UA, Stamp, code_hash, is_verified, log, mark_verified

NETWORKS = ("icn",)
DIR = CACHE / "cyclenet" / "-".join(NETWORKS)
INDEX = DIR / "index.json.gz"
# Public Overpass servers, tried in turn when one fails or is full.
SERVERS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
)
BATCH = 10  # routes per query
TRIES = 8  # per request, across the servers
PAUSE = 5.0  # seconds between requests, to share the public servers politely
SIMPLIFY = 0.003  # degrees, about 300 m


def _request(query: str, timeout: int = 600) -> dict:
    """POST a query to the Overpass servers in turn until one answers."""
    data = urllib.parse.urlencode({"data": query}).encode()
    last: Exception | None = None
    for attempt in range(TRIES):
        server = SERVERS[attempt % len(SERVERS)]
        try:
            req = urllib.request.Request(server, data=data, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                out = json.loads(r.read())
            remark = out.get("remark", "")
            if "error" in remark.lower():  # a 200 that hit the server's limits
                raise RuntimeError(remark.strip()[:200])
            time.sleep(PAUSE)
            return out
        except Exception as e:  # noqa: BLE001 - any failure means "try again"
            last = e
            wait = min(30 * (attempt + 1), 300) + random.uniform(0, 10)
            if isinstance(e, urllib.error.HTTPError) and e.code == 429:
                wait = max(wait, float(e.headers.get("Retry-After") or 60))
            host = urllib.parse.urlparse(server).hostname
            log(f"    {host}: {str(e)[:90]}; next try in {wait:.0f} s")
            time.sleep(wait)
    raise RuntimeError(f"no Overpass server answered: {last}")


def _write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".part")
    with gzip.open(tmp, "wt") as f:
        json.dump(data, f, separators=(",", ":"))
    tmp.replace(path)
    mark_verified(path)


def _read(path: Path):
    with gzip.open(path, "rt") as f:
        return json.load(f)


def _index(fresh: bool) -> list[dict]:
    """Every route: {"id", "version", "bbox": [w, s, e, n]}."""
    if fresh or not is_verified(INDEX):
        networks = "|".join(NETWORKS)
        out = _request(
            "[out:json][timeout:300];"
            f'relation["type"="route"]["route"="bicycle"]["network"~"^({networks})$"];'
            "out meta bb;"
        )
        routes = [
            {
                "id": el["id"],
                "version": el.get("version", 0),
                "bbox": [el["bounds"]["minlon"], el["bounds"]["minlat"], el["bounds"]["maxlon"], el["bounds"]["maxlat"]],
            }
            for el in out.get("elements", [])
            if el.get("type") == "relation" and el.get("bounds")
        ]
        if not routes:
            raise RuntimeError("the route index came back empty")
        _write(INDEX, {"routes": routes})
    return _read(INDEX)["routes"]


def route_file(r: dict) -> Path:
    return DIR / f"rel-{r['id']}-v{r['version']}.json.gz"


def _fetch(batch: list[dict]) -> None:
    """The ways of each route in `batch`, cached per route."""
    ids = ",".join(str(r["id"]) for r in batch)
    out = _request(
        "[out:json][timeout:600][maxsize:1073741824];"
        f"relation(id:{ids});"
        # Each route's id, then its ways (and those of any child routes).
        "foreach->.r(.r out ids;(.r;rel(r.r););way(r);out geom;);"
    )
    ways: dict[int, dict] = {r["id"]: {} for r in batch}
    current = None
    for el in out.get("elements", []):
        if el.get("type") == "relation" and el["id"] in ways:
            current = el["id"]
        elif el.get("type") == "way" and current is not None and el.get("geometry"):
            ways[current][str(el["id"])] = [[p["lon"], p["lat"]] for p in el["geometry"]]
    for r in batch:
        _write(route_file(r), {"ways": ways[r["id"]]})


def download(fresh: bool = False) -> None:
    routes = _index(fresh)
    todo = [r for r in routes if fresh or not is_verified(route_file(r))]
    log(f"  {len(routes)} routes, {len(routes) - len(todo)} cached, {len(todo)} to fetch")
    failed: list[int] = []
    for i in range(0, len(todo), BATCH):
        batch = todo[i : i + BATCH]
        try:
            _fetch(batch)
        except RuntimeError:
            log("    batch failed; trying its routes one by one")
            for r in batch:
                try:
                    _fetch([r])
                except RuntimeError as e:
                    log(f"    route {r['id']} skipped: {str(e)[:120]}")
                    failed.append(r["id"])
        log(f"  [{min(i + BATCH, len(todo)):4}/{len(todo)}] routes fetched")
    if failed:
        log(f"  {len(failed)} routes not fetched ({', '.join(map(str, failed[:10]))}{'…' if len(failed) > 10 else ''}); run again to retry them")


def _touches(box, bbox) -> bool:
    w, s, e, n = box
    return not (e < bbox[0] or w > bbox[2] or n < bbox[1] or s > bbox[3])


def files() -> list[Path]:
    """What the download should leave: the index and every route's file."""
    if not INDEX.exists():
        return [INDEX]
    return [INDEX] + [route_file(r) for r in _read(INDEX)["routes"]]


def outputs() -> list[Path]:
    return [OUT / c["id"] / "cyclenet.json" for c in CONTINENTS]


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
    if not INDEX.exists():
        raise SystemExit("Missing the cycle-route index. Run: download cyclenet")
    routes = _read(INDEX)["routes"]
    present = [r for r in routes if route_file(r).exists()]
    stamp = Stamp("cyclenet", [INDEX] + [route_file(r) for r in present], outputs(), code_hash(sys.modules[__name__], continents, pipeline))
    if not fresh and stamp.up_to_date():
        log("  cycle network is up to date")
        return
    if len(present) < len(routes):
        log(f"  {len(routes) - len(present)} of {len(routes)} routes are not downloaded yet; building without them")
    for c in CONTINENTS:
        ways: dict[str, list] = {}
        for r in present:
            if _touches(r["bbox"], c["bbox"]):
                ways.update(_read(route_file(r))["ways"])
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
        log(f"  {c['id']:14} {len(ways):6} ways -> {len(lines)} lines, {points} points, {path.stat().st_size / 1e6:.2f} MB ({gz / 1e6:.2f} MB gzipped)")
    stamp.done()
