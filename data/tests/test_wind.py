"""The wind in riding hours: local solar time, and each climate's years."""

import numpy as np

from forkcast_data import wind


def test_riding_hours_are_local():
    hours = wind.riding_hours(np.array([0.0, 120.0, -75.0]))
    assert list(hours[:, 0]) == list(wind.RIDING)  # Greenwich: UTC is local
    assert hours[0, 1] == 1  # 9:00 at 120° E is 01:00 UTC
    assert hours[0, 2] == 14  # 9:00 at 75° W is 14:00 UTC
    assert hours[-1, 1] == 8  # 16:00 at 120° E is 08:00 UTC


def test_each_climate_averages_its_own_years():
    years = wind.climate_years((2011, 2025))
    assert years["last15"] == list(range(2011, 2026))
    assert years["last5"] == list(range(2021, 2026))
    assert years["last1"] == [2025]
    assert years["elnino"] == years["last15"]  # its corrections are temperature and rain only
