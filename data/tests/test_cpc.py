"""How far single days stray: measured around the seasonal curve, per month."""

import numpy as np

from forkcast_data import cpc


def test_monthly_spread_leaves_out_the_seasons():
    days = np.arange("1991-01-01", "2021-01-01", dtype="datetime64[D]")
    phase = cpc._seasons(days)[:, 1]  # cos of the yearly wave
    rng = np.random.default_rng(0)
    noise = rng.normal(0, 1, len(days)) * np.where(days.astype("datetime64[M]").astype(int) % 12 == 0, 5, 2)
    x = (10 - 12 * phase + noise)[:, None]  # a 24 °C yearly swing, ±5 °C in January, ±2 °C otherwise
    x[5, 0] = np.nan  # a missing day
    sd = cpc.monthly_spread(x, days)[:, 0]
    assert abs(sd[0] - 5) < 0.3
    assert np.all(np.abs(sd[2:11] - 2) < 0.15)  # not the season's slope


def test_regrid_is_bilinear_and_wraps_round():
    lat = np.array([1.0, 0.0])
    lon = np.arange(0.5, 360, 1.0)  # CPC's 0–360, here at 1°
    east = np.where(lon > 180, lon - 360, lon)
    a = np.stack([east, east])[None]  # (1, lat, lon): each cell's longitude, −179.5 … 179.5
    out = cpc.regrid(a, lat, lon, np.array([0.5]), np.array([1.0, 90.25, 0.0]))
    assert np.allclose(out[0, 0], [1.0, 90.25, 0.0])  # 0° between 359.5 (−0.5) and 0.5


def test_fill_spreads_to_the_coast():
    a = np.array([[[1.0, np.nan, np.nan]]])
    assert np.allclose(cpc._fill(a, steps=2), 1.0)
