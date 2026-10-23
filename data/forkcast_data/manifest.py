"""Build out/manifest.json: what the app can load, per continent.

Lists each continent with its bounding box, its download size (climate grid +
borders, before compression) and the preset routes on it.

Usage: uv run python -m forkcast_data build manifest [--fresh]
"""

import gzip
import json
import sys

from . import continents, pipeline
from .continents import CONTINENTS
from .pipeline import OUT, Stamp, code_hash, log


def build(fresh: bool = False):
    inputs = [OUT / "routes" / "index.json"]
    inputs += [OUT / c["id"] / f for c in CONTINENTS for f in ("climate.bin", "climate.json", "countries.json")]
    stamp = Stamp("manifest", inputs, [OUT / "manifest.json"], code_hash(sys.modules[__name__], continents, pipeline))
    if not fresh and stamp.up_to_date():
        log("  manifest is up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing {missing[0].relative_to(pipeline.ROOT)}. Run the builds before the manifest.")
    index = json.loads((OUT / "routes" / "index.json").read_text())["routes"]
    entries = []
    for c in CONTINENTS:
        d = OUT / c["id"]
        files = [d / f for f in ("climate.bin", "climate.json", "countries.json")]
        size = sum(f.stat().st_size for f in files)
        # Roughly what the browser downloads, since the server sends these gzipped.
        gz = sum(len(gzip.compress(f.read_bytes(), compresslevel=6, mtime=0)) for f in files)
        entries.append({
            "id": c["id"],
            "name": c["name"],
            "bbox": c["bbox"],
            "bytes": size,
            "gzipBytes": gz,
            "routes": [r for r in index if r.get("continent") == c["id"]],
        })
        log(f"  {c['id']:14} {size / 1e6:5.1f} MB ({gz / 1e6:.1f} MB gzipped), {len(entries[-1]['routes'])} routes")
    (OUT / "manifest.json").write_text(json.dumps({"continents": entries}, separators=(",", ":"), ensure_ascii=False))
    stamp.done()
