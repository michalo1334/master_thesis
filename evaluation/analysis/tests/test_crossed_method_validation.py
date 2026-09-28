"""Acceptance tests for the crossed product bootstrap.

These tests run the reference crossed product bootstrap on synthetic
plan-by-attack matrices. Each case fixes its matrix size, variation source,
and seed before any result is observed. The seeds are not tuned.

The tests require success. Every case must reach the declared coverage lower
bound and must not exceed the declared null-rejection maximum. A threshold
breach is a method calibration defect. Report it. Do not weaken a threshold,
change a seed, or delete a case to make the suite pass.

Coverage above the conservative warning threshold is recorded and reported.
It is not a failure. A wider-than-needed interval costs precision, not
validity. The pilot precision target exposes that cost.
"""

import math
import unittest
import warnings
from unittest import mock

import numpy as np

from method_validation import (
    SyntheticCrossedCase,
    _corrected_product_bootstrap,
    empirical_coverage,
    empirical_null_rejection_rate,
    finite_sample_correction,
    generate_crossed_case,
    reference_centered_p_value,
    reference_product_bootstrap,
)
from network_defense_analysis.statistics import (
    CrossedComparison,
    _bootstrap_contrast,
    _finite_sample_correction,
)

EXPECTED_CONFIDENCE = 0.95
MIN_EMPIRICAL_COVERAGE = 0.91
CONSERVATIVE_COVERAGE_WARNING = 0.99
MAX_NULL_REJECTION_RATE = 0.07
NULL_ALPHA = 0.05

COVERAGE_REPETITIONS = 800
NULL_REPETITIONS = 1200
BOOTSTRAP_RESAMPLES = 400

HOLDOUT_COVERAGE_REPETITIONS = 600
HOLDOUT_NULL_REPETITIONS = 800

COVERAGE_OBSERVATIONS: list[tuple[str, float]] = []
"""Coverage observations recorded during one process run."""

NULL_REJECTION_OBSERVATIONS: list[tuple[str, float]] = []
"""Null-rejection observations recorded during one process run."""

CONSERVATIVE_COVERAGE_NOTES: list[tuple[str, float]] = []
"""Coverage observations above the conservative warning threshold."""

CASE_ALL_VARIATION = dict(
    tested_plan_count=7,
    baseline_plan_count=7,
    attack_count=40,
    contrast=-1.5,
    plan_sd=1.0,
    attack_sd=1.0,
    strategy_attack_sd=0.5,
    interaction_sd=0.5,
)
CASE_NULL_VARIATION = dict(CASE_ALL_VARIATION, contrast=0.0)
CASE_PLAN_DOMINATED = dict(
    tested_plan_count=8,
    baseline_plan_count=7,
    attack_count=30,
    contrast=-1.5,
    plan_sd=2.0,
    attack_sd=0.3,
    strategy_attack_sd=0.1,
    interaction_sd=0.1,
)
CASE_SHARED_ATTACK_DOMINATED = dict(
    tested_plan_count=7,
    baseline_plan_count=7,
    attack_count=30,
    contrast=-1.5,
    plan_sd=0.3,
    attack_sd=2.0,
    strategy_attack_sd=0.0,
    interaction_sd=0.2,
)
CASE_UNEQUAL_COUNTS = dict(
    tested_plan_count=9,
    baseline_plan_count=5,
    attack_count=32,
    contrast=-1.5,
    plan_sd=1.0,
    attack_sd=1.0,
    strategy_attack_sd=0.5,
    interaction_sd=0.5,
)
CASE_STRATEGY_ATTACK_DOMINATED = dict(
    tested_plan_count=7,
    baseline_plan_count=7,
    attack_count=30,
    contrast=-1.5,
    plan_sd=0.1,
    attack_sd=2.0,
    strategy_attack_sd=1.0,
    interaction_sd=0.1,
)
CASE_INTERACTION_DOMINATED = dict(
    tested_plan_count=7,
    baseline_plan_count=7,
    attack_count=30,
    contrast=-1.5,
    plan_sd=0.1,
    attack_sd=0.3,
    strategy_attack_sd=0.1,
    interaction_sd=1.0,
)
CASE_ZERO_VARIATION = dict(
    tested_plan_count=5,
    baseline_plan_count=5,
    attack_count=10,
    contrast=0.0,
    plan_sd=0.0,
    attack_sd=0.0,
    strategy_attack_sd=0.0,
    interaction_sd=0.0,
)
CASE_SHARED_EFFECT_CANCELLATION = dict(
    tested_plan_count=6,
    baseline_plan_count=8,
    attack_count=12,
    contrast=-1.25,
    plan_sd=0.0,
    attack_sd=3.0,
    strategy_attack_sd=0.0,
    interaction_sd=0.0,
)

# Independent holdout cases. The correction is frozen before these run.
# Do not change a value, a seed, or a repetition count after execution.
HOLDOUT_H1 = dict(
    tested_plan_count=5,
    baseline_plan_count=5,
    attack_count=10,
    contrast=-1.25,
    plan_sd=1.0,
    attack_sd=1.0,
    strategy_attack_sd=0.5,
    interaction_sd=0.5,
)
HOLDOUT_H2 = dict(
    tested_plan_count=5,
    baseline_plan_count=9,
    attack_count=20,
    contrast=-0.75,
    plan_sd=1.2,
    attack_sd=0.8,
    strategy_attack_sd=0.4,
    interaction_sd=0.6,
)
HOLDOUT_H3 = dict(
    tested_plan_count=6,
    baseline_plan_count=11,
    attack_count=24,
    contrast=-2.0,
    plan_sd=2.5,
    attack_sd=0.2,
    strategy_attack_sd=0.1,
    interaction_sd=0.15,
)
HOLDOUT_H4 = dict(
    tested_plan_count=8,
    baseline_plan_count=8,
    attack_count=18,
    contrast=-1.0,
    plan_sd=0.15,
    attack_sd=1.5,
    strategy_attack_sd=1.2,
    interaction_sd=0.15,
)
HOLDOUT_H5 = dict(
    tested_plan_count=9,
    baseline_plan_count=6,
    attack_count=36,
    contrast=-0.5,
    plan_sd=0.1,
    attack_sd=0.3,
    strategy_attack_sd=0.1,
    interaction_sd=1.2,
)
HOLDOUT_H6 = dict(
    tested_plan_count=12,
    baseline_plan_count=12,
    attack_count=48,
    contrast=-1.75,
    plan_sd=0.8,
    attack_sd=1.4,
    strategy_attack_sd=0.6,
    interaction_sd=0.7,
)

HOLDOUT_H1_SEED = 7101
HOLDOUT_H2_SEED = 7102
HOLDOUT_H3_SEED = 7103
HOLDOUT_H4_SEED = 7104
HOLDOUT_H5_SEED = 7105
HOLDOUT_H6_SEED = 7106

# Null holdouts reuse H1, H4, and H5 dimensions with zero contrast.
HOLDOUT_NULL_H1 = dict(HOLDOUT_H1, contrast=0.0)
HOLDOUT_NULL_H4 = dict(HOLDOUT_H4, contrast=0.0)
HOLDOUT_NULL_H5 = dict(HOLDOUT_H5, contrast=0.0)

HOLDOUT_NULL_H1_SEED = 7201
HOLDOUT_NULL_H4_SEED = 7202
HOLDOUT_NULL_H5_SEED = 7203

NULL_SEED = 5252


def _factory(parameters):
    """Return a case factory that forwards one seed into the parameters."""

    def build(seed):
        return generate_crossed_case(seed=seed, **parameters)

    return build


def record_coverage(name: str, coverage: float) -> None:
    """Record one coverage observation and report conservative behavior.

    Coverage above ``CONSERVATIVE_COVERAGE_WARNING`` means the interval is
    wider than necessary. Record it. Do not fail it.
    """

    COVERAGE_OBSERVATIONS.append((name, coverage))
    if coverage > CONSERVATIVE_COVERAGE_WARNING:
        CONSERVATIVE_COVERAGE_NOTES.append((name, coverage))
        warnings.warn(
            f"{name}: coverage {coverage:.4f} exceeds the conservative "
            f"warning threshold {CONSERVATIVE_COVERAGE_WARNING:.2f}",
            stacklevel=2,
        )


def record_null_rejection(name: str, rate: float) -> None:
    """Record one null-rejection observation for the calibration report."""

    NULL_REJECTION_OBSERVATIONS.append((name, rate))


class GenerationTest(unittest.TestCase):
    def test_generated_shapes_and_contrast(self):
        case = generate_crossed_case(seed=137, **CASE_ALL_VARIATION)
        self.assertEqual(case.tested.shape, (7, 40))
        self.assertEqual(case.baseline.shape, (7, 40))
        self.assertEqual(case.true_contrast, -1.5)

    def test_generation_is_deterministic(self):
        first = generate_crossed_case(seed=137, **CASE_ALL_VARIATION)
        second = generate_crossed_case(seed=137, **CASE_ALL_VARIATION)
        np.testing.assert_array_equal(first.tested, second.tested)
        np.testing.assert_array_equal(first.baseline, second.baseline)

    def test_unequal_counts_are_respected(self):
        case = generate_crossed_case(seed=211, **CASE_UNEQUAL_COUNTS)
        self.assertEqual(case.tested.shape, (9, 32))
        self.assertEqual(case.baseline.shape, (5, 32))

    def test_shared_attack_effect_is_common_to_both_sides(self):
        parameters = dict(
            tested_plan_count=6,
            baseline_plan_count=8,
            attack_count=12,
            contrast=-1.25,
            plan_sd=0.0,
            attack_sd=2.0,
            strategy_attack_sd=0.0,
            interaction_sd=0.0,
        )
        case = generate_crossed_case(seed=53, **parameters)
        np.testing.assert_allclose(case.tested[0] - case.baseline[0], -1.25)
        np.testing.assert_allclose(
            case.tested,
            np.broadcast_to(case.tested[0], case.tested.shape),
        )
        np.testing.assert_allclose(
            case.baseline,
            np.broadcast_to(case.baseline[0], case.baseline.shape),
        )

    def test_strategy_attack_effects_are_independent(self):
        parameters = dict(
            tested_plan_count=6,
            baseline_plan_count=6,
            attack_count=12,
            contrast=0.0,
            plan_sd=0.0,
            attack_sd=0.0,
            strategy_attack_sd=1.0,
            interaction_sd=0.0,
        )
        case = generate_crossed_case(seed=31, **parameters)
        # Rows are identical within a side, so one row exposes the full
        # strategy-specific attack response of that side.
        self.assertFalse(np.array_equal(case.tested[0], case.baseline[0]))

    def test_zero_variation_case_is_constant(self):
        case = generate_crossed_case(seed=11, **CASE_ZERO_VARIATION)
        self.assertTrue(np.all(case.tested == 0.0))
        self.assertTrue(np.all(case.baseline == 0.0))

    def test_invalid_sizes_rejected(self):
        with self.assertRaises(ValueError):
            generate_crossed_case(
                seed=1, **dict(CASE_ALL_VARIATION, attack_count=0)
            )
        with self.assertRaises(ValueError):
            generate_crossed_case(
                seed=1, **dict(CASE_ALL_VARIATION, plan_sd=-1.0)
            )
        with self.assertRaises(ValueError):
            generate_crossed_case(
                seed=1, **dict(CASE_ALL_VARIATION, strategy_attack_sd=-1.0)
            )


class CorrectionFormulaTest(unittest.TestCase):
    def test_correction_matches_closed_form(self):
        expected = math.sqrt((7.0 / 6.0) * (40.0 / 39.0))
        self.assertAlmostEqual(
            finite_sample_correction(7, 7, 40), expected, places=12
        )

    def test_correction_uses_larger_row_ratio(self):
        # Baseline plan count 7 gives 7/6. Tested plan count 8 gives 8/7.
        # The larger ratio is the baseline ratio.
        expected = math.sqrt((7.0 / 6.0) * (30.0 / 29.0))
        self.assertAlmostEqual(
            finite_sample_correction(8, 7, 30), expected, places=12
        )
        self.assertEqual(
            finite_sample_correction(8, 7, 30),
            finite_sample_correction(7, 8, 30),
        )

    def test_correction_stays_near_one_for_large_counts(self):
        self.assertGreater(finite_sample_correction(5, 5, 10), 1.0)
        self.assertAlmostEqual(
            finite_sample_correction(1_000_001, 1_000_001, 1_000_001),
            1.0,
            places=5,
        )

    def test_correction_rejects_degenerate_counts(self):
        for counts in ((1, 5, 10), (5, 1, 10), (5, 5, 1)):
            with self.assertRaises(ValueError):
                finite_sample_correction(*counts)


class SharedAttackScheduleTest(unittest.TestCase):
    def test_shared_attack_effects_cancel_in_the_contrast(self):
        case = generate_crossed_case(seed=17, **CASE_SHARED_EFFECT_CANCELLATION)
        observed, low, high = reference_product_bootstrap(
            case,
            resamples=200,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=99,
        )
        self.assertAlmostEqual(observed, case.true_contrast, places=12)
        self.assertAlmostEqual(low, case.true_contrast, places=9)
        self.assertAlmostEqual(high, case.true_contrast, places=9)

    def test_bootstrap_is_deterministic(self):
        case = generate_crossed_case(seed=17, **CASE_ALL_VARIATION)
        first = reference_product_bootstrap(
            case,
            resamples=200,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=99,
        )
        second = reference_product_bootstrap(
            case,
            resamples=200,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=99,
        )
        self.assertEqual(first, second)

    def test_correction_widens_the_interval(self):
        case = generate_crossed_case(seed=17, **CASE_ALL_VARIATION)
        _, low, high = reference_product_bootstrap(
            case,
            resamples=BOOTSTRAP_RESAMPLES,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=5,
        )
        with mock.patch(
            "method_validation.finite_sample_correction", return_value=1.0
        ):
            _, low_uncorrected, high_uncorrected = (
                reference_product_bootstrap(
                    case,
                    resamples=BOOTSTRAP_RESAMPLES,
                    confidence_level=EXPECTED_CONFIDENCE,
                    seed=5,
                )
            )
        self.assertGreater(high - low, high_uncorrected - low_uncorrected)

    def test_correction_widens_the_null_distribution(self):
        case = generate_crossed_case(seed=23, **CASE_ALL_VARIATION)
        p_value = reference_centered_p_value(
            case, resamples=BOOTSTRAP_RESAMPLES, seed=5
        )
        with mock.patch(
            "method_validation.finite_sample_correction", return_value=1.0
        ):
            p_uncorrected = reference_centered_p_value(
                case, resamples=BOOTSTRAP_RESAMPLES, seed=5
            )
        # The corrected null distribution is wider, so the same observed
        # contrast cannot become more extreme.
        self.assertGreaterEqual(p_value, p_uncorrected)


class ZeroVariationTest(unittest.TestCase):
    def test_zero_contrast_and_zero_width(self):
        case = generate_crossed_case(seed=11, **CASE_ZERO_VARIATION)
        observed, low, high = reference_product_bootstrap(
            case,
            resamples=100,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=3,
        )
        self.assertEqual(observed, 0.0)
        self.assertEqual(low, 0.0)
        self.assertEqual(high, 0.0)

    def test_zero_variation_p_value_is_one(self):
        case = generate_crossed_case(seed=11, **CASE_ZERO_VARIATION)
        p_value = reference_centered_p_value(case, resamples=100, seed=3)
        self.assertEqual(p_value, 1.0)


class UnsupportedCountsTest(unittest.TestCase):
    def test_bootstrap_rejects_small_tested_plan_count(self):
        case = generate_crossed_case(
            seed=1, **dict(CASE_ALL_VARIATION, tested_plan_count=4)
        )
        with self.assertRaises(ValueError):
            reference_product_bootstrap(
                case,
                resamples=50,
                confidence_level=EXPECTED_CONFIDENCE,
                seed=1,
            )

    def test_bootstrap_rejects_small_baseline_plan_count(self):
        case = generate_crossed_case(
            seed=2, **dict(CASE_ALL_VARIATION, baseline_plan_count=4)
        )
        with self.assertRaises(ValueError):
            reference_product_bootstrap(
                case,
                resamples=50,
                confidence_level=EXPECTED_CONFIDENCE,
                seed=2,
            )

    def test_bootstrap_rejects_small_attack_count(self):
        case = generate_crossed_case(
            seed=3, **dict(CASE_ALL_VARIATION, attack_count=9)
        )
        with self.assertRaises(ValueError):
            reference_product_bootstrap(
                case,
                resamples=50,
                confidence_level=EXPECTED_CONFIDENCE,
                seed=3,
            )

    def test_centered_p_value_rejects_small_attack_count(self):
        case = generate_crossed_case(
            seed=4, **dict(CASE_ALL_VARIATION, attack_count=9)
        )
        with self.assertRaises(ValueError):
            reference_centered_p_value(case, resamples=50, seed=4)

    def test_minimum_counts_are_accepted(self):
        case = generate_crossed_case(seed=5, **CASE_ZERO_VARIATION)
        observed, low, high = reference_product_bootstrap(
            case,
            resamples=50,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=5,
        )
        self.assertEqual((observed, low, high), (0.0, 0.0, 0.0))


class CoverageTest(unittest.TestCase):
    def assert_coverage(self, name, parameters, seed):
        coverage = empirical_coverage(
            repetitions=COVERAGE_REPETITIONS,
            case_factory=_factory(parameters),
            bootstrap_resamples=BOOTSTRAP_RESAMPLES,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=seed,
        )
        record_coverage(name, coverage)
        self.assertGreaterEqual(
            coverage,
            MIN_EMPIRICAL_COVERAGE,
            msg=(
                f"{name}: coverage {coverage:.4f} is below "
                f"{MIN_EMPIRICAL_COVERAGE:.4f}"
            ),
        )

    def test_all_variation_negative_contrast(self):
        self.assert_coverage("all variation", CASE_ALL_VARIATION, 4242)

    def test_plan_dominated_variation(self):
        self.assert_coverage("plan dominated", CASE_PLAN_DOMINATED, 4243)

    def test_shared_attack_dominated_variation(self):
        self.assert_coverage(
            "shared-attack dominated", CASE_SHARED_ATTACK_DOMINATED, 4244
        )

    def test_unequal_plan_counts(self):
        self.assert_coverage("unequal counts", CASE_UNEQUAL_COUNTS, 4245)

    def test_strategy_attack_dominated_variation(self):
        self.assert_coverage(
            "strategy-attack dominated",
            CASE_STRATEGY_ATTACK_DOMINATED,
            4246,
        )

    def test_cell_interaction_dominated_variation(self):
        self.assert_coverage(
            "cell-interaction dominated", CASE_INTERACTION_DOMINATED, 4247
        )

    def test_coverage_is_deterministic(self):
        first = empirical_coverage(
            repetitions=100,
            case_factory=_factory(CASE_ALL_VARIATION),
            bootstrap_resamples=100,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=77,
        )
        second = empirical_coverage(
            repetitions=100,
            case_factory=_factory(CASE_ALL_VARIATION),
            bootstrap_resamples=100,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=77,
        )
        self.assertEqual(first, second)


class NullRejectionTest(unittest.TestCase):
    def test_rejection_rate_stays_near_alpha(self):
        rate = empirical_null_rejection_rate(
            repetitions=NULL_REPETITIONS,
            case_factory=_factory(CASE_NULL_VARIATION),
            bootstrap_resamples=BOOTSTRAP_RESAMPLES,
            alpha=NULL_ALPHA,
            seed=NULL_SEED,
        )
        record_null_rejection("development null", rate)
        self.assertLessEqual(
            rate,
            MAX_NULL_REJECTION_RATE,
            msg=(
                f"null rejection rate {rate:.4f} exceeds accepted maximum "
                f"{MAX_NULL_REJECTION_RATE:.4f}"
            ),
        )


class HoldoutCoverageTest(unittest.TestCase):
    """Frozen coverage holdouts. Run once. Do not tune after a failure."""

    def assert_holdout_coverage(self, name, parameters, seed):
        coverage = empirical_coverage(
            repetitions=HOLDOUT_COVERAGE_REPETITIONS,
            case_factory=_factory(parameters),
            bootstrap_resamples=BOOTSTRAP_RESAMPLES,
            confidence_level=EXPECTED_CONFIDENCE,
            seed=seed,
        )
        record_coverage(f"holdout {name}", coverage)
        self.assertGreaterEqual(
            coverage,
            MIN_EMPIRICAL_COVERAGE,
            msg=(
                f"holdout {name}: coverage {coverage:.4f} is below "
                f"{MIN_EMPIRICAL_COVERAGE:.4f}"
            ),
        )

    def test_holdout_h1_minimum_balanced_matrix(self):
        self.assert_holdout_coverage("H1", HOLDOUT_H1, HOLDOUT_H1_SEED)

    def test_holdout_h2_unequal_plan_counts(self):
        self.assert_holdout_coverage("H2", HOLDOUT_H2, HOLDOUT_H2_SEED)

    def test_holdout_h3_plan_dominated_variation(self):
        self.assert_holdout_coverage("H3", HOLDOUT_H3, HOLDOUT_H3_SEED)

    def test_holdout_h4_strategy_attack_dominated_variation(self):
        self.assert_holdout_coverage("H4", HOLDOUT_H4, HOLDOUT_H4_SEED)

    def test_holdout_h5_interaction_dominated_variation(self):
        self.assert_holdout_coverage("H5", HOLDOUT_H5, HOLDOUT_H5_SEED)

    def test_holdout_h6_mixed_variation_larger_matrix(self):
        self.assert_holdout_coverage("H6", HOLDOUT_H6, HOLDOUT_H6_SEED)


class HoldoutNullRejectionTest(unittest.TestCase):
    """Frozen null holdouts. Run once. Do not tune after a failure."""

    def assert_holdout_rejection(self, name, parameters, seed):
        rate = empirical_null_rejection_rate(
            repetitions=HOLDOUT_NULL_REPETITIONS,
            case_factory=_factory(parameters),
            bootstrap_resamples=BOOTSTRAP_RESAMPLES,
            alpha=NULL_ALPHA,
            seed=seed,
        )
        record_null_rejection(f"holdout {name}", rate)
        self.assertLessEqual(
            rate,
            MAX_NULL_REJECTION_RATE,
            msg=(
                f"holdout {name}: null rejection rate {rate:.4f} exceeds "
                f"accepted maximum {MAX_NULL_REJECTION_RATE:.4f}"
            ),
        )

    def test_holdout_null_h1_balanced_matrix(self):
        self.assert_holdout_rejection(
            "null H1", HOLDOUT_NULL_H1, HOLDOUT_NULL_H1_SEED
        )

    def test_holdout_null_h4_strategy_attack_dominated(self):
        self.assert_holdout_rejection(
            "null H4", HOLDOUT_NULL_H4, HOLDOUT_NULL_H4_SEED
        )

    def test_holdout_null_h5_interaction_dominated(self):
        self.assert_holdout_rejection(
            "null H5", HOLDOUT_NULL_H5, HOLDOUT_NULL_H5_SEED
        )


class ProductionEquivalenceTest(unittest.TestCase):
    """Bind the method harness to the production crossed implementation.

    Every case uses one fixed matrix and one seed. The harness and production
    must draw from the generator in the same order and apply the same
    finite-sample correction.
    """

    @staticmethod
    def fixed_case(tested_rows, baseline_rows, attack_count, shift):
        columns = np.arange(attack_count, dtype=float) * 0.5
        tested = shift + np.arange(tested_rows, dtype=float)[:, None] + columns
        baseline = np.arange(baseline_rows, dtype=float)[:, None] * 0.25 + columns
        return SyntheticCrossedCase(
            tested=tested, baseline=baseline, true_contrast=shift
        )

    @staticmethod
    def comparison(case):
        return CrossedComparison(
            tested=case.tested,
            baseline=case.baseline,
            tested_plan_ids=tuple(
                f"tested-{index}" for index in range(case.tested.shape[0])
            ),
            baseline_plan_ids=tuple(
                f"baseline-{index}" for index in range(case.baseline.shape[0])
            ),
            attack_seeds=tuple(range(case.tested.shape[1])),
        )

    def test_correction_matches_production(self):
        for counts in ((7, 7, 40), (8, 7, 30), (9, 5, 32), (5, 11, 24)):
            self.assertEqual(
                finite_sample_correction(*counts),
                _finite_sample_correction(*counts),
            )

    def test_bootstrap_draws_match_production(self):
        case = self.fixed_case(6, 8, 12, -1.25)
        expected = _corrected_product_bootstrap(
            case.tested, case.baseline, 200, np.random.default_rng(99)
        )
        actual = _bootstrap_contrast(self.comparison(case), resamples=200, seed=99)
        np.testing.assert_array_equal(actual, expected)

    def test_interval_matches_reference(self):
        case = self.fixed_case(7, 7, 40, -1.5)
        observed, low, high = reference_product_bootstrap(
            case, resamples=300, confidence_level=0.9, seed=123
        )
        values = _bootstrap_contrast(self.comparison(case), resamples=300, seed=123)
        tail = (1.0 - 0.9) / 2.0
        production_low, production_high = np.percentile(
            values, [tail * 100.0, (1.0 - tail) * 100.0]
        )
        self.assertAlmostEqual(
            observed,
            float(case.tested.mean() - case.baseline.mean()),
            places=12,
        )
        self.assertAlmostEqual(low, float(production_low), places=12)
        self.assertAlmostEqual(high, float(production_high), places=12)

    def test_centered_p_value_matches_reference(self):
        case = self.fixed_case(6, 8, 12, -1.25)
        comparison = self.comparison(case)
        expected = reference_centered_p_value(case, resamples=200, seed=321)
        centered = CrossedComparison(
            tested=case.tested - case.tested.mean(),
            baseline=case.baseline - case.baseline.mean(),
            tested_plan_ids=comparison.tested_plan_ids,
            baseline_plan_ids=comparison.baseline_plan_ids,
            attack_seeds=comparison.attack_seeds,
        )
        values = _bootstrap_contrast(centered, resamples=200, seed=321)
        observed = abs(float(case.tested.mean() - case.baseline.mean()))
        exceed = int(np.count_nonzero(np.abs(values) >= observed))
        self.assertEqual(expected, (1.0 + exceed) / (200 + 1.0))


if __name__ == "__main__":
    unittest.main()
