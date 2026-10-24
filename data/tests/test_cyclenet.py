"""The cycle-network build: joining OSM's short ways into a connected network."""

from forkcast_data.cyclenet import _close_gaps, _join, _simplify, _split_at_junctions


def test_join_chains_pieces_in_any_order_and_direction():
    pieces = [[[1, 0], [2, 0]], [[0, 0], [1, 0]], [[3, 0], [2, 0]]]
    assert _join(pieces) == [[[0, 0], [1, 0], [2, 0], [3, 0]]]


def test_join_stops_where_three_meet():
    fork = [[[0, 0], [1, 0]], [[1, 0], [2, 0]], [[1, 0], [1, 1]]]
    assert len(_join(fork)) == 3


def test_split_at_junctions_keeps_a_t_junction():
    # Way B ends in the middle of way A: A is split there, so simplifying
    # can't drop the junction and cut B off.
    a = [[0, 0], [1, 0], [2, 0]]
    b = [[1, 0], [1, 1]]
    lines = _join(_split_at_junctions([a, b]))
    assert sorted(lines) == sorted([[[0, 0], [1, 0]], [[1, 0], [2, 0]], [[1, 0], [1, 1]]])


def test_simplify_keeps_bends_and_ends():
    line = [[0, 0], [1, 0.0001], [2, 0], [2, 1]]
    assert _simplify(line, 0.003) == [[0, 0], [2, 0], [2, 1]]


def test_close_gaps_joins_ends_that_nearly_touch():
    a = [[0.0, 50.0], [0.1, 50.0]]
    b = [[0.1005, 50.0], [0.2, 50.0]]  # 50 m on
    c = [[0.5, 50.0], [0.6, 50.0]]  # far away
    a, b, c = _close_gaps([a, b, c])
    assert a[-1] == b[0]
    assert c[0] == [0.5, 50.0]
