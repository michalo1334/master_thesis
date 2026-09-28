"""Simulation harness for the crossed plan-and-attack bootstrap.

This module is not production code. It builds synthetic plan-by-attack
matrices with a known contrast and known variation sources. It runs a
reference crossed product bootstrap on those matrices.

The tests in ``test_crossed_method_validation.py`` use this module. They
measure interval coverage and null false-positive behavior. Production
statistics must pass those checks before the study uses the method.

The generation rule is::

    baseline[row, column] = baseline_mean
        + baseline_plan_effect[row]
        + attack_effect[column]
        + baseline_strategy_attack_effect[column]
        + baseline_interaction[row, column]

    tested[row, column] = baseline_mean
        + contrast
        + tested_plan_effect[row]
        + attack_effect[column]
        + tested_strategy_attack_effect[column]
        + tested_interaction[row, column]

The two sides share ``attack_effect``. This shared term represents the shared
attack schedule. The two sides generate their plan effects, strategy-specific
attack effects, and cell interactions independently. This separates common
attack severity from strategy-by-attack response.

The reference bootstrap applies the finite-sample correction from the design.
It inflates each replicate's deviation from the observed contrast. The
correction is conservative when one variance source dominates.

The reference bootstrap requires at least five plan rows on each side and at
least ten shared attack columns. Counts below these limits did not meet the
coverage and null-rejection thresholds. The accepted cases must meet them.
A threshold breach is a calibration defect to report, not to hide.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable

import numpy as np

__all__ = [
    "SyntheticCrossedCase",
    "generate_crossed_case",
    "finite_sample_correction",
    "reference_product_bootstrap",
    "reference_centered_p_value",
    "empirical_coverage",
    "empirical_null_rejection_rate",
]

BASELINE_MEAN = 0.0
"""Fixed mean of the baseline side. It keeps generated values near zero."""

MAX_SEED = 2**32
"""Exclusive upper bound for derived integer seeds."""

MIN_PLAN_COUNT = 5
"""Minimum plan rows on each comparison side."""

MIN_ATTACK_COUNT = 10
"""Minimum shared attack columns."""


@dataclass(frozen=True)
class SyntheticCrossedCase:
    """One generated comparison with a known true contrast."""

    tested: np.ndarray
    baseline: np.ndarray
    true_contrast: float


def generate_crossed_case(
    *,
    tested_plan_count: int,
    baseline_plan_count: int,
    attack_count: int,
    contrast: float,
    plan_sd: float,
    attack_sd: float,
    strategy_attack_sd: float,
    interaction_sd: float,
    seed: int,
) -> SyntheticCrossedCase:
    """Generate tested and baseline plan-by-attack matrices."""

    if tested_plan_count < 1 or baseline_plan_count < 1 or attack_count < 1:
        raise ValueError("plan counts and attack count must be positive")
    if (
        plan_sd < 0.0
        or attack_sd < 0.0
        or strategy_attack_sd < 0.0
        or interaction_sd < 0.0
    ):
        raise ValueError("standard deviations must be non-negative")

    rng = np.random.default_rng(seed)

    attack_effect = rng.normal(0.0, attack_sd, size=attack_count)
    tested_strategy_attack_effect = rng.normal(
        0.0, strategy_attack_sd, size=attack_count
    )
    baseline_strategy_attack_effect = rng.normal(
        0.0, strategy_attack_sd, size=attack_count
    )
    tested_plan_effect = rng.normal(0.0, plan_sd, size=tested_plan_count)
    baseline_plan_effect = rng.normal(0.0, plan_sd, size=baseline_plan_count)
    tested_interaction = rng.normal(
        0.0, interaction_sd, size=(tested_plan_count, attack_count)
    )
    baseline_interaction = rng.normal(
        0.0, interaction_sd, size=(baseline_plan_count, attack_count)
    )

    baseline = (
        BASELINE_MEAN
        + baseline_plan_effect[:, None]
        + attack_effect[None, :]
        + baseline_strategy_attack_effect[None, :]
        + baseline_interaction
    )
    tested = (
        BASELINE_MEAN
        + float(contrast)
        + tested_plan_effect[:, None]
        + attack_effect[None, :]
        + tested_strategy_attack_effect[None, :]
        + tested_interaction
    )
    return SyntheticCrossedCase(
        tested=tested,
        baseline=baseline,
        true_contrast=float(contrast),
    )


def finite_sample_correction(
    tested_plan_count: int,
    baseline_plan_count: int,
    attack_count: int,
) -> float:
    """Return the finite-sample variance correction factor.

    The factor corrects the maximum row-and-column finite-sample loss. Row
    resampling loses ``count / (count - 1)`` variance when rows are sampled.
    Column resampling loses the same when columns are sampled.
    """

    if tested_plan_count < 2 or baseline_plan_count < 2 or attack_count < 2:
        raise ValueError(
            "finite-sample correction requires at least two plan rows "
            "and two attack columns"
        )
    row = max(
        tested_plan_count / (tested_plan_count - 1),
        baseline_plan_count / (baseline_plan_count - 1),
    )
    column = attack_count / (attack_count - 1)
    return math.sqrt(row * column)


def _require_supported_counts(
    tested_plan_count: int,
    baseline_plan_count: int,
    attack_count: int,
) -> None:
    """Reject matrix sizes below the calibrated minimum."""

    if tested_plan_count < MIN_PLAN_COUNT:
        raise ValueError(f"tested plan count must be at least {MIN_PLAN_COUNT}")
    if baseline_plan_count < MIN_PLAN_COUNT:
        raise ValueError(f"baseline plan count must be at least {MIN_PLAN_COUNT}")
    if attack_count < MIN_ATTACK_COUNT:
        raise ValueError(f"attack count must be at least {MIN_ATTACK_COUNT}")


def _corrected_product_bootstrap(
    tested: np.ndarray,
    baseline: np.ndarray,
    resamples: int,
    rng: np.random.Generator,
) -> np.ndarray:
    """Return the corrected crossed product bootstrap contrast distribution.

    The function calculates each raw replicate contrast. It then transforms
    the replicate to ``observed + correction * (raw - observed)``.
    """

    tested_count, attack_count = tested.shape
    baseline_count, _ = baseline.shape
    observed = float(tested.mean() - baseline.mean())
    correction = finite_sample_correction(
        tested_count,
        baseline_count,
        attack_count,
    )
    values = np.empty(resamples, dtype=float)

    for index in range(resamples):
        attacks = rng.integers(0, attack_count, size=attack_count)
        tested_rows = rng.integers(0, tested_count, size=tested_count)
        baseline_rows = rng.integers(0, baseline_count, size=baseline_count)

        tested_sample = tested[np.ix_(tested_rows, attacks)]
        baseline_sample = baseline[np.ix_(baseline_rows, attacks)]
        raw = float(tested_sample.mean() - baseline_sample.mean())
        values[index] = observed + correction * (raw - observed)

    return values


def reference_product_bootstrap(
    case: SyntheticCrossedCase,
    *,
    resamples: int,
    confidence_level: float,
    seed: int,
) -> tuple[float, float, float]:
    """Return observed contrast and percentile interval."""

    if resamples < 1:
        raise ValueError("resamples must be positive")
    if not 0.0 < confidence_level < 1.0:
        raise ValueError("confidence_level must be between zero and one")

    tested_count, attack_count = case.tested.shape
    baseline_count, _ = case.baseline.shape
    _require_supported_counts(tested_count, baseline_count, attack_count)

    observed = float(case.tested.mean() - case.baseline.mean())
    rng = np.random.default_rng(seed)
    values = _corrected_product_bootstrap(
        case.tested,
        case.baseline,
        resamples,
        rng,
    )

    tail = (1.0 - confidence_level) / 2.0
    low, high = np.percentile(values, [tail * 100.0, (1.0 - tail) * 100.0])
    return observed, float(low), float(high)


def reference_centered_p_value(
    case: SyntheticCrossedCase,
    *,
    resamples: int,
    seed: int,
) -> float:
    """Return a two-sided p-value from a centered product bootstrap."""

    if resamples < 1:
        raise ValueError("resamples must be positive")

    tested_count, attack_count = case.tested.shape
    baseline_count, _ = case.baseline.shape
    _require_supported_counts(tested_count, baseline_count, attack_count)

    observed = abs(float(case.tested.mean() - case.baseline.mean()))
    tested_null = case.tested - case.tested.mean()
    baseline_null = case.baseline - case.baseline.mean()

    rng = np.random.default_rng(seed)
    values = _corrected_product_bootstrap(
        tested_null,
        baseline_null,
        resamples,
        rng,
    )
    exceed = int(np.count_nonzero(np.abs(values) >= observed))
    return (1.0 + exceed) / (resamples + 1.0)


def _derived_seeds(seed: int, count: int) -> np.ndarray:
    """Return deterministic integer seeds for independent streams."""

    return np.random.default_rng(seed).integers(0, MAX_SEED, size=count, dtype=np.int64)


def empirical_coverage(
    *,
    repetitions: int,
    case_factory: Callable[[int], SyntheticCrossedCase],
    bootstrap_resamples: int,
    confidence_level: float,
    seed: int,
) -> float:
    """Return the fraction of intervals that contain the known contrast.

    ``case_factory`` receives one integer seed. It must return one generated
    case. The harness derives each seed from ``seed``. This keeps the run
    deterministic.
    """

    if repetitions < 1:
        raise ValueError("repetitions must be positive")

    streams = _derived_seeds(seed, repetitions * 2).reshape(repetitions, 2)
    covered = 0
    for index in range(repetitions):
        case = case_factory(int(streams[index, 0]))
        _, low, high = reference_product_bootstrap(
            case,
            resamples=bootstrap_resamples,
            confidence_level=confidence_level,
            seed=int(streams[index, 1]),
        )
        if low <= case.true_contrast <= high:
            covered += 1
    return covered / repetitions


def empirical_null_rejection_rate(
    *,
    repetitions: int,
    case_factory: Callable[[int], SyntheticCrossedCase],
    bootstrap_resamples: int,
    alpha: float,
    seed: int,
) -> float:
    """Return the fraction of null cases with p-value below alpha.

    ``case_factory`` receives one integer seed. It must return one generated
    case. Use a null contrast of zero in the generated cases.
    """

    if repetitions < 1:
        raise ValueError("repetitions must be positive")
    if not 0.0 < alpha < 1.0:
        raise ValueError("alpha must be between zero and one")

    streams = _derived_seeds(seed, repetitions * 2).reshape(repetitions, 2)
    rejections = 0
    for index in range(repetitions):
        case = case_factory(int(streams[index, 0]))
        p_value = reference_centered_p_value(
            case,
            resamples=bootstrap_resamples,
            seed=int(streams[index, 1]),
        )
        if p_value < alpha:
            rejections += 1
    return rejections / repetitions
