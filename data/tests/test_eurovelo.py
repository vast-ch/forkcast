"""EuroVelo routes from OpenStreetMap: from relations to one path."""

import numpy as np

from forkcast_data import eurovelo, osm
from forkcast_data.eurovelo import Graph, _profile_indices, roots, route_ways, trace

# Relations as osm.relations() gives them: id -> (tags, [(type, id, role)]).
RELS = {
    1: ({"ref": "EV6", "type": "superroute"}, [("r", 2, ""), ("r", 3, "")]),
    2: ({"ref": "EV6", "name": "part France"}, [("w", 10, ""), ("w", 11, "forward"), ("w", 12, "alternative")]),
    3: ({"ref": "EV6", "name": "part Switzerland"}, [("w", 20, ""), ("r", 4, "variant")]),
    4: ({"ref": "EV6", "name": "Rheinfall variant"}, [("w", 30, "")]),
    5: ({"ref": "EV 6;D6", "name": "a stage under a national route"}, [("w", 40, "")]),
    6: ({"ref": "D6", "name": "national route"}, [("r", 5, "")]),
}


def test_roots_are_the_ev_relations_no_other_one_contains():
    assert roots(RELS, 6) == [1, 5]
    assert roots(RELS, 15) == []


def test_route_ways_leave_out_alternatives_and_variants():
    assert route_ways(RELS, 6) == [10, 11, 20, 40]


def test_member_ways_without_skipping_take_everything():
    assert osm.member_ways(RELS, 1) == [10, 11, 12, 20, 30]


def _line(first_id, lat, lons):
    """A way along a parallel: (node id, lon, lat) points."""
    return [(first_id + i, lon, lat) for i, lon in enumerate(lons)]


def _walk(points):
    return [(round(p[0], 4), round(p[1], 4)) for p in points]


def test_trace_bridges_a_small_hole_and_ignores_a_spur():
    main_a = _line(100, 46.0, [7.0, 7.1, 7.2])
    main_b = _line(200, 46.0, [7.2005, 7.3, 7.4])  # starts ~40 m on: touching
    spur = _line(300, 46.0, [7.3]) + _line(301, 46.1, [7.3])  # a dead end north
    spur[0] = (201, 7.3, 46.0)  # shares the main line's node
    g = Graph([main_a, main_b, spur])
    g.bridge()
    points = trace(g, [(46.0, 7.0), (46.0, 7.4)])
    assert all(kind == 0 for *_, kind in points)
    assert all(lat == 46.0 for lat, _, _ in points)  # never up the spur
    assert _walk(points)[0] == (46.0, 7.0) and _walk(points)[-1] == (46.0, 7.4)


def test_trace_marks_a_real_hole_and_prefers_the_ridden_way(monkeypatch):
    monkeypatch.setattr(eurovelo, "crosses_sea", lambda a, b: True)
    west = _line(100, 46.0, [7.0, 7.1])
    east = _line(200, 46.0, [7.3, 7.4])  # ~15 km of nothing: a ferry here
    g = Graph([west, east])
    g.bridge()
    points = trace(g, [(46.0, 7.0), (46.0, 7.4)])
    kinds = [kind for *_, kind in points]
    assert kinds.count(1) == 1
    assert points[kinds.index(1)][1] == 7.3  # the line into the far shore


def test_trace_follows_via_points_round_a_loop():
    north = _line(100, 46.1, [7.0, 7.1, 7.2])
    south = _line(200, 46.0, [7.0, 7.1, 7.2])
    west = [(100, 7.0, 46.1), (200, 7.0, 46.0)]
    east = [(102, 7.2, 46.1), (202, 7.2, 46.0)]
    g = Graph([north, south, west, east])
    points = trace(g, [(46.1, 7.0), (46.0, 7.2), (46.1, 7.0)])
    walk = _walk(points)
    assert walk[0] == walk[-1] == (46.1, 7.0)
    assert (46.0, 7.2) in walk


def test_profile_keeps_the_summit():
    km = np.array([0.0, 1, 2, 3, 4])
    ele = np.array([500.0, 600, 700, 600, 500])
    assert _profile_indices(km, ele, 5) == {0, 2, 4}
