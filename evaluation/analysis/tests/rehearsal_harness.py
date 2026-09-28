"""Deterministic synthetic fixtures for the crossed study rehearsal.

This module builds test-only tier archives and runs the real
``/v1/study/pilot`` and ``/v1/study/analyze`` routes on study ZIP bytes that
the Elixir ``StudyBundle.archive/2`` produced. It adds no statistics. Every
value here is invented. None is a production study value.

Two subcommands drive the rehearsal:

``fixtures``
    Write three pilot tier archives, three final tier archives, one study
    specification, and one seed record.

``run``
    Load an Elixir-built pilot and final study bundle, verify the declared and
    observed seed schedules are disjoint, POST each bundle to its study route
    through the Starlette test client, and write both result ZIPs.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import shutil
import tempfile
import zipfile
from pathlib import Path

STRATEGIES = ("alt-ridge", "alt-segment", "alt-simulated", "alt-annealed")
"""Invented alternative strategy labels."""

BASELINE = "baseline-cvss"
"""Invented CVSS-style baseline label."""

BUDGETS = (1, 2, 3)
TIER_LABELS = ("tier-amber", "tier-basalt", "tier-cobalt")
MODEL_VARIANT = "full"
"""Model variant wire value. The Phoenix primary-row contract requires it."""

PILOT_PLAN_COUNT = 8
PILOT_ATTACK_COUNT = 16
PILOT_SELECTION_SEEDS = tuple(range(4100, 4100 + PILOT_PLAN_COUNT))
PILOT_ATTACK_SEEDS = tuple(range(5100, 5100 + PILOT_ATTACK_COUNT))
PILOT_EVALUATION_SEED = 6100
PILOT_ANALYSIS_SEED = 6300

FINAL_PLAN_COUNT = 5
FINAL_ATTACK_COUNT = 10
FINAL_SELECTION_SEEDS = tuple(range(4200, 4200 + FINAL_PLAN_COUNT))
FINAL_ATTACK_SEEDS = tuple(range(5300, 5300 + FINAL_ATTACK_COUNT))
FINAL_EVALUATION_SEED = 6200
FINAL_ANALYSIS_SEED = 6400

CI_HALF_WIDTH = 100.0
"""Deliberately loose rehearsal target so the pilot yields a recommendation.
The tight-target and insufficient paths are covered by ``test_pilot``."""

GUARD_QUANTILE = 0.5
PILOT_SUBSAMPLES = 2
PILOT_RESAMPLING_SEED = 6500
SELECTION_RULE = "lowest_predicted_runtime"
CONFIDENCE_LEVEL = 0.9
BOOTSTRAP_RESAMPLES = 25
PERMUTATION_RESAMPLES = 25

BASE_IMPACT = 6.0
STRATEGY_OFFSETS = {
    "alt-ridge": 1.5,
    "alt-segment": -1.0,
    "alt-simulated": 2.5,
    "alt-annealed": -2.0,
    BASELINE: 0.0,
}

NON_INFORMATIVE_TIER_INDEX = 0
NON_INFORMATIVE_BUDGET = 2
NON_INFORMATIVE_STRATEGY = STRATEGIES[0]
"""The final fixture zeroes both sides of one comparison so that the family
keeps one non-informative row. The pilot fixture keeps every row informative."""

TRIAL_HEADERS = (
    "experiment_id",
    "plan_id",
    "trial_index",
    "seed",
    "blast_radius",
    "mission_impact",
)
CAPABILITY_HEADERS = (
    "experiment_id",
    "plan_id",
    "trial_index",
    "seed",
    "capability_id",
    "capability_name",
    "disrupted",
    "impact_weight",
)
FLOW_HEADERS = (
    "experiment_id",
    "plan_id",
    "capability_id",
    "capability_name",
    "source_segment_id",
    "target_service_id",
    "available",
)
HOST_HEADERS = (
    "experiment_id",
    "plan_id",
    "trial_index",
    "seed",
    "host_id",
    "host_name",
    "entry_host",
    "compromised",
)
SUMMARY_HEADERS = (
    "experiment_id",
    "plan_id",
    "trial_count",
    "expected_blast_radius",
    "median_blast_radius",
    "blast_radius_p95",
    "blast_radius_p99",
    "min_blast_radius",
    "max_blast_radius",
    "runtime_ms",
)
EVALUATOR_RUNTIME_HEADERS = ("runtime_ms",)

PAYLOAD_FILES = (
    "manifest.resolved.json",
    "graph.json",
    "plans.jsonl",
    "trials.csv",
    "capability_outcomes.csv",
    "pre_attack_flow_statuses.csv",
    "host_compromises.csv",
    "summary.csv",
    "evaluator_runtime.csv",
)


def study_spec() -> dict:
    """Return the deterministic study specification used by both bundles."""

    return {
        "study_id": "crossed-rehearsal-study",
        "specification_version": 1,
        "expected_family": {
            "strategies": list(STRATEGIES),
            "baseline": BASELINE,
            "budgets": list(BUDGETS),
            "outcome": "mission_impact",
        },
        "pilot": {
            "ci_half_width": CI_HALF_WIDTH,
            "plan_count_candidates": [5, 6],
            "attacks_per_plan_candidates": [10, 12],
            "guard_quantile": GUARD_QUANTILE,
            "subsamples": PILOT_SUBSAMPLES,
            "seed": PILOT_RESAMPLING_SEED,
            "selection_rule": SELECTION_RULE,
        },
        "multiplicity_correction": "holm",
        "pilot_seed_schedule": {
            "selection": list(PILOT_SELECTION_SEEDS),
            "evaluation": [PILOT_EVALUATION_SEED],
        },
        "final_seed_schedule": {
            "selection": list(FINAL_SELECTION_SEEDS),
            "evaluation": [FINAL_EVALUATION_SEED],
        },
    }


def write_fixtures(output: str | Path) -> dict:
    """Write pilot and final tier archives plus the study specification."""

    output = Path(output)
    (output / "pilot" / "tiers").mkdir(parents=True, exist_ok=True)
    (output / "final" / "tiers").mkdir(parents=True, exist_ok=True)

    spec = study_spec()
    (output / "study.json").write_text(json.dumps(spec, indent=2, sort_keys=True) + "\n")

    pilot_tiers: dict[str, str] = {}
    final_tiers: dict[str, str] = {}
    for tier_index, label in enumerate(TIER_LABELS):
        pilot_path = output / "pilot" / "tiers" / f"{label}.zip"
        _build_tier_zip(
            pilot_path,
            label=label,
            tier_index=tier_index,
            plan_count=PILOT_PLAN_COUNT,
            attack_count=PILOT_ATTACK_COUNT,
            selection_seeds=PILOT_SELECTION_SEEDS,
            attack_seeds=PILOT_ATTACK_SEEDS,
            analysis_seed=PILOT_ANALYSIS_SEED,
            evaluation_seed=PILOT_EVALUATION_SEED,
            zero_control=False,
        )
        final_path = output / "final" / "tiers" / f"{label}.zip"
        _build_tier_zip(
            final_path,
            label=label,
            tier_index=tier_index,
            plan_count=FINAL_PLAN_COUNT,
            attack_count=FINAL_ATTACK_COUNT,
            selection_seeds=FINAL_SELECTION_SEEDS,
            attack_seeds=FINAL_ATTACK_SEEDS,
            analysis_seed=FINAL_ANALYSIS_SEED,
            evaluation_seed=FINAL_EVALUATION_SEED,
            zero_control=True,
        )
        pilot_tiers[label] = str(pilot_path)
        final_tiers[label] = str(final_path)

    seeds = {
        "pilot": {
            "selection": list(PILOT_SELECTION_SEEDS),
            "attack": list(PILOT_ATTACK_SEEDS),
            "evaluation": [PILOT_EVALUATION_SEED],
            "analysis_seed": PILOT_ANALYSIS_SEED,
        },
        "final": {
            "selection": list(FINAL_SELECTION_SEEDS),
            "attack": list(FINAL_ATTACK_SEEDS),
            "evaluation": [FINAL_EVALUATION_SEED],
            "analysis_seed": FINAL_ANALYSIS_SEED,
        },
    }
    (output / "seeds.json").write_text(json.dumps(seeds, indent=2, sort_keys=True) + "\n")

    manifest = {
        "study_spec": str(output / "study.json"),
        "seeds_path": str(output / "seeds.json"),
        "labels": list(TIER_LABELS),
        "pilot_tiers": pilot_tiers,
        "final_tiers": final_tiers,
        "seeds": seeds,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def run_routes(pilot_bundle: str | Path, final_bundle: str | Path, output: str | Path) -> dict:
    """Verify disjoint seeds, then run both study routes on the exact bytes."""

    from starlette.testclient import TestClient

    from network_defense_analysis import service

    pilot_bundle = Path(pilot_bundle)
    final_bundle = Path(final_bundle)
    verify_disjoint_seeds(pilot_bundle, final_bundle)

    destination = Path(output)
    destination.mkdir(parents=True, exist_ok=True)
    results: dict[str, dict] = {}
    for name, path, endpoint, filename in (
        ("pilot", pilot_bundle, "/v1/study/pilot", "pilot-output.zip"),
        ("analyze", final_bundle, "/v1/study/analyze", "final-output.zip"),
    ):
        payload = Path(path).read_bytes()
        # One app per request keeps the single-slot concurrency guard free.
        client = TestClient(service.create_app())
        response = client.post(
            endpoint,
            content=payload,
            headers={"content-type": "application/zip"},
        )
        if response.status_code != 200:
            raise RuntimeError(
                f"{endpoint} returned {response.status_code}: {response.text[:512]}"
            )
        if response.headers.get("content-type", "").split(";", 1)[0] != "application/zip":
            raise RuntimeError(f"{endpoint} returned an unexpected content type")
        body = response.content
        (destination / filename).write_bytes(body)
        results[name] = {
            "endpoint": endpoint,
            "status": response.status_code,
            "filename": filename,
            "byte_size": len(body),
            "sha256": hashlib.sha256(body).hexdigest(),
        }
    return results


def verify_disjoint_seeds(pilot_bundle: Path, final_bundle: Path) -> None:
    """Reject any overlap between pilot and final seeds, before analysis."""

    for bundle in (pilot_bundle, final_bundle):
        spec = _read_outer_json(bundle, "study.json")
        for key in ("selection", "evaluation"):
            declared_pilot = set(spec["pilot_seed_schedule"][key])
            declared_final = set(spec["final_seed_schedule"][key])
            if declared_pilot & declared_final:
                raise RuntimeError(f"declared {key} seed schedules overlap")
            if not declared_pilot or not declared_final:
                raise RuntimeError(f"declared {key} seed schedule is empty")

    pilot_actual = _tier_seed_sets(pilot_bundle)
    final_actual = _tier_seed_sets(final_bundle)
    for key in ("selection", "attack", "evaluation"):
        if not pilot_actual[key] or not final_actual[key]:
            raise RuntimeError(f"missing observed {key} seeds")
        if pilot_actual[key] & final_actual[key]:
            raise RuntimeError(f"pilot and final {key} seeds overlap")


def _tier_seed_sets(bundle: Path) -> dict[str, set]:
    selection: set[int] = set()
    attack: set[int] = set()
    evaluation: set[int] = set()
    with zipfile.ZipFile(bundle) as outer:
        for name in outer.namelist():
            if not name.startswith("tiers/") or not name.endswith(".zip"):
                continue
            with zipfile.ZipFile(io.BytesIO(outer.read(name))) as inner:
                manifest = json.loads(inner.read("manifest.resolved.json"))
                trials = inner.read("trials.csv").decode()
            for run in manifest.get("strategy_runs", []):
                selection.update(run.get("selection_seeds", []))
            evaluation.add(manifest.get("evaluation", {}).get("seed"))
            for row in csv.DictReader(io.StringIO(trials)):
                if row.get("seed"):
                    attack.add(int(row["seed"]))
    return {"selection": selection, "attack": attack, "evaluation": evaluation}


def _read_outer_json(bundle: Path, name: str):
    with zipfile.ZipFile(bundle) as archive:
        return json.loads(archive.read(name))


def _mission_impact(
    tier_index: int,
    strategy: str,
    budget: int,
    plan_index: int,
    attack_index: int,
    zero_control: bool,
) -> float:
    if (
        zero_control
        and tier_index == NON_INFORMATIVE_TIER_INDEX
        and budget == NON_INFORMATIVE_BUDGET
        and strategy in (NON_INFORMATIVE_STRATEGY, BASELINE)
    ):
        return 0.0
    return (
        BASE_IMPACT
        + STRATEGY_OFFSETS[strategy]
        + 0.4 * plan_index
        + 0.2 * attack_index
        + 0.1 * tier_index
    )


def _build_tier_zip(
    target: Path,
    *,
    label: str,
    tier_index: int,
    plan_count: int,
    attack_count: int,
    selection_seeds,
    attack_seeds,
    analysis_seed: int,
    evaluation_seed: int,
    zero_control: bool,
) -> None:
    directory = Path(tempfile.mkdtemp())
    try:
        strategies = list(STRATEGIES) + [BASELINE]
        plan_records = [
            (f"{label}-{strategy}-{budget}-{plan_index}", strategy, budget, plan_index)
            for strategy in strategies
            for budget in BUDGETS
            for plan_index in range(plan_count)
        ]
        runs = [
            {
                "model_variant": MODEL_VARIANT,
                "strategy": strategy,
                "budget": budget,
                "selection_seeds": list(selection_seeds),
            }
            for strategy in strategies
            for budget in BUDGETS
        ]
        comparisons = [
            {
                "strategy": strategy,
                "model_variant": MODEL_VARIANT,
                "baseline": BASELINE,
                "baseline_model_variant": MODEL_VARIANT,
                "budget": budget,
                "outcome": "mission_impact",
            }
            for strategy in STRATEGIES
            for budget in BUDGETS
        ]
        manifest = {
            "schema_version": 3,
            "model_version": "rehearsal-model",
            "id": f"{label}-manifest",
            "model_variants": [
                {
                    "id": MODEL_VARIANT,
                    "objective": "mission_then_blast_radius",
                    "require_pre_attack_feasibility": True,
                }
            ],
            "evaluation": {"trials": attack_count, "seed": evaluation_seed},
            "strategy_runs": runs,
            "analysis": {
                "primary_comparisons": comparisons,
                "confidence_level": CONFIDENCE_LEVEL,
                "bootstrap_resamples": BOOTSTRAP_RESAMPLES,
                "permutation_resamples": PERMUTATION_RESAMPLES,
                "multiplicity_correction": "holm",
                "seed": analysis_seed,
            },
        }
        (directory / "manifest.resolved.json").write_text(json.dumps(manifest, sort_keys=True) + "\n")
        (directory / "graph.json").write_text("{}\n")
        plans = [
            {
                "id": plan_id,
                "model_variant": MODEL_VARIANT,
                "strategy": strategy,
                "requested_budget": budget,
                "selection_seed": selection_seeds[plan_index],
                "objective": "mission_then_blast_radius",
                "require_pre_attack_feasibility": True,
                "status": "completed",
                "runtime_ms": 3,
            }
            for plan_id, strategy, budget, plan_index in plan_records
        ]
        (directory / "plans.jsonl").write_text("\n".join(json.dumps(plan) for plan in plans) + "\n")

        trials = []
        summaries = []
        for plan_id, strategy, budget, plan_index in plan_records:
            for attack_index, attack_seed in enumerate(attack_seeds):
                value = _mission_impact(
                    tier_index, strategy, budget, plan_index, attack_index, zero_control
                )
                trials.append(
                    {
                        "experiment_id": f"experiment-{plan_id}",
                        "plan_id": plan_id,
                        "trial_index": attack_index + 1,
                        "seed": attack_seed,
                        "blast_radius": value,
                        "mission_impact": value,
                    }
                )
            summaries.append(
                {
                    "experiment_id": f"experiment-{plan_id}",
                    "plan_id": plan_id,
                    "trial_count": attack_count,
                    "expected_blast_radius": 0.0,
                    "median_blast_radius": 0.0,
                    "blast_radius_p95": 0.0,
                    "blast_radius_p99": 0.0,
                    "min_blast_radius": 0.0,
                    "max_blast_radius": 0.0,
                    "runtime_ms": attack_count * 2,
                }
            )
        _write_csv(directory / "trials.csv", TRIAL_HEADERS, trials)
        for name, headers in (
            ("capability_outcomes.csv", CAPABILITY_HEADERS),
            ("pre_attack_flow_statuses.csv", FLOW_HEADERS),
            ("host_compromises.csv", HOST_HEADERS),
        ):
            (directory / name).write_text(",".join(headers) + "\n")
        _write_csv(directory / "summary.csv", SUMMARY_HEADERS, summaries)
        _write_csv(directory / "evaluator_runtime.csv", EVALUATOR_RUNTIME_HEADERS, [{"runtime_ms": 12}])
        _write_checksums(directory)

        target.parent.mkdir(parents=True, exist_ok=True)
        _write_zip(directory, target)
    finally:
        shutil.rmtree(directory, ignore_errors=True)


def _write_csv(path: Path, headers, rows: list[dict]) -> None:
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(headers))
        writer.writeheader()
        writer.writerows(rows)


def _write_checksums(directory: Path) -> None:
    lines = [
        f"{name}  {hashlib.sha256((directory / name).read_bytes()).hexdigest()}"
        for name in PAYLOAD_FILES
    ]
    (directory / "checksums.txt").write_text("\n".join(lines) + "\n")


def _write_zip(directory: Path, target: Path) -> None:
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        paths = sorted(
            (path for path in directory.rglob("*") if path.is_file()),
            key=lambda path: path.relative_to(directory).as_posix(),
        )
        for path in paths:
            info = zipfile.ZipInfo(path.relative_to(directory).as_posix(), (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o600 << 16
            archive.writestr(info, path.read_bytes())


def _emit(payload) -> None:
    print(f"REHEARSAL_JSON:{json.dumps(payload, sort_keys=True)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="rehearsal_harness")
    subcommands = parser.add_subparsers(dest="command", required=True)
    fixtures = subcommands.add_parser("fixtures")
    fixtures.add_argument("--output", required=True)
    run = subcommands.add_parser("run")
    run.add_argument("--pilot-bundle", required=True)
    run.add_argument("--final-bundle", required=True)
    run.add_argument("--output", required=True)
    arguments = parser.parse_args(argv)

    if arguments.command == "fixtures":
        _emit(write_fixtures(arguments.output))
        return 0
    if arguments.command == "run":
        _emit(run_routes(arguments.pilot_bundle, arguments.final_bundle, arguments.output))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
