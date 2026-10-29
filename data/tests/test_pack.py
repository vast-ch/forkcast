import json

import numpy as np
import pytest

from forkcast_data import era5land, pack, variants

PHASE = (np.arange(365) + 0.5) / 365


def _monthly(name: str, values: np.ndarray) -> np.ndarray:
    """12 monthly values for a 1×2 grid (the second cell sea) as era5land stores them."""
    v = np.stack([values, np.full(12, np.nan)], axis=1)[:, None, :]
    return era5land.encode(name, v)


def _grid(layers: dict[str, np.ndarray]) -> tuple[bytes, dict]:
    names = list(layers)
    elev = era5land.encode("elev", np.array([[800.0, np.nan]]))
    data = np.stack([_monthly(n, layers[n]) for n in names]).tobytes() + elev.tobytes()
    header = {"rows": 1, "cols": 2, "vars": names, "static": ["elev"], "encoding": era5land.ENCODING, "nodata": era5land.NODATA}
    return data, header


SEASON = 0.5 - 0.5 * np.cos(2 * np.pi * (np.arange(12) + 0.5) / 12)  # 0 in January, 1 in July
LAYERS = {
    "tmx": -15 + 45 * SEASON,  # a continental climate: −15 … +30 °C
    "tmn": -25 + 40 * SEASON,
    "pre": 5 + 300 * SEASON**4,  # a monsoon: nearly dry, then 300 mm
    "r1": 1 + 25 * SEASON**4,
    "r5": 0.5 + 18 * SEASON**4,
    "r10": 0.2 + 12 * SEASON**4,
}


def test_packed_curves_match_the_monthly_fit():
    data, header = _grid(LAYERS)
    packed, h = pack.pack(data, header)
    assert h["terms"] == pack.TERMS
    raw = np.frombuffer(packed, dtype=np.uint8)
    cells = 2
    tolerance = {"tmx": 0.3, "tmn": 0.3, "pre": 0.3, "r1": 0.01, "r5": 0.01, "r10": 0.01}  # °C, mm a day, share of days
    for i, n in enumerate(header["vars"]):
        b = raw[i * pack.TERMS * cells : (i + 1) * pack.TERMS * cells].reshape(pack.TERMS, 1, cells)
        got = pack.evaluate(pack.decode(n, b), PHASE)
        monthly = variants.decode(n, _monthly(n, LAYERS[n]))
        want = pack.evaluate(pack.fit(monthly.astype(np.float64), n not in ("tmx", "tmn")), PHASE)
        assert np.nanmax(np.abs(got - want)[:, 0, 0]) < tolerance[n], n
        assert np.isnan(got[:, 0, 1]).all(), f"{n}: sea stays without data"
    # The static layer is carried over as it was.
    assert raw[-2:].tolist() == era5land.encode("elev", np.array([[800.0, np.nan]])).ravel().tolist()
    json.dumps(h)


def test_the_fit_reproduces_monthly_averages():
    # Averaged over each month, the curve gives back the month's value (the
    # flattening correction undoes what averaging over a month takes away).
    c = pack.fit(LAYERS["tmx"][:, None], per_day=False)
    days = np.repeat(np.arange(12), 1000)
    phase = (np.arange(12000) + 0.5) / 12000
    curve = pack.evaluate(c, phase)[:, 0]
    means = np.array([curve[days == m].mean() for m in range(12)])
    assert np.allclose(means, LAYERS["tmx"], atol=0.5)


def test_values_outside_an_encoding_stop_the_build():
    c = pack.fit(np.full((12, 1), 80.0), per_day=False)  # a mean high of 80 °C
    with pytest.raises(SystemExit, match="outside the encoding"):
        pack.encode("tmx", c)
