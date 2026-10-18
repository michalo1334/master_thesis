import numpy as np

from evaluation_compute.statistics import (
    corrected_crossed_bootstrap,
    corrected_crossed_draws,
    finite_sample_correction,
)


def test_statistics_01_finite_sample_correction():
    assert np.isclose(finite_sample_correction(5, 8, 10), np.sqrt(1.25 * (10 / 9)))


def test_statistics_02_fixed_index_oracle_for_corrected_draws(monkeypatch):
    """STAT-02: WHEN fixed crossed samples are used, draws SHALL match oracle constants."""

    class FixedGenerator:
        def __init__(self):
            self.samples = iter(
                [
                    [0, 1, 1, 3, 5, 8, 8, 9, 2, 4],
                    [0, 1, 2, 3, 4],
                    [4, 3, 2, 1, 0],
                    [9, 9, 7, 6, 5, 4, 3, 2, 1, 0],
                    [4, 4, 3, 2, 1],
                    [0, 0, 1, 2, 3],
                ]
            )

        def integers(self, _low, _high, *, size):
            sample = np.asarray(next(self.samples), dtype=np.int64)
            assert sample.size == size
            return sample

    alternative = np.arange(50, dtype=float).reshape(5, 10)
    reference = (np.arange(50, dtype=float).reshape(5, 10) * 1.5) + 2
    monkeypatch.setattr(
        "evaluation_compute.statistics.np.random.default_rng", lambda _seed: FixedGenerator()
    )

    actual = corrected_crossed_draws(alternative, reference, replicates=2, seed=91)

    assert np.allclose(actual, [-14.014297739604482, 9.26130047445271], rtol=0, atol=1e-14)


def test_statistics_03_interval_centered_null_and_add_one_oracle(monkeypatch):
    """STAT-03: WHEN fixed draws are used, interval and test outputs SHALL match constants."""
    alternative = np.arange(50, dtype=float).reshape(5, 10)
    reference = alternative - 2.5
    calls = []

    def fixed_draws(left, right, *, replicates, seed):
        calls.append((left.copy(), right.copy(), replicates, seed))
        if len(calls) == 1:
            return np.array([-4.0, -2.0, 0.0, 2.0, 4.0])
        return np.array([-3.0, -1.0, 0.0, 1.0, 3.0])

    monkeypatch.setattr("evaluation_compute.statistics.corrected_crossed_draws", fixed_draws)

    result = corrected_crossed_bootstrap(
        alternative, reference, replicates=5, confidence_level=0.8, seed=17
    )

    assert result.estimate == 2.5
    assert np.isclose(result.lower, -3.2)
    assert np.isclose(result.upper, 3.2)
    assert result.raw_p_value == 0.5
    assert result.informative is True
    assert result.zero_width_interval is False
    assert calls[0][2:] == (5, 3302413169)
    assert calls[1][2:] == (5, 2035845825)
    assert np.array_equal(calls[0][0], alternative)
    assert np.array_equal(calls[0][1], reference)
    assert np.allclose(calls[1][0].mean(), 0.0, atol=1e-15)
    assert np.allclose(calls[1][1].mean(), 0.0, atol=1e-15)
    assert np.array_equal(calls[1][0], calls[1][1])


def test_statistics_04_deterministic_recomputation():
    alternative = np.arange(50, dtype=float).reshape(5, 10)
    reference = alternative + 1.0
    first = corrected_crossed_bootstrap(
        alternative, reference, replicates=200, confidence_level=0.95, seed=7
    )
    second = corrected_crossed_bootstrap(
        alternative, reference, replicates=200, confidence_level=0.95, seed=7
    )
    assert first == second


def test_statistics_05_non_informative_result():
    matrix = np.ones((5, 10), dtype=float)
    result = corrected_crossed_bootstrap(
        matrix, matrix, replicates=100, confidence_level=0.95, seed=7
    )
    assert result.informative is False
    assert result.raw_p_value == 1.0
    assert result.lower == result.upper == result.estimate == 0.0


def test_statistics_06_nonzero_zero_width_is_warning():
    alternative = np.zeros((5, 10), dtype=float)
    reference = np.ones((5, 10), dtype=float)
    result = corrected_crossed_bootstrap(
        alternative, reference, replicates=100, confidence_level=0.95, seed=7
    )
    assert result.informative is True
    assert result.zero_width_interval is True
    assert result.estimate == result.lower == result.upper == -1.0
