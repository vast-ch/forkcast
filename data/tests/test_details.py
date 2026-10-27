"""Map details: geometry helpers for the places and water files."""

from forkcast_data.details import _inside, _lines, _round


def test_lines_of_every_geometry_type():
    assert _lines({"type": "LineString", "coordinates": [[0, 0], [1, 1]]}) == [[[0, 0], [1, 1]]]
    assert len(_lines({"type": "MultiLineString", "coordinates": [[[0, 0], [1, 1]], [[2, 2], [3, 3]]]})) == 2
    ring = [[0, 0], [1, 0], [1, 1], [0, 0]]
    assert _lines({"type": "Polygon", "coordinates": [ring, [[0.2, 0.2], [0.3, 0.2], [0.2, 0.2]]]}) == [ring]
    assert _lines({"type": "Point", "coordinates": [0, 0]}) == []


def test_round_drops_points_that_become_the_same():
    assert _round([[0.001, 0.001], [0.002, 0.002], [1.0, 1.0]]) == [[0.0, 0.0], [1.0, 1.0]]


def test_inside_a_box():
    europe = (-25.0, 27.0, 45.0, 72.0)
    assert _inside(8.5, 47.4, europe)
    assert not _inside(-74.0, 40.7, europe)
