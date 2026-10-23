"""Shared machinery for the data pipeline: resumable downloads and build stamps.

Downloads (`ensure`)
    A file is fetched to `<name>.part`, checked by a validator, and only then
    renamed into place, so a half-finished download never looks complete.
    A file that passed validation is remembered (by size and modification time)
    in cache/.verified.json, so later runs skip it without re-checking. With
    `fresh=True` the file is fetched again regardless.

Builds (`Stamp`)
    A build records what it was made from in cache/.stamps/<step>.json: the
    size and modification time of every input file, a hash of the code that
    builds it, and its parameters. If that record still matches and every
    output exists, the build is skipped. With `fresh=True` it always runs.
"""

from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path
from typing import Callable, Iterable

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "cache"
OUT = ROOT / "out"
VERIFIED = CACHE / ".verified.json"
STAMPS = CACHE / ".stamps"
UA = "forkcast-build/0.2 (https://github.com/vast-ch/forkcast)"


def log(msg: str) -> None:
    print(msg, flush=True)


def _sig(path: Path) -> list[int]:
    st = path.stat()
    return [st.st_size, st.st_mtime_ns]


def _load(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1, sort_keys=True))
    tmp.replace(path)


# --- Downloads -----------------------------------------------------------------


def is_verified(path: Path) -> bool:
    """True if `path` exists and passed validation in its current state."""
    if not path.exists():
        return False
    return _load(VERIFIED).get(str(path.relative_to(ROOT))) == _sig(path)


def mark_verified(path: Path) -> None:
    data = _load(VERIFIED)
    data[str(path.relative_to(ROOT))] = _sig(path)
    _save(VERIFIED, data)


def ensure(
    path: Path,
    fetch: Callable[[Path], None],
    validate: Callable[[Path], None],
    fresh: bool = False,
    retries: int = 3,
) -> str:
    """Make sure `path` exists and is valid; fetch it otherwise.

    `fetch(tmp)` writes the file to `tmp`. `validate(p)` raises if `p` is not a
    complete, correct file. Returns a short status for the log.
    """
    name = path.name
    if not fresh and path.exists():
        if is_verified(path):
            return f"have {name}"
        try:
            validate(path)
            mark_verified(path)
            return f"have {name} (checked)"
        except Exception as e:  # noqa: BLE001 - any failure means "fetch again"
            log(f"  {name} is not valid ({e}); fetching again")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".part")
    t0 = time.time()
    for attempt in range(1, retries + 1):
        try:
            fetch(tmp)
            validate(tmp)
            tmp.replace(path)
            mark_verified(path)
            size = path.stat().st_size / 1e6
            return f"got {name} ({size:.1f} MB, {(time.time() - t0) / 60:.1f} min)"
        except Exception as e:  # noqa: BLE001 - network, server or validation errors
            if attempt == retries:
                raise RuntimeError(f"could not get {name}: {e}") from e
            log(f"  {name}: attempt {attempt} failed ({str(e)[:200]}); retrying")
            time.sleep(30 * attempt)
    raise AssertionError("unreachable")


def http_get(url: str, to: Path, timeout: int = 600) -> None:
    import urllib.request

    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r, open(to, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)


# --- Builds --------------------------------------------------------------------


def code_hash(*modules) -> str:
    h = hashlib.sha1()
    for m in modules:
        h.update(Path(m.__file__).read_bytes())
    return h.hexdigest()[:12]


class Stamp:
    """Decides whether a build step needs to run, and records it when it did."""

    def __init__(self, step: str, inputs: Iterable[Path], outputs: Iterable[Path], code: str, params: dict | None = None):
        self.path = STAMPS / f"{step}.json"
        self.inputs = sorted(set(inputs))
        self.outputs = sorted(set(outputs))
        self.code = code
        self.params = params or {}

    def _record(self) -> dict:
        return {
            "code": self.code,
            "params": self.params,
            "inputs": {str(p.relative_to(ROOT)): _sig(p) for p in self.inputs},
        }

    def missing_inputs(self) -> list[Path]:
        return [p for p in self.inputs if not p.exists()]

    def up_to_date(self) -> bool:
        if self.missing_inputs() or not all(p.exists() for p in self.outputs):
            return False
        return _load(self.path) == self._record()

    def done(self) -> None:
        _save(self.path, self._record())
