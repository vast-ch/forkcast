"""Hand-made routes and the BRouter legs."""

import json

import pytest

from forkcast_data import routes

MESSAGES = ["Longitude", "Latitude", "Elevation", "Distance", "CostPerKm", "ElevCost", "TurnCost", "NodeCost", "InitialCost", "WayTags"]


def test_a_eurovelo_leg_says_which_lines_are_ferries(tmp_path, monkeypatch):
    # Two points on a road, then a ferry to the last one.
    leg = {
        "features": [
            {
                "geometry": {"coordinates": [[7.0, 46.0, 400], [7.1, 46.0, 410], [7.2, 46.05, 0], [7.3, 46.1, 0]]},
                "properties": {
                    "messages": [
                        MESSAGES,
                        ["7100000", "46000000", "410", "7700", "1000", "0", "0", "0", "0", "highway=tertiary"],
                        ["7300000", "46100000", "0", "18000", "5000", "0", "0", "0", "0", "route=ferry"],
                    ]
                },
            }
        ]
    }
    path = tmp_path / "leg.json"
    path.write_text(json.dumps(leg))
    monkeypatch.setattr(routes, "leg_path", lambda a, b: path)
    assert [p[2] for p in routes.eurovelo_leg((46.0, 7.0), (46.1, 7.3))] == [False, False, True, True]


def test_a_busy_server_isnt_taken_for_no_route(tmp_path):
    busy = tmp_path / "busy.json"
    busy.write_text(json.dumps({"error": "operation killed by thread-priority-watchdog after 2 seconds"}))
    none = tmp_path / "none.json"
    none.write_text(json.dumps({"error": "to-position not mapped in existing datafile"}))
    with pytest.raises(ValueError):
        routes._validate_ev_leg(busy)
    routes._validate_ev_leg(none)
