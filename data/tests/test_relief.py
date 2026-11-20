import numpy as np
import pytest

from forkcast_data import relief

ROWS, COLS = 180 * 60, 360 * 60


def flat(h: float) -> np.ndarray:
    return np.full((ROWS, COLS), h, dtype=np.int16)


def test_a_tile_runs_from_its_north_west_corner():
    z = np.zeros((ROWS, COLS), dtype=np.int16)
    z[:, :] = (np.arange(ROWS) // 60)[:, None]  # each row its whole degree north of 90° S
    t = relief.cut(z, 40, 0)
    assert t.shape == (relief.SIZE, relief.SIZE)
    assert t[5, 0] == 139  # 49.75° N
    assert t[-6, 0] == 130  # 40.25° N


def test_each_height_is_the_mean_of_the_3_minute_box_around_its_point():
    z = flat(0)
    # The point at 0° N, 0° E: its box is 1.5′ either way, the cells beside it whole, the next ones half.
    r, c = 90 * 60, 180 * 60
    z[r - 2 : r + 2, c - 2 : c + 2] = 900
    t = relief.cut(z, -10, 0)
    assert t[0, 0] == pytest.approx(900)  # the box is all inside the raised square
    z[r - 2, :] = 0  # half a row of the box down to 0
    assert relief.cut(z, -10, 0)[0, 0] == pytest.approx(900 * (1 - 0.5 / 3))


def test_columns_wrap_round_at_180_degrees():
    z = flat(0)
    z[:, :2] = 300  # just east of 180° W
    z[:, -2:] = 300  # just west of 180° E
    assert relief.cut(z, 0, 170)[0, -1] == pytest.approx(300)


def test_the_sea_floor_is_flat():
    assert relief.cut(flat(-4000), 0, 0).max() == 0


def test_heights_are_little_endian_metres():
    b = relief.encode(np.array([[1.4, -2.6], [4000, 40000]]))
    assert np.frombuffer(b, "<i2").tolist() == [1, -3, 4000, 32767]
