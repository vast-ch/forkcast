"""Build out/manifest.json: what the app can load, per continent.

Lists each continent with its bounding box, its download size (climate grid +
borders, before compression) and the preset routes on it.

Usage: uv run python -m wheelther_data.manifest
"""

import gzip
import json
from pathlib import Path

from .continents import CONTINENTS

OUT = Path(__file__).resolve().parent.parent / "out"


def main():
    index = json.loads((OUT / "routes" / "index.json").read_text())["routes"]
    continents = []
    for c in CONTINENTS:
        d = OUT / c["id"]
        files = [d / f for f in ("climate.bin", "climate.json", "countries.json")]
        size = sum(f.stat().st_size for f in files)
        # Roughly what the browser downloads, since the server sends these gzipped.
        gz = sum(len(gzip.compress(f.read_bytes(), compresslevel=6, mtime=0)) for f in files)
        continents.append({
            "id": c["id"],
            "name": c["name"],
            "bbox": c["bbox"],
            "bytes": size,
            "gzipBytes": gz,
            "routes": [r for r in index if r.get("continent") == c["id"]],
        })
        print(f"  {c['id']:14} {size / 1e6:5.1f} MB ({gz / 1e6:.1f} MB gzipped), {len(continents[-1]['routes'])} routes")
    (OUT / "manifest.json").write_text(json.dumps({"continents": continents}, separators=(",", ":"), ensure_ascii=False))


if __name__ == "__main__":
    main()
