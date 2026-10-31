import numpy as np
import pytest

from forkcast_data import ghcnd, verify_stations, warming


def test_a_steady_rise_comes_out_as_its_rate():
    years = list(range(2000, 2015))
    annual = np.array([np.full((30, 40), 10 + 0.03 * (y - 2000)) for y in years])
    assert np.allclose(warming.rate(annual, years), 0.03)


def test_the_rate_is_averaged_over_land_and_left_out_at_sea():
    years = list(range(2000, 2015))
    annual = np.array([np.full((30, 40), 0.03 * (y - 2000)) for y in years])
    annual[:, 15, 20] = 0.0  # one cell that didn't warm
    annual[:, 0, 0] = np.nan  # sea
    r = warming.rate(annual, years)
    assert np.isnan(r[0, 0])
    assert 0.0 < r[15, 20] < 0.03  # borrows its neighbours' warming
    assert r[15, 20] == pytest.approx(0.03 * (1 - 1 / 21**2))


def test_smoothing_wraps_round_the_globe():
    a = np.zeros((1, 5, 40))
    a[0, 2, 0] = 9.0
    s = warming.smooth(a, 3)
    assert s[0, 2, -1] == pytest.approx(1.0)  # the last column sees the first


def test_each_climate_is_brought_forward_from_the_middle_of_its_years():
    app = (2011, 2025)
    assert warming.shift_years("last15", app) == 8.0  # 2018 → 2026
    assert warming.shift_years("last10", app) == 5.5
    assert warming.shift_years("last5", app) == 3.0
    assert warming.shift_years("last1", app) == 0.0  # the one year, as it was
    assert warming.shift_years("elnino", app) == 8.0  # 15 yrs plus a correction


def test_station_lines_are_read_by_their_columns():
    text = (
        "SZ000006717  45.8667    7.1667 2472.0    COL DU GRAND ST-BERNARD\n"
        "US1AKAB0015  61.1945 -149.7573 -999.9 AK ANCHORAGE 5.0 ESE\n"
        "short line\n"
    )
    s = ghcnd.parse_stations(text)
    assert s["SZ000006717"] == (45.8667, 7.1667, 2472.0)
    assert s["US1AKAB0015"][2] == -999.9
    assert len(s) == 2


def test_the_lapse_rate_is_the_apps_between_mid_months():
    mid_jan, mid_feb = 0.5 / 12, 1.5 / 12
    assert verify_stations.lapse_rate_at(np.array([mid_jan]))[0] == pytest.approx(0.0045)
    assert verify_stations.lapse_rate_at(np.array([(mid_jan + mid_feb) / 2]))[0] == pytest.approx(0.00475)
    assert verify_stations.lapse_rate_at(np.array([0.0]))[0] == pytest.approx((0.0044 + 0.0045) / 2)  # wraps to December


def test_a_station_gets_the_cells_around_it_and_none_at_sea():
    header = {"lat0": 10.0, "lon0": 0.0, "step": 1.0, "rows": 4, "cols": 4}
    land = np.ones((4, 4), bool)
    land[1, 2] = False
    values = np.arange(16, dtype=float).reshape(4, 4)
    cells, w = verify_stations.neighbours(header, np.array([9.5, 8.5]), np.array([0.5, 1.5]), land)
    v = verify_stations.at_points(values, cells, w)
    assert v[0] == pytest.approx((0 + 1 + 4 + 5) / 4)
    assert v[1] == pytest.approx((5 + 9 + 10) / 3)  # the sea cell (6) left out
