import numpy as np

from forkcast_data import variants, variants_research


def test_residuals_remove_a_linear_trend():
    years = list(range(2011, 2026))
    trend = np.array(years, dtype=np.float32)[:, None] * np.array([0.1, -2.0], dtype=np.float32)
    assert np.allclose(variants.residuals(trend + 5, years), 0, atol=1e-3)


def test_residuals_keep_departures_from_the_trend():
    years = list(range(2011, 2016))
    a = np.array([[0.0], [0.0], [1.0], [0.0], [0.0]], dtype=np.float32)
    r = variants.residuals(a, years)
    assert np.isclose(r.sum(), 0, atol=1e-6)
    assert r[2, 0] == r.max()


def test_share_counts_only_noticeable_changes_on_land():
    base = np.array([100.0, 100.0, 20.0, np.nan])
    assert variants_research.share(np.array([0.6, -0.4, 0.5, np.nan]), base, "tmx") == 2 / 3
    # Rain: needs both 20 % and 10 mm.
    assert variants_research.share(np.array([25.0, 15.0, 8.0, np.nan]), base, "pre") == 1 / 3
    assert variants_research.share(np.array([1.0, -1.0, 0.9, np.nan]), base, "r1") == 2 / 3


ONI = """\
 SEAS  YR   TOTAL   ANOM
   DJF 2000  25.0   -0.6
   JFM 2000  25.0   -0.6
   FMA 2000  25.0   -0.6
   MAM 2000  25.0   -1.2
   AMJ 2000  25.0   -0.4
   MJJ 2000  25.0    0.5
   JJA 2000  25.0    0.7
   JAS 2000  25.0    1.1
   ASO 2000  25.0    0.9
   SON 2000  25.0    0.8
   OND 2000  25.0    0.2
   NDJ 2000  25.0   -0.5
"""


def test_parse_oni_centres_seasons_on_their_middle_month():
    oni = variants.parse_oni(ONI)
    assert oni[(2000, 0)] == -0.6  # DJF → January
    assert oni[(2000, 11)] == -0.5  # NDJ → December
    assert len(oni) == 12


def test_enso_months_need_five_seasons_in_a_row():
    oni = variants.parse_oni(ONI)
    # Four La Niña seasons are too few; five El Niño seasons make an event.
    assert variants.enso_months(oni, -1) == set()
    assert variants.enso_months(oni, 1) == {(2000, m) for m in range(5, 10)}
    assert variants.enso_months(oni, 1, strong=True) == {(2000, 7)}


def test_keep_weight_fades_in_between_the_75th_and_90th_percentile():
    random = np.arange(100, dtype=np.float32)[:, None] - 50  # |random| percentiles: 75th ≈ 37, 90th ≈ 45
    lo, hi = np.percentile(np.abs(random), variants.KEEP)
    d = np.array([[0.0, lo, (lo + hi) / 2, hi, -100.0]], dtype=np.float32)
    w = variants.keep_weight(d, random[:, :, None].repeat(5, axis=2))
    assert np.allclose(w, [[0, 0, 0.5, 1, 1]])


def test_enso_correction_keeps_a_real_signal_and_drops_noise():
    rng = np.random.default_rng(0)
    res = rng.normal(0, 1, (45, 20, 20)).astype(np.float32)
    sel = np.zeros(45, bool)
    sel[::4] = True  # 12 event years
    res[sel] += 3  # far beyond what 12 random years average to
    d = variants.enso_correction(res, sel, np.random.default_rng(1), {})
    assert d.mean() > 2.5
    quiet = rng.normal(0, 1, (45, 20, 20)).astype(np.float32)
    d = variants.enso_correction(quiet, sel, np.random.default_rng(1), {})
    assert np.abs(d).mean() < 0.1


def test_enso_correction_is_zero_with_too_few_years():
    res = np.ones((45, 3, 3), dtype=np.float32)
    sel = np.zeros(45, bool)
    sel[0] = True
    assert not variants.enso_correction(res, sel, np.random.default_rng(1), {}).any()


def test_apply_shifts_temperature_scales_rain_and_bounds_rainy_days():
    base = np.array([10.0, 100.0, 0.5])
    assert np.allclose(variants.apply("tmx", base, np.array([1.0, -2.0, 0.0]), base, 0), [11, 98, 0.5])
    # Rain: ref 50 → 75 is ×1.5; a halving or worse is held at ×0.5; under 1 mm stays.
    ref = np.array([50.0, 50.0, 0.5])
    pre = variants.apply("pre", base, np.array([25.0, -40.0, 5.0]), ref, 0)
    assert np.allclose(pre, [15, 50, 0.5])
    days = variants.apply("r1", np.array([1.0, 30.0]), np.array([-3.0, 3.0]), base, 1)
    assert np.allclose(days, [0, variants.MONTH_DAYS[1]])


def test_decode_inverts_encode():
    from forkcast_data import era5land

    for name, v in (("tmx", [-12.5, 0, 31.5]), ("pre", [0, 16, 400]), ("r5", [0, 2.5, 20])):
        a = np.array([*v, np.nan], dtype=np.float32)
        assert np.allclose(variants.decode(name, era5land.encode(name, a)), a, equal_nan=True)


def test_check_stops_the_build_on_a_flipped_enso_effect(monkeypatch):
    import pytest

    stats = {}
    for v, region, field, ms, sign in variants.KNOWN:
        for m in ms:
            stats[(v, region, field, m)] = sign * 1.0
    cids = ["europe"]
    for v in variants.VARIANTS:
        for f in ("tmx", "tmn"):
            for m in range(12):
                stats[(v, "europe", f, m)] = (0.1, 1.0)
    variants.check(stats, cids)  # passes
    v, region, field, ms, _ = variants.KNOWN[0]
    for m in ms:
        stats[(v, region, field, m)] *= -1
    with pytest.raises(SystemExit, match=region):
        variants.check(stats, cids)
    stats[(v, region, field, ms[0])] *= -1
    stats[("elnino", "europe", "tmx", 3)] = (0.1, 9.0)
    with pytest.raises(SystemExit, match="up to 9.0"):
        variants.check(stats, cids)


def test_check_holds_known_data_flaws_to_their_own_limit():
    import pytest

    (name, (_, cid, limit)), = variants.QUIRKS.items()
    stats = {(v, region, f, m): s * 1.0 for v, region, f, ms, s in variants.KNOWN for m in ms}
    for v in variants.VARIANTS:
        for f in ("tmx", "tmn"):
            for m in range(12):
                stats[(v, cid, f, m)] = (0.1, 1.0)
                stats[(v, name, f, m)] = variants.MAX_TEMP + 1  # beyond the usual limit, within its own
    variants.check(stats, [cid])
    stats[("last5", name, "tmn", 0)] = limit + 1
    with pytest.raises(SystemExit, match=name):
        variants.check(stats, [cid])
