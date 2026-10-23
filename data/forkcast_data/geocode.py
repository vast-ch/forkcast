"""Resolve route stops to coordinates with Nominatim; results are kept in geocoded.json.

Only stops missing from geocoded.json are looked up (1 request per second),
or all of them with --fresh. Run as part of: download brouter
"""

import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

from .anchors import ROUTES

CACHE = Path(__file__).with_name("geocoded.json")
UA = "forkcast-build/0.2 (https://github.com/vast-ch/forkcast)"


def main(fresh: bool = False):
    cache = {} if fresh or not CACHE.exists() else json.loads(CACHE.read_text())
    for route in ROUTES:
        for stop in route["stops"]:
            cc, name = stop[0], stop[1]
            key = f"{cc}|{name}"
            if key in cache:
                continue
            q = urllib.parse.urlencode({"q": name, "countrycodes": cc, "format": "json", "limit": 1})
            req = urllib.request.Request(f"https://nominatim.openstreetmap.org/search?{q}", headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                res = json.load(r)
            cache[key] = [float(res[0]["lat"]), float(res[0]["lon"])] if res else None
            print(("MISSING " if not res else "") + key, cache[key], flush=True)
            CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=0))
            time.sleep(1.1)


if __name__ == "__main__":
    main()
