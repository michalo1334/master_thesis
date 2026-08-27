from __future__ import annotations

import csv
import json
import math
import shutil
import statistics
import time
from importlib.metadata import version
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from .contracts import (_configuration, _finite, _load, _manifest_requirements, _normalise_capabilities, _normalise_phase_one_evidence, _normalise_plans, _normalise_summary, _normalise_trials)
from .errors import _error
from .statistics import _bootstrap_interval, _comparison_groups, _holm, _paired_statistics, _pairs

OUTPUT_HEADERS = {
    "primary_results.csv": (
        "comparison",
        "strategy",
        "model_variant",
        "baseline",
        "baseline_model_variant",
        "budget",
        "outcome",
        "paired_mean_difference",
        "ci_lower",
        "ci_upper",
        "ci_half_width",
        "d_z",
        "p_raw",
        "p_adjusted",
    ),
    "secondary_results.csv": (
        "comparison",
        "strategy",
        "model_variant",
        "baseline",
        "baseline_model_variant",
        "budget",
        "outcome",
        "mean_difference",
        "ci_lower",
        "ci_upper",
        "ci_half_width",
    ),
    "capability_results.csv": (
        "comparison",
        "strategy",
        "model_variant",
        "baseline",
        "baseline_model_variant",
        "budget",
        "capability_id",
        "capability_name",
        "tested_probability",
        "baseline_probability",
        "probability_difference",
        "ci_lower",
        "ci_upper",
        "ci_half_width",
    ),
    "plan_variation.csv": (
        "comparison",
        "plan_id",
        "model_variant",
        "strategy",
        "budget",
        "selection_seed",
        "plan_mean",
        "comparison_relative_difference",
    ),
    "runtime.csv": ("plan_id", "kind", "runtime_ms"),
    "cdf.csv": ("model_variant", "strategy", "budget", "blast_radius", "probability"),
    "pilot_results.csv": (
        "comparison",
        "ci_half_width",
        "target",
        "passes",
        "paired_attack_seed_count",
        "approximate_trials",
    ),
    "host_probabilities.csv": (
        "model_variant", "strategy", "budget", "host_id", "host_name", "entry_host", "compromise_probability",
    ),
    "feasibility_summary.csv": (
        "experiment_id", "plan_id", "pre_attack_feasible", "unavailable_required_flow_count", "affected_capability_count",
    ),
    "runtime_summary.csv": (
        "median_plan_selection_runtime_ms", "median_simulation_runtime_ms", "evaluator_runtime_ms",
    ),
}

def _write_csv(path: Path, rows: list[dict], headers: tuple[str, ...]) -> None:
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def _runtime(value: str | int | float | None, field: str) -> float:
    result = _finite(value, field)
    if result < 0:
        raise _error(f"{field} must be non-negative")
    return result


def _clear_outputs(destination: Path) -> None:
    names = set(OUTPUT_HEADERS) | {"analysis.json", "metadata.json"}
    for name in names:
        path = destination / name
        if path.is_file():
            path.unlink()
    figures = destination / "figures"
    if figures.is_dir():
        shutil.rmtree(figures)


def _json_safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    return value


def _plot(output: Path, cdf: list[dict], variation: list[dict]) -> None:
    figure = plt.figure()
    for group in sorted({(row["model_variant"], row["strategy"], row["budget"]) for row in cdf}):
        points = [row for row in cdf if (row["model_variant"], row["strategy"], row["budget"]) == group]
        label = f"{group[0]} / {group[1]} / {group[2]}"
        plt.step([row["blast_radius"] for row in points], [row["probability"] for row in points], where="post", label=label)
    plt.xlabel("blast radius")
    plt.ylabel("empirical probability")
    if cdf:
        plt.legend()
    figure.tight_layout()
    figure.savefig(output / "figures" / "blast_radius_cdf.png")
    plt.close(figure)

    figure = plt.figure()
    labels = [row["plan_id"] for row in variation]
    means = [row["plan_mean"] for row in variation]
    plt.bar(labels, means)
    plt.xlabel("plan")
    plt.ylabel("plan mean blast radius")
    figure.autofmt_xdate()
    figure.tight_layout()
    figure.savefig(output / "figures" / "plan_variation.png")
    plt.close(figure)


def analyze(source: str | Path, output: str | Path, mode: str = "analyze") -> None:
    started = time.monotonic()
    loaded = _load(source)
    temporary = loaded.temporary
    manifest = loaded.manifest
    plans = loaded.plans
    trial_rows = loaded.trials
    capability_rows = loaded.capabilities
    flow_rows = loaded.flows
    host_rows = loaded.hosts
    summary = loaded.summary
    evaluator_runtime = loaded.evaluator_runtime
    hashes = loaded.hashes
    checksum_hash = loaded.checksum_hash
    try:
        expected_trials = _manifest_requirements(manifest)
        configuration = _configuration(manifest)
        identities = _normalise_plans(plans)
        trials, schedules = _normalise_trials(set(identities), trial_rows, expected_trials)
        capabilities, capability_names = _normalise_capabilities(set(identities), capability_rows, trials)
        flows, hosts = _normalise_phase_one_evidence(set(identities), trial_rows, flow_rows, host_rows, expected_trials)
        summary = _normalise_summary(trial_rows, summary, expected_trials)
        destination = Path(output)
        destination.mkdir(parents=True, exist_ok=True)
        _clear_outputs(destination)
        (destination / "figures").mkdir(exist_ok=True)

        primary = []
        secondary = []
        capability_results = []
        variation = []
        pilot = []
        comparisons = configuration["primary_comparisons"]
        for comparison_index, comparison in enumerate(comparisons):
            left, right = _comparison_groups(identities, comparison)
            outcome = comparison.get("outcome")
            if outcome not in ("blast_radius", "mission_impact"):
                raise _error(f"unsupported outcome: {outcome}")
            schedule, differences = _pairs(left, right, trials, schedules, outcome)
            mean, low, high, effect, p_value = _paired_statistics(
                differences, configuration, int(configuration["seed"]) + comparison_index * 2
            )
            primary.append(
                {
                    "comparison": comparison_index,
                    "strategy": comparison["strategy"],
                    "model_variant": comparison["model_variant"],
                    "baseline": comparison["baseline"],
                    "baseline_model_variant": comparison["baseline_model_variant"],
                    "budget": comparison["budget"],
                    "outcome": outcome,
                    "paired_mean_difference": mean,
                    "ci_lower": low,
                    "ci_upper": high,
                    "ci_half_width": (high - low) / 2,
                    "d_z": effect,
                    "p_raw": p_value,
                    "p_adjusted": None,
                }
            )
            other_outcome = "mission_impact" if outcome == "blast_radius" else "blast_radius"
            _, secondary_differences = _pairs(left, right, trials, schedules, other_outcome)
            secondary_low, secondary_high = _bootstrap_interval(
                secondary_differences.tolist(), configuration, int(configuration["seed"]) + 1000 + comparison_index
            )
            secondary.append(
                {
                    "comparison": comparison_index,
                    "strategy": comparison["strategy"],
                    "model_variant": comparison["model_variant"],
                    "baseline": comparison["baseline"],
                    "baseline_model_variant": comparison["baseline_model_variant"],
                    "budget": comparison["budget"],
                    "outcome": other_outcome,
                    "mean_difference": float(np.mean(secondary_differences)),
                    "ci_lower": secondary_low,
                    "ci_upper": secondary_high,
                    "ci_half_width": (secondary_high - secondary_low) / 2,
                }
            )
            target = float(configuration.get("pilot", {}).get("ci_half_width", math.inf))
            passes = (high - low) / 2 <= target
            pilot.append(
                {
                    "comparison": comparison_index,
                    "ci_half_width": (high - low) / 2,
                    "target": target,
                    "passes": passes,
                    "paired_attack_seed_count": len(schedule),
                    "approximate_trials": None if passes else math.ceil(len(schedule) * (((high - low) / 2) / target) ** 2),
                }
            )

            baseline_values = [
                value[outcome]
                for pid in right
                for (candidate, _), value in trials.items()
                if candidate == pid
            ]
            baseline_means = np.mean(baseline_values)
            for plan_id in left + right:
                identity = identities[plan_id]
                values = [
                    next(value[outcome] for (candidate, _), value in trials.items() if candidate == plan_id and value["seed"] == seed)
                    for seed in schedules[plan_id]
                ]
                variation.append(
                    {
                        "comparison": comparison_index,
                        "plan_id": plan_id,
                        "model_variant": identity[0],
                        "strategy": identity[1],
                        "budget": identity[2],
                        "selection_seed": identity[3],
                        "plan_mean": float(np.mean(values)),
                        "comparison_relative_difference": float(np.mean(values) - baseline_means),
                    }
                )

            capability_ids = sorted({key[2] for key in capabilities if key[0] in left + right})
            for capability_id in capability_ids:
                differences_by_seed = []
                tested_probabilities = []
                baseline_probabilities = []
                for seed in schedule:
                    tested_values = [capabilities.get((pid, seed, capability_id)) for pid in left]
                    baseline_values = [capabilities.get((pid, seed, capability_id)) for pid in right]
                    if any(value is None for value in tested_values + baseline_values):
                        raise _error(f"missing capability attack seed pair: {capability_id}, {seed}")
                    tested_probability = float(np.mean(tested_values))
                    baseline_probability = float(np.mean(baseline_values))
                    tested_probabilities.append(tested_probability)
                    baseline_probabilities.append(baseline_probability)
                    differences_by_seed.append(tested_probability - baseline_probability)
                capability_low, capability_high = _bootstrap_interval(
                    differences_by_seed, configuration, int(configuration["seed"]) + 2000 + comparison_index
                )
                capability_results.append(
                    {
                        "comparison": comparison_index,
                        "strategy": comparison["strategy"],
                        "model_variant": comparison["model_variant"],
                        "baseline": comparison["baseline"],
                        "baseline_model_variant": comparison["baseline_model_variant"],
                        "budget": comparison["budget"],
                        "capability_id": capability_id,
                        "capability_name": capability_names[capability_id],
                        "tested_probability": float(np.mean(tested_probabilities)),
                        "baseline_probability": float(np.mean(baseline_probabilities)),
                        "probability_difference": float(np.mean(differences_by_seed)),
                        "ci_lower": capability_low,
                        "ci_upper": capability_high,
                        "ci_half_width": (capability_high - capability_low) / 2,
                    }
                )

        p_values = [row["p_raw"] for row in primary]
        adjusted = _holm(p_values) if configuration["multiplicity_correction"] == "holm" else p_values
        for row, adjusted_value in zip(primary, adjusted):
            row["p_adjusted"] = adjusted_value

        cdf = []
        groups = sorted({identity[:3] for identity in identities.values()})
        for model_variant, strategy, budget in groups:
            plan_ids = [pid for pid, identity in identities.items() if identity[:3] == (model_variant, strategy, budget)]
            values = sorted(
                value["blast_radius"]
                for plan_id in plan_ids
                for (candidate, _), value in trials.items()
                if candidate == plan_id
            )
            cdf.extend(
                {
                    "model_variant": model_variant,
                    "strategy": strategy,
                    "budget": budget,
                    "blast_radius": value,
                    "probability": (index + 1) / len(values),
                }
                for index, value in enumerate(values)
            )

        runtimes = [
            {"plan_id": plan.get("id"), "kind": "plan_selection", "runtime_ms": _runtime(plan.get("runtime_ms"), "plan runtime_ms")}
            for plan in plans
        ] + [
            {"plan_id": row["plan_id"], "kind": "experiment", "runtime_ms": row["runtime_ms"]}
            for row in summary
        ]
        host_groups = {}
        for row in hosts:
            plan_id = row["plan_id"]
            if not plan_id:
                continue
            identity = identities[plan_id]
            key = (*identity[:3], row["host_id"])
            group = host_groups.setdefault(key, {"host_name": row["host_name"], "entry_host": row["entry_host"], "compromised": []})
            if group["host_name"] != row["host_name"] or group["entry_host"] != row["entry_host"]:
                raise _error(f"inconsistent host metadata: {row['host_id']}")
            group["compromised"].append(row["compromised"])
        host_probabilities = [
            {
                "model_variant": key[0], "strategy": key[1], "budget": key[2], "host_id": key[3],
                "host_name": group["host_name"], "entry_host": group["entry_host"],
                "compromise_probability": sum(group["compromised"]) / len(group["compromised"]),
            }
            for key, group in sorted(host_groups.items())
        ]
        flows_by_experiment = {
            (row["experiment_id"].strip(), row.get("plan_id", "").strip()): [] for row in trial_rows
        }
        for row in flows:
            flows_by_experiment.setdefault((row["experiment_id"], row["plan_id"]), []).append(row)
        feasibility = [
            {
                "experiment_id": experiment_id,
                "plan_id": plan_id,
                "pre_attack_feasible": all(row["available"] for row in experiment_flows),
                "unavailable_required_flow_count": sum(not row["available"] for row in experiment_flows),
                "affected_capability_count": len({row["capability_id"] for row in experiment_flows if not row["available"]}),
            }
            for (experiment_id, plan_id), experiment_flows in sorted(flows_by_experiment.items())
        ]
        runtime_summary = {
            "median_plan_selection_runtime_ms": statistics.median(_runtime(plan.get("runtime_ms"), "plan runtime_ms") for plan in plans),
            "median_simulation_runtime_ms": statistics.median(row["runtime_ms"] for row in summary),
            "evaluator_runtime_ms": _runtime(evaluator_runtime[0].get("runtime_ms"), "evaluator runtime_ms"),
        }
        _write_csv(destination / "primary_results.csv", primary, OUTPUT_HEADERS["primary_results.csv"])
        _write_csv(destination / "secondary_results.csv", secondary, OUTPUT_HEADERS["secondary_results.csv"])
        _write_csv(destination / "capability_results.csv", capability_results, OUTPUT_HEADERS["capability_results.csv"])
        _write_csv(destination / "plan_variation.csv", variation, OUTPUT_HEADERS["plan_variation.csv"])
        _write_csv(destination / "runtime.csv", runtimes, OUTPUT_HEADERS["runtime.csv"])
        _write_csv(destination / "host_probabilities.csv", host_probabilities, OUTPUT_HEADERS["host_probabilities.csv"])
        _write_csv(destination / "feasibility_summary.csv", feasibility, OUTPUT_HEADERS["feasibility_summary.csv"])
        _write_csv(destination / "runtime_summary.csv", [runtime_summary], OUTPUT_HEADERS["runtime_summary.csv"])
        _write_csv(destination / "cdf.csv", cdf, OUTPUT_HEADERS["cdf.csv"])
        _plot(destination, cdf, variation)

        all_pass = all(row["passes"] for row in pilot)
        if mode == "pilot":
            _write_csv(destination / "pilot_results.csv", pilot, OUTPUT_HEADERS["pilot_results.csv"])
        metadata = {
            "manifest_id": manifest.get("id"),
            "schema_version": manifest.get("schema_version"),
            "model_version": manifest.get("model_version"),
            "model_variants": manifest.get("model_variants"),
            "input_hashes": hashes,
            "checksums_hash": checksum_hash,
            "analysis_configuration": configuration,
            "input_trial_count": len(trial_rows),
            "declared_plan_trial_count": sum(len(schedule) for schedule in schedules.values()),
            "runtime_summary": runtime_summary,
            "command_mode": mode,
            "pilot_comparison_pass": pilot,
            "pilot_all_pass": all_pass,
            "simulator_only_uncertainty": True,
            "estimand_note": "Confidence intervals and tests condition on the manifest-declared selection-seed set. Plan-selection variation is reported separately.",
            "package_version": "0.1.0",
            "dependencies": {name: version(name) for name in ("numpy", "scipy", "matplotlib")},
            "analysis_runtime_seconds": time.monotonic() - started,
        }
        (destination / "metadata.json").write_text(json.dumps(_json_safe(metadata), sort_keys=True, indent=2) + "\n")
        analysis_json = {**metadata, "primary_results": primary, "secondary_results": secondary, "capability_results": capability_results, "host_probabilities": host_probabilities, "feasibility_summary": feasibility}
        (destination / "analysis.json").write_text(json.dumps(_json_safe(analysis_json), sort_keys=True, indent=2) + "\n")
    finally:
        if temporary:
            shutil.rmtree(temporary, ignore_errors=True)

__all__ = ["OUTPUT_HEADERS", "analyze"]
