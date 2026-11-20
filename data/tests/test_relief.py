import numpy as np

from forkcast_data import relief


def world() -> np.ndarray:
    """A world at 0.1° whose height is its row × 10000 + column, columns from 180° W."""
    rows, cols = 1801, 3600
    return np.arange(rows)[:, None] * 10000.0 + np.arange(cols)[None, :]


def test_a_tile_starts_at_its_north_west_corner():
    t = relief.cut(world(), 40, 0)
    assert t.shape == (relief.SIZE, relief.SIZE)
    assert t[0, 0] == 400 * 10000 + 1800  # 50° N, 0° E
    assert t[-1, -1] == 500 * 10000 + 1900  # 40° N, 10° E: shared with the neighbours


def test_columns_wrap_round_at_180_degrees():
    t = relief.cut(world(), 0, 170)
    assert t[0, -1] == 800 * 10000 + 0  # 180° E is 180° W


def test_heights_are_little_endian_metres():
    b = relief.encode(np.array([[1.4, -2.6], [4000, 40000]]))
    assert np.frombuffer(b, "<i2").tolist() == [1, -3, 4000, 32767]
