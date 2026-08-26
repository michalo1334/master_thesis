from __future__ import annotations

import numpy as np
from scipy import stats

from .contracts import _integer
from .errors import _error


def _paired_statistics(values: np.ndarray, configuration: dict, stream_seed: int) -> tuple[float, float, float, float | None, float]:
    differences = np.asarray(values, dtype=float)
    bootstrap_rng = np.random.default_rng(stream_seed)
    bootstrap = stats.bootstrap(
        (differences,),
        np.mean,
        confidence_level=float(configuration["confidence_level"]),
        n_resamples=int(configuration["bootstrap_resamples"]),
        method="percentile",
        random_state=bootstrap_rng,
    )
    if len(differences) > 1 and np.std(differences, ddof=1) > 0:
        effect = float(np.mean(differences) / np.std(differences, ddof=1))
    else:
        effect = None
    permutation_rng = np.random.default_rng(stream_seed + 1)
    permutation = stats.permutation_test(
        (differences,),
        np.mean,
        permutation_type="samples",
        n_resamples=int(configuration["permutation_resamples"]),
        alternative="two-sided",
        random_state=permutation_rng,
    )
    p_value = max(float(permutation.pvalue), 1.0 / (int(configuration["permutation_resamples"]) + 1))
    return (
        float(np.mean(differences)),
        float(bootstrap.confidence_interval.low),
        float(bootstrap.confidence_interval.high),
        effect,
        p_value,
    )


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


def _comparison_groups(manifest: dict, identities: dict[str, tuple[str, str, int, int]], comparison: dict) -> tuple[list[str], list[str]]:
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
    if (
        tested == baseline
        and tested_variant != baseline_variant
        and _run_seeds(manifest, tested_variant, tested, budget) != _run_seeds(manifest, baseline_variant, baseline, budget)
    ):
        raise _error("same-strategy cross-model comparisons must declare identical ordered selection seeds")
    left = [pid for pid, identity in identities.items() if identity[:3] == (tested_variant, tested, budget)]
    right = [pid for pid, identity in identities.items() if identity[:3] == (baseline_variant, baseline, budget)]
    if not left or not right:
        raise _error(f"comparison has no declared plans: {comparison}")
    return left, right


def _run_seeds(manifest: dict, model_variant: str, strategy: str, budget: int) -> list | None:
    for run in manifest.get("strategy_runs", []):
        if (
            isinstance(run, dict)
            and run.get("model_variant") == model_variant
            and run.get("strategy") == strategy
            and run.get("budget") == budget
        ):
            return run.get("selection_seeds")
    return None


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

__all__ = ["_paired_statistics", "_bootstrap_interval", "_holm", "_comparison_groups", "_pairs"]
