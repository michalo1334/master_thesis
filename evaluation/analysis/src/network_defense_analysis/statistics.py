from __future__ import annotations

import math
import warnings
from dataclasses import dataclass

import numpy as np
from scipy import stats

from .contracts import _integer
from .errors import _error


def _bootstrap_interval(values: list[float], configuration: dict, stream_seed: int) -> tuple[float, float]:
    rng = np.random.default_rng(stream_seed)
    result = stats.bootstrap(
        (np.asarray(values, dtype=float),),
        np.mean,
        confidence_level=float(configuration["confidence_level"]),
        n_resamples=int(configuration["bootstrap_resamples"]),
        method="percentile",
        random_state=rng,
    )
    return float(result.confidence_interval.low), float(result.confidence_interval.high)


def _holm(values: list[float]) -> list[float]:
    order = sorted(range(len(values)), key=values.__getitem__)
    adjusted = [0.0] * len(values)
    previous = 0.0
    for rank, index in enumerate(order):
        previous = max(previous, (len(values) - rank) * values[index])
        adjusted[index] = min(1.0, previous)
    return adjusted


def _comparison_groups(identities: dict[str, tuple[str, str, int, int]], comparison: dict) -> tuple[list[str], list[str]]:
    if not isinstance(comparison, dict) or not {"strategy", "baseline", "budget", "model_variant", "baseline_model_variant"} <= set(comparison):
        raise _error("malformed primary comparison")
    tested = comparison["strategy"]
    baseline = comparison["baseline"]
    tested_variant = comparison["model_variant"]
    baseline_variant = comparison["baseline_model_variant"]
    budget = _integer(comparison["budget"], "comparison budget")
    for field, value in (("model_variant", tested_variant), ("baseline_model_variant", baseline_variant)):
        if not isinstance(value, str) or not value:
            raise _error(f"comparison {field} must be a non-empty string")
    left = [pid for pid, identity in identities.items() if identity[:3] == (tested_variant, tested, budget)]
    right = [pid for pid, identity in identities.items() if identity[:3] == (baseline_variant, baseline, budget)]
    if not left or not right:
        raise _error(f"comparison has no declared plans: {comparison}")
    return left, right


def _pairs(left: list[str], right: list[str], trials: dict[tuple[str, int], dict], schedules: dict[str, list[int]], outcome: str) -> tuple[list[int], np.ndarray]:
    schedule = schedules[left[0]]
    for plan_id in left[1:] + right:
        if schedules.get(plan_id) != schedule:
            raise _error(f"inconsistent ordered attack-seed schedule for plan {plan_id}")
    by_seed = {
        (plan_id, value["seed"]): value
        for (plan_id, _), value in trials.items()
    }
    differences = []
    for seed in schedule:
        tested = [by_seed[(pid, seed)][outcome] for pid in left if (pid, seed) in by_seed]
        baseline = [by_seed[(pid, seed)][outcome] for pid in right if (pid, seed) in by_seed]
        if len(tested) != len(left) or len(baseline) != len(right):
            raise _error(f"missing attack seed pair: {seed}")
        differences.append(float(np.mean(tested) - np.mean(baseline)))
    return schedule, np.asarray(differences)


MIN_PLAN_COUNT = 5
"""Minimum plan rows on each comparison side for the crossed study path."""

MIN_ATTACK_COUNT = 10
"""Minimum shared attack columns for the crossed study path."""


@dataclass(frozen=True)
class CrossedComparison:
    """Tested and baseline plan-by-attack matrices for one comparison."""

    tested: np.ndarray
    baseline: np.ndarray
    tested_plan_ids: tuple[str, ...]
    baseline_plan_ids: tuple[str, ...]
    attack_seeds: tuple[int, ...]

    def __post_init__(self) -> None:
        if self.tested.ndim != 2 or self.baseline.ndim != 2:
            raise _error("crossed outcomes must be matrices")
        if self.tested.shape[1] != self.baseline.shape[1]:
            raise _error("comparison sides must share attack columns")


def _crossed_comparison(
    left: list[str],
    right: list[str],
    identities: dict[str, tuple[str, str, int, int]],
    trials: dict[tuple[str, int], dict],
    schedules: dict[str, list[int]],
    outcome: str,
) -> CrossedComparison:
    """Build tested and baseline plan-by-attack matrices for one comparison.

    Each side is sorted by the normalized plan identity, which includes the
    selection seed. The ordering only keeps finite resampling deterministic.
    It does not pair plan rows across the two strategies.
    """

    if not left or not right:
        raise _error("crossed comparison requires plans on both sides")
    for plan_id in left + right:
        if plan_id not in identities:
            raise _error(f"missing plan identity: {plan_id}")

    schedule = schedules.get(left[0])
    if not schedule:
        raise _error(f"plan {left[0]} has no declared attack-seed schedule")
    for plan_id in left[1:] + right:
        if schedules.get(plan_id) != schedule:
            raise _error(f"inconsistent ordered attack-seed schedule for plan {plan_id}")

    by_seed = {
        (plan_id, value["seed"]): value
        for (plan_id, _), value in trials.items()
    }

    def cell(plan_id: str, seed: int) -> float:
        value = by_seed.get((plan_id, seed))
        if value is None or outcome not in value:
            raise _error(f"missing crossed outcome for plan {plan_id}, attack seed {seed}")
        return float(value[outcome])

    def matrix(plan_ids: list[str]) -> np.ndarray:
        return np.asarray(
            [[cell(plan_id, seed) for seed in schedule] for plan_id in plan_ids],
            dtype=float,
        )

    tested_ids = sorted(left, key=identities.__getitem__)
    baseline_ids = sorted(right, key=identities.__getitem__)
    return CrossedComparison(
        tested=matrix(tested_ids),
        baseline=matrix(baseline_ids),
        tested_plan_ids=tuple(tested_ids),
        baseline_plan_ids=tuple(baseline_ids),
        attack_seeds=tuple(schedule),
    )


def _finite_sample_correction(
    tested_plan_count: int,
    baseline_plan_count: int,
    attack_count: int,
) -> float:
    """Return the conservative row-and-column variance correction."""

    if tested_plan_count < 2 or baseline_plan_count < 2 or attack_count < 2:
        raise _error("finite-sample correction requires at least two plan rows and two attack columns")
    row = max(
        tested_plan_count / (tested_plan_count - 1),
        baseline_plan_count / (baseline_plan_count - 1),
    )
    column = attack_count / (attack_count - 1)
    return math.sqrt(row * column)


def _bootstrap_contrast(
    comparison: CrossedComparison,
    *,
    resamples: int,
    seed: int,
) -> np.ndarray:
    """Return corrected tested-minus-baseline bootstrap contrasts."""

    if resamples < 1:
        raise _error("bootstrap resamples must be positive")
    tested_count, attack_count = comparison.tested.shape
    baseline_count, _ = comparison.baseline.shape
    if tested_count < MIN_PLAN_COUNT:
        raise _error(f"crossed bootstrap requires at least {MIN_PLAN_COUNT} tested plan rows")
    if baseline_count < MIN_PLAN_COUNT:
        raise _error(f"crossed bootstrap requires at least {MIN_PLAN_COUNT} baseline plan rows")
    if attack_count < MIN_ATTACK_COUNT:
        raise _error(f"crossed bootstrap requires at least {MIN_ATTACK_COUNT} shared attack columns")

    observed = float(comparison.tested.mean() - comparison.baseline.mean())
    correction = _finite_sample_correction(tested_count, baseline_count, attack_count)
    rng = np.random.default_rng(seed)
    values = np.empty(resamples, dtype=float)

    for index in range(resamples):
        attack_columns = rng.integers(0, attack_count, size=attack_count)
        tested_rows = rng.integers(0, tested_count, size=tested_count)
        baseline_rows = rng.integers(0, baseline_count, size=baseline_count)

        tested_sample = comparison.tested[np.ix_(tested_rows, attack_columns)]
        baseline_sample = comparison.baseline[np.ix_(baseline_rows, attack_columns)]
        raw = float(tested_sample.mean() - baseline_sample.mean())
        values[index] = observed + correction * (raw - observed)

    return values


_ZERO_WIDTH_WARNING = "informative primary contrast has a zero-width confidence interval"
"""Stable warning text for a zero-width interval around a non-zero contrast."""


class DegenerateContrastWarning(UserWarning):
    """Signals an informative contrast with a zero-width interval."""


@dataclass(frozen=True)
class PrimaryStatistics:
    """Primary crossed statistics for one comparison."""

    mean_difference: float
    ci_lower: float
    ci_upper: float
    ci_half_width: float
    p_raw: float
    informative: bool
    tested_plan_count: int
    baseline_plan_count: int
    attacks_per_plan: int


COMPARISON_STREAM_STRIDE = 2
"""Per-comparison stream-seed stride for deterministic resampling."""


def _comparison_stream_seed(base_seed: int, tier_offset: int, comparison_index: int) -> int:
    """Return one deterministic resampling root per tier and comparison.

    Single-archive analysis passes a zero ``tier_offset``. Study analysis and
    the study pilot pass a per-tier offset. The helper keeps every existing
    numeric seed exactly.
    """

    return (
        int(base_seed)
        + int(tier_offset)
        + int(comparison_index) * COMPARISON_STREAM_STRIDE
    )


def _child_seeds(stream_seed: int) -> tuple[int, int]:
    """Derive one interval seed and one null-distribution seed."""

    children = np.random.SeedSequence(stream_seed).spawn(2)
    interval_seed = int(children[0].generate_state(1)[0])
    null_seed = int(children[1].generate_state(1)[0])
    return interval_seed, null_seed


def _crossed_statistics(
    comparison: CrossedComparison,
    configuration: dict,
    stream_seed: int,
) -> PrimaryStatistics:
    """Return the primary contrast, interval, p-value, and informativeness.

    The interval uses the corrected uncentered bootstrap. The p-value uses a
    separate corrected centered bootstrap. Each distribution draws from its
    own deterministic child seed.
    """

    resamples = int(configuration["bootstrap_resamples"])
    confidence_level = float(configuration["confidence_level"])
    interval_seed, null_seed = _child_seeds(stream_seed)

    observed = float(comparison.tested.mean() - comparison.baseline.mean())
    interval_values = _bootstrap_contrast(comparison, resamples=resamples, seed=interval_seed)
    tail = (1.0 - confidence_level) / 2.0
    ci_lower, ci_upper = np.percentile(
        interval_values, [tail * 100.0, (1.0 - tail) * 100.0]
    )
    ci_lower = float(ci_lower)
    ci_upper = float(ci_upper)

    centered = CrossedComparison(
        tested=comparison.tested - comparison.tested.mean(),
        baseline=comparison.baseline - comparison.baseline.mean(),
        tested_plan_ids=comparison.tested_plan_ids,
        baseline_plan_ids=comparison.baseline_plan_ids,
        attack_seeds=comparison.attack_seeds,
    )
    null_values = _bootstrap_contrast(centered, resamples=resamples, seed=null_seed)
    extreme = int(np.count_nonzero(np.abs(null_values) >= abs(observed)))
    p_raw = float((1 + extreme) / (len(null_values) + 1))

    informative = not (
        np.isclose(observed, 0.0)
        and np.isclose(ci_lower, 0.0)
        and np.isclose(ci_upper, 0.0)
    )
    if not informative:
        p_raw = 1.0
    elif np.isclose(ci_lower, ci_upper):
        warnings.warn(_ZERO_WIDTH_WARNING, DegenerateContrastWarning, stacklevel=2)

    tested_count, attack_count = comparison.tested.shape
    baseline_count, _ = comparison.baseline.shape
    return PrimaryStatistics(
        mean_difference=observed,
        ci_lower=ci_lower,
        ci_upper=ci_upper,
        ci_half_width=(ci_upper - ci_lower) / 2.0,
        p_raw=p_raw,
        informative=bool(informative),
        tested_plan_count=int(tested_count),
        baseline_plan_count=int(baseline_count),
        attacks_per_plan=int(attack_count),
    )


__all__ = [
    "_bootstrap_interval",
    "_holm",
    "_comparison_groups",
    "_pairs",
    "CrossedComparison",
    "_crossed_comparison",
    "_finite_sample_correction",
    "_bootstrap_contrast",
    "PrimaryStatistics",
    "DegenerateContrastWarning",
    "_comparison_stream_seed",
    "COMPARISON_STREAM_STRIDE",
    "_child_seeds",
    "_crossed_statistics",
]
