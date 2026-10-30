
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
    coef, static = pack.curves(data, header)
    tolerance = {"tmx": 0.3, "tmn": 0.3, "pre": 0.3, "r1": 0.01, "r5": 0.01, "r10": 0.01}  # °C, mm a day, share of days
    for n in header["vars"]:
        b = pack.encode(n, coef[n])
        got = pack.evaluate(pack.decode(n, b), PHASE)
        monthly = variants.decode(n, _monthly(n, LAYERS[n]))
        want = pack.evaluate(pack.fit(monthly.astype(np.float64), n not in ("tmx", "tmn")), PHASE)
        assert np.nanmax(np.abs(got - want)[:, 0, 0]) < tolerance[n], n
        assert np.isnan(got[:, 0, 1]).all(), f"{n}: sea stays without data"
    # The static layer is carried over as it was.
    assert static.ravel().tolist() == era5land.encode("elev", np.array([[800.0, np.nan]])).ravel().tolist()


WORLD = {"lon0": -180.0, "lat0": 84.0, "step": 0.25, "rows": 577, "cols": 1440}


def test_tiles_cover_the_world_and_share_their_edges():
    t = pack.tiles(WORLD)
    rows, cols = t["40_10"]
    assert len(rows) == len(cols) == 41
    # 50° N is row 136 (84 − 136 × 0.25); 10° E is column 760.
    assert (rows[0], rows[-1], cols[0], cols[-1]) == (136, 176, 760, 800)
    east_rows, east_cols = t["40_20"]
    assert east_cols[0] == cols[-1], "neighbours share their edge column"
    assert t["30_10"][0][0] == rows[-1], "and their edge row"
    # The last column of the tile at 170° E is 180°, which is −180°: column 0.
    assert t["40_170"][1][-1] == 0
    assert "80_0" in t and "-60_0" in t and "-70_0" not in t


def test_tiles_beyond_the_grid_are_sea():
    a = np.zeros((1, 3, 4), dtype=np.uint8)
    out = pack._cut(a, np.array([-1, 0, 1]), np.array([3, 0]))
    assert out[0, 0].tolist() == [era5land.NODATA] * 2
    assert out[0, 1:].tolist() == [[0, 0], [0, 0]]


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
