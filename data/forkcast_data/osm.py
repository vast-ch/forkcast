"""OpenStreetMap: the single source of the routes, from a planet file.

- download `osm`: the whole planet as cache/osm/planet.osm.pbf (about 96 GB),
  from planet.openstreetmap.org (which hands it to a fast mirror). The dated
  file that "latest" points to is picked once and written next to the
  download (planet.osm.pbf.source), so an interrupted download resumes the
  same file, even days later; it is checked against the planet's published
  MD5. --fresh fetches the newest planet.
- build `bicycle`: every bicycle route relation (`route=bicycle`, every
  network) with its member ways, child routes and their nodes, cut out with
  osmium into cache/osm/bicycle.osm.pbf (a few hundred MB, some minutes).
  The cycle network and the EuroVelo routes are built from that.

Why a planet file and not the Overpass API: the public Overpass servers are
shared and often overloaded, so fetching hundreds of routes from them took
days and failed half the time. A planet download is one plain HTTPS file
that resumes, and filtering it is local and repeatable.

Data © OpenStreetMap contributors, ODbL: credited on the map and the help page.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from . import pipeline
from .pipeline import CACHE, UA, Stamp, code_hash, ensure, log

DIR = CACHE / "osm"
PLANET = DIR / "planet.osm.pbf"
SOURCE = DIR / "planet.osm.pbf.source"
BICYCLE = DIR / "bicycle.osm.pbf"
SERVER = "https://planet.openstreetmap.org/pbf/"
CHUNK = 8 << 20


def _latest() -> str:
    """The dated name "planet-latest" redirects to, e.g. planet-261026.osm.pbf."""
    req = urllib.request.Request(SERVER + "planet-latest.osm.pbf", method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        name = Path(urllib.parse.urlparse(r.url).path).name
    if not name.startswith("planet-") or name == "planet-latest.osm.pbf":
        raise RuntimeError(f"could not tell which planet is the latest (got {name})")
    return name


def _md5_of(name: str) -> str:
    req = urllib.request.Request(SERVER + name + ".md5", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode().split()[0]


def _fetch(tmp: Path) -> None:
    """Download the planet named in SOURCE to `tmp`, resuming what is there."""
    name = SOURCE.read_text().split()[0]
    req = urllib.request.Request(SERVER + name, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        total = int(r.headers["Content-Length"])
    have = tmp.stat().st_size if tmp.exists() else 0
    if have > total:
        tmp.unlink()
        have = 0
    if have == total:
        return
    req = urllib.request.Request(SERVER + name, headers={"User-Agent": UA, "Range": f"bytes={have}-"})
    t0, last = time.time(), time.time()
    start = have
    with urllib.request.urlopen(req, timeout=300) as r, open(tmp, "ab") as f:
        if have and r.status != 206:
            raise RuntimeError("the server would not resume the download")
        while chunk := r.read(CHUNK):
            f.write(chunk)
            have += len(chunk)
            if time.time() - last > 60:
                last = time.time()
                rate = (have - start) / (last - t0)
                log(f"    {name}: {have / 1e9:.1f} of {total / 1e9:.1f} GB, {rate / 1e6:.1f} MB/s, {(total - have) / rate / 60:.0f} min left")
    if have != total:
        raise RuntimeError(f"stopped at {have} of {total} bytes")


def _validate(path: Path) -> None:
    want = SOURCE.read_text().split()[1]
    h = hashlib.md5()
    with open(path, "rb") as f:
        while chunk := f.read(CHUNK):
            h.update(chunk)
    if h.hexdigest() != want:
        path.unlink()  # so the next try starts over instead of "resuming" a full, broken file
        raise ValueError(f"MD5 {h.hexdigest()} is not the published {want}")


def download(fresh: bool = False) -> None:
    DIR.mkdir(parents=True, exist_ok=True)
    tmp = PLANET.with_name(PLANET.name + ".part")
    if fresh or not SOURCE.exists():
        name = _latest()
        if SOURCE.exists() and SOURCE.read_text().split()[0] != name:
            tmp.unlink(missing_ok=True)  # a part of an older planet can't be resumed
        SOURCE.write_text(f"{name} {_md5_of(name)}\n")
    log(f"  planet: {SOURCE.read_text().split()[0]}")
    log("  " + ensure(PLANET, _fetch, _validate, fresh=fresh, retries=20))


def outputs() -> list[Path]:
    return [BICYCLE]


def build(fresh: bool = False) -> None:
    if not PLANET.exists():
        raise SystemExit("Missing the OpenStreetMap planet. Run: download osm")
    stamp = Stamp("bicycle", [PLANET], outputs(), code_hash(sys.modules[__name__], pipeline))
    if not fresh and stamp.up_to_date():
        log("  bicycle routes are up to date")
        return
    tmp = BICYCLE.with_name("bicycle.part.osm.pbf")
    # Matching relations plus everything they reference: child routes, ways, nodes.
    subprocess.run(
        ["osmium", "tags-filter", "--overwrite", "-o", str(tmp), str(PLANET), "r/route=bicycle"],
        check=True,
    )
    tmp.replace(BICYCLE)
    log(f"  {BICYCLE.name}: {BICYCLE.stat().st_size / 1e6:.0f} MB")
    stamp.done()


# --- Reading the bicycle routes -------------------------------------------------


Member = tuple[str, int, str]  # type ("n", "w", "r"), id, role


def relations(path: Path | None = None) -> dict[int, tuple[dict[str, str], list[Member]]]:
    """Every relation in the file: its tags and its members, in order."""
    import osmium

    return {
        r.id: (dict(r.tags), [(m.type, m.ref, m.role) for m in r.members])
        for r in osmium.FileProcessor(str(path or BICYCLE), osmium.osm.RELATION)
    }


def member_ways(rels, root: int, skip_roles: frozenset[str] = frozenset()) -> list[int]:
    """The ways of a relation and of its child relations, in member order,
    leaving out members (ways or child relations) whose role is in `skip_roles`."""
    out: list[int] = []
    seen = {root}
    stack = [root]
    while stack:
        rel = rels.get(stack.pop())
        if rel is None:
            continue  # a child outside the file (not a bicycle route)
        children = []
        for kind, ref, role in rel[1]:
            if role in skip_roles:
                continue
            if kind == "w":
                out.append(ref)
            elif kind == "r" and ref not in seen:
                seen.add(ref)
                children.append(ref)
        stack.extend(reversed(children))
    return out


def way_nodes(ids, path: Path | None = None) -> dict[int, list[tuple[int, float, float]]]:
    """The given ways as (node id, lon, lat) points; ways without locations are left out."""
    import osmium

    wanted = set(ids)
    out = {}
    for w in osmium.FileProcessor(str(path or BICYCLE), osmium.osm.NODE | osmium.osm.WAY).with_locations():
        if w.is_way() and w.id in wanted:
            pts = [(n.ref, n.lon, n.lat) for n in w.nodes if n.location.valid()]
            if len(pts) > 1:
                out[w.id] = pts
    return out
