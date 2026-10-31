import csv

import numpy as np
import pytest

from forkcast_data import pack, verify

PHASES = pack.PHASES


def test_a_curve_of_three_waves_matches_its_months_exactly():
    # Months made of the mean and the three waves the curve has: nothing for the fit to lose.
    m = 10 + 8 * np.cos(2 * np.pi * PHASES) - 3 * np.sin(4 * np.pi * PHASES) + np.cos(6 * np.pi * PHASES)
    flat = np.array([np.sin(np.pi * k / 12) / (np.pi * k / 12) for k in (1, 2, 3)])
    months = 10 + flat[0] * 8 * np.cos(2 * np.pi * PHASES) - flat[1] * 3 * np.sin(4 * np.pi * PHASES) + flat[2] * np.cos(6 * np.pi * PHASES)
    c = pack.fit(months, False)
    assert np.allclose(verify.monthly_means(c, False), months)
    assert np.allclose(pack.evaluate(c, PHASES), m)  # mid-month, the curve is the wave itself


def test_rain_curves_compare_as_monthly_totals():
    months = 30 + 20 * np.cos(2 * np.pi * PHASES) * (np.sin(np.pi / 12) / (np.pi / 12))
    totals = months * pack.MONTH_DAYS
    assert np.allclose(verify.monthly_means(pack.fit(totals, True), True), totals)


def test_stats_weight_cells_by_area_and_leave_out_the_sea():
    err = np.array([[[1.0, 3.0, np.nan]]])  # (month, rows, cols)
    s = verify._stats(err, np.array([[3.0, 1.0, 5.0]]))
    assert s["mae"] == pytest.approx(1.5)
    assert s["rmse"] == pytest.approx(np.sqrt(3.0))
    assert s["p95"] == 3.0


def test_per_year_errors_average_each_year_over_its_cells():
    err = np.zeros((2, 12, 1, 2))
    err[0, :, 0, 0], err[1, :, 0, 1] = 2.0, -4.0
    at = np.array([[True, True]])
    assert np.allclose(verify.per_year_mae(err, at, np.ones((1, 2))), [1.0, 2.0])
    assert np.allclose(verify.per_year_mae(err, np.array([[True, False]]), np.ones((1, 2))), [2.0, 0.0])


def test_the_interval_narrows_with_more_years_and_holds_the_mean():
    rng = np.random.default_rng(0)
    few, many = rng.normal(1.5, 0.2, 10), rng.normal(1.5, 0.2, 90)
    lo, hi = verify.interval(few)
    assert lo < few.mean() < hi
    lo2, hi2 = verify.interval(many)
    assert hi2 - lo2 < (hi - lo) * 0.7  # about 1/√9 as wide, give or take the draw
    assert verify.interval(np.full(30, 2.0)) == (2.0, 2.0)


def _history(path, runs):
    with path.open("w", newline="") as f:
        out = csv.DictWriter(f, verify.COLUMNS, lineterminator="\n")
        out.writeheader()
        for (date, code), values in runs:
            for stat, v in values.items():
                out.writerow({"date": date, "code": code, "grids": "g", "metric": "backtest", "climate": "last15", "field": "tmx", "area": "Europe", "stat": stat, "value": v, "unit": "°C"})


def test_compare_tells_a_real_change_from_noise(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(verify, "HISTORY", tmp_path / "history.csv")
    base = {"mae": 1.56, "mae lo95": 1.51, "mae hi95": 1.61}
    _history(verify.HISTORY, [(("2026-10-01", "aaa"), base), (("2026-10-02", "bbb"), base | {"mae": 1.54}), (("2026-10-03", "ccc"), base | {"mae": 1.40})])
    verify.compare()
    out = capsys.readouterr().out
    assert "2026-10-03 ccc against 2026-10-01 aaa" in out
    assert "better" in out
    verify.compare("bbb")  # against the second run, 1.54 → 1.40 is still more than the noise
    assert "better" in capsys.readouterr().out
    _history(verify.HISTORY, [(("2026-10-01", "aaa"), base), (("2026-10-02", "bbb"), base | {"mae": 1.54})])
    verify.compare()
    assert "within noise" in capsys.readouterr().out
    with pytest.raises(SystemExit, match="No run 'zzz'"):
        verify.compare("zzz")
