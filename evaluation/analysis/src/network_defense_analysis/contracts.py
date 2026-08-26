from __future__ import annotations

import csv
import hashlib
import json
import math
import re
import shutil
from dataclasses import dataclass
from pathlib import Path

from .archive import _read_input
from .errors import AnalysisError


PAYLOAD_FILES = (
    "manifest.resolved.json",
    "graph.json",
    "plans.jsonl",
    "trials.csv",
    "capability_outcomes.csv",
    "summary.csv",
)
REQUIRED_FILES = PAYLOAD_FILES + (
    "checksums.txt",
)
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


@dataclass
class LoadedExport:
    root: Path
    temporary: Path | None
    manifest: dict
    plans: list[dict]
    trials: list[dict]
    capabilities: list[dict]
    summary: list[dict]
    hashes: dict[str, str]
    checksum_hash: str


def _error(message: str) -> AnalysisError:
    return AnalysisError(message)


def _required_files(root: Path) -> None:
    missing = [name for name in REQUIRED_FILES if not (root / name).is_file()]
    if missing:
        raise _error(f"missing required files: {', '.join(missing)}")


def _input_hashes(root: Path) -> dict[str, str]:
    return {
        name: hashlib.sha256((root / name).read_bytes()).hexdigest()
        for name in PAYLOAD_FILES
    }


def _verify_checksums(root: Path) -> None:
    entries = []
    for line in (root / "checksums.txt").read_text().splitlines():
        if not line.strip():
            raise _error("malformed checksums.txt")
        parts = line.split()
        if len(parts) != 2:
            raise _error("malformed checksums.txt")
        name, expected = parts
        if name in entries or name not in PAYLOAD_FILES or len(expected) != 64:
            raise _error(f"invalid checksum entry: {name}")
        try:
            int(expected, 16)
        except ValueError as exc:
            raise _error(f"invalid checksum entry: {name}") from exc
        path = root / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise _error(f"checksum mismatch: {name}")
        entries.append(name)
    if set(entries) != set(PAYLOAD_FILES):
        raise _error("checksums.txt does not cover exactly the payload files")


def _csv_rows(path: Path, expected: tuple[str, ...]) -> list[dict[str, str]]:
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream)
        fieldnames = reader.fieldnames or []
        if len(fieldnames) != len(set(fieldnames)) or None in fieldnames:
            raise _error(f"{path.name} has duplicate or malformed headers")
        if fieldnames != list(expected):
            raise _error(f"{path.name} has invalid headers")
        rows = list(reader)
        for row in rows:
            if None in row or any(value is None for value in row.values()):
                raise _error(f"{path.name} has a malformed row")
            if not any(value.strip() for value in row.values()):
                raise _error(f"{path.name} has a blank row")
        return rows


def _finite(value: str | None, field: str) -> float:
    if isinstance(value, bool):
        raise _error(f"invalid {field}")
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise _error(f"invalid {field}") from exc
    if not math.isfinite(result):
        raise _error(f"non-finite {field}")
    return result


def _integer(value: str | int | None, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        raise _error(f"invalid {field}")
    if isinstance(value, str) and not re.fullmatch(r"[+-]?\d+", value):
        raise _error(f"invalid {field}")
    return int(value)


def _load(source: str | Path) -> LoadedExport:
    root, temporary = _read_input(source)
    try:
        _required_files(root)
        _verify_checksums(root)
        hashes = _input_hashes(root)
        checksum_hash = hashlib.sha256((root / "checksums.txt").read_bytes()).hexdigest()
        try:
            manifest = json.loads((root / "manifest.resolved.json").read_text())
        except json.JSONDecodeError as exc:
            raise _error(f"invalid manifest: {exc}") from exc
        plans = []
        for line_number, line in enumerate((root / "plans.jsonl").read_text().splitlines(), 1):
            try:
                plans.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise _error(f"invalid plan at line {line_number}") from exc
        trials = _csv_rows(root / "trials.csv", TRIAL_HEADERS)
        capabilities = _csv_rows(root / "capability_outcomes.csv", CAPABILITY_HEADERS)
        summary = _csv_rows(root / "summary.csv", SUMMARY_HEADERS)
        return LoadedExport(root, temporary, manifest, plans, trials, capabilities, summary, hashes, checksum_hash)
    except (UnicodeError, NotImplementedError) as exc:
        if temporary:
            shutil.rmtree(temporary, ignore_errors=True)
        raise _error(f"invalid encoded input: {exc}") from exc
    except Exception:
        if temporary:
            shutil.rmtree(temporary, ignore_errors=True)
        raise


def _configuration(manifest: dict) -> dict:
    if not isinstance(manifest, dict):
        raise _error("manifest must be an object")
    configuration = manifest.get("analysis")
    required = (
        "primary_comparisons",
        "confidence_level",
        "bootstrap_resamples",
        "permutation_resamples",
        "multiplicity_correction",
        "seed",
    )
    if not isinstance(configuration, dict) or any(key not in configuration for key in required):
        raise _error("manifest analysis configuration is incomplete")
    if not isinstance(configuration["primary_comparisons"], list) or not configuration["primary_comparisons"]:
        raise _error("primary_comparisons must be a non-empty list")
    correction = configuration["multiplicity_correction"]
    if correction not in ("holm", "none"):
        raise _error(f"unsupported multiplicity correction: {correction}")
    confidence = _finite(configuration["confidence_level"], "confidence_level")
    if not 0 < confidence < 1:
        raise _error("confidence_level must be between zero and one")
    for field in ("bootstrap_resamples", "permutation_resamples"):
        if _integer(configuration[field], field) < 1:
            raise _error(f"{field} must be positive")
    if _integer(configuration["seed"], "analysis seed") < 0:
        raise _error("analysis seed must be non-negative")
    pilot = configuration.get("pilot")
    if not isinstance(pilot, dict) or "ci_half_width" not in pilot:
        raise _error("manifest analysis.pilot.ci_half_width is required")
    if _finite(pilot["ci_half_width"], "pilot ci_half_width") <= 0:
        raise _error("pilot ci_half_width must be positive")
    return configuration


MODEL_VARIANTS = {
    "full": ("mission_then_blast_radius", True),
    "blast_only_unconstrained": ("blast_radius_only", False),
    "mission_only": ("mission_impact_only", True),
}
OBJECTIVES = tuple(objective for objective, _ in MODEL_VARIANTS.values())


def _manifest_requirements(manifest: dict) -> int:
    if not isinstance(manifest, dict):
        raise _error("manifest must be an object")
    if manifest.get("schema_version") != 3:
        raise _error("manifest schema_version must be 3")
    for field in ("id", "model_version", "model_variants", "strategy_runs", "analysis"):
        if field not in manifest or manifest[field] in (None, ""):
            raise _error(f"manifest field is required: {field}")
    if not isinstance(manifest["model_variants"], list) or not manifest["model_variants"]:
        raise _error("manifest model_variants must be a non-empty list")
    variants = {}
    for variant in manifest["model_variants"]:
        if not isinstance(variant, dict) or not isinstance(variant.get("id"), str) or not variant["id"]:
            raise _error("malformed model variant")
        if variant["id"] in variants:
            raise _error(f"duplicate model variant: {variant['id']}")
        canonical = MODEL_VARIANTS.get(variant["id"])
        if canonical is None:
            raise _error(f"unknown model variant: {variant['id']}")
        if variant.get("objective") != canonical[0]:
            raise _error(f"model variant objective does not match: {variant['id']}")
        if variant.get("require_pre_attack_feasibility") is not canonical[1]:
            raise _error(f"model variant feasibility rule does not match: {variant['id']}")
        variants[variant["id"]] = variant
    if not isinstance(manifest["strategy_runs"], list):
        raise _error("manifest strategy_runs must be a list")
    evaluation = manifest.get("evaluation")
    if not isinstance(evaluation, dict) or "trials" not in evaluation:
        raise _error("manifest field is required: evaluation.trials")
    trial_count = _integer(evaluation["trials"], "evaluation.trials")
    if trial_count < 2:
        raise _error("evaluation.trials must be at least 2 for statistical analysis")
    return trial_count


def _declared_plans(manifest: dict, plans: list[dict]) -> tuple[dict[str, tuple[str, str, int, int]], list[tuple[str, str, int, int]]]:
    variants = {variant["id"]: variant for variant in manifest.get("model_variants", []) if isinstance(variant, dict)}
    declared = []
    for run in manifest.get("strategy_runs", []):
        if not isinstance(run, dict) or not {"model_variant", "strategy", "budget", "selection_seeds"} <= set(run):
            raise _error("malformed strategy run")
        model_variant = run["model_variant"]
        strategy = run["strategy"]
        seeds = run["selection_seeds"]
        budget = _integer(run["budget"], "budget")
        if (
            not isinstance(model_variant, str)
            or not model_variant
            or model_variant not in variants
            or not isinstance(strategy, str)
            or not strategy
            or not isinstance(seeds, list)
            or not seeds
            or budget <= 0
        ):
            raise _error("malformed strategy run")
        for seed in seeds:
            selection_seed = _integer(seed, "selection_seed")
            if selection_seed < 0:
                raise _error("selection_seed must be non-negative")
            declared.append((model_variant, strategy, budget, selection_seed))
    declared_set = set(declared)
    if len(declared_set) != len(declared):
        raise _error("manifest contains duplicate plan identities")
    identities = {}
    plan_ids = set()
    for plan in plans:
        if not isinstance(plan, dict):
            raise _error("malformed plan record")
        plan_id = plan.get("id")
        if not isinstance(plan_id, str) or not plan_id or plan_id in plan_ids:
            raise _error(f"plan ID is missing or duplicated: {plan_id}")
        plan_ids.add(plan_id)
        model_variant = plan.get("model_variant")
        strategy = plan.get("strategy")
        if not isinstance(model_variant, str) or not model_variant:
            raise _error("plan model_variant must be a non-empty string")
        if not isinstance(strategy, str) or not strategy:
            raise _error("plan strategy must be a non-empty string")
        budget = _integer(plan.get("requested_budget", plan.get("budget")), "plan budget")
        selection_seed = _integer(plan.get("selection_seed"), "plan selection seed")
        identity = (model_variant, strategy, budget, selection_seed)
        if identity not in declared_set:
            raise _error(f"undeclared plan: {identity}")
        if identity in identities.values():
            raise _error(f"duplicate plan identity: {identity}")
        declaration = variants[model_variant]
        if plan.get("objective") != declaration.get("objective"):
            raise _error(f"plan objective does not match its model variant: {plan_id}")
        if plan.get("require_pre_attack_feasibility") is not declaration.get("require_pre_attack_feasibility"):
            raise _error(f"plan feasibility rule does not match its model variant: {plan_id}")
        if plan.get("status") not in (None, "completed"):
            raise _error(f"incomplete plan: {identity}")
        identities[plan_id] = identity
    if set(identities.values()) != declared_set:
        raise _error(f"missing declared plans: {sorted(declared_set - set(identities.values()))}")
    return identities, declared


def _normalise_trials(plan_ids: set[str], rows: list[dict], expected_trials: int) -> tuple[dict[tuple[str, int], dict], dict[str, list[int]]]:
    values = {}
    schedules = {}
    trial_indices = {}
    attack_seeds = {}
    for row in rows:
        plan_id = row.get("plan_id", "").strip()
        if not plan_id:
            continue
        if plan_id not in plan_ids:
            raise _error(f"unknown plan in trial: {plan_id}")
        trial_index = _integer(row.get("trial_index"), "trial_index")
        seed = _integer(row.get("seed"), "attack seed")
        if trial_index < 1 or trial_index > expected_trials or seed < 0:
            raise _error(f"invalid trial index or attack seed for plan {plan_id}")
        key = (plan_id, trial_index)
        if trial_index in trial_indices.setdefault(plan_id, set()) or seed in attack_seeds.setdefault(plan_id, set()):
            raise _error(f"duplicate trial record for plan {plan_id}, trial {trial_index}, seed {seed}")
        trial_indices[plan_id].add(trial_index)
        attack_seeds[plan_id].add(seed)
        blast_radius = _finite(row.get("blast_radius"), "blast_radius")
        mission_impact = _finite(row.get("mission_impact"), "mission_impact")
        if blast_radius < 0 or mission_impact < 0:
            raise _error(f"trial outcomes must be non-negative for plan {plan_id}")
        values[key] = {
            "seed": seed,
            "blast_radius": blast_radius,
            "mission_impact": mission_impact,
        }
        schedules.setdefault(plan_id, []).append(seed)
    if not values:
        raise _error("no declared-plan trial records")
    for plan_id in plan_ids:
        indexes = sorted(index for candidate, index in values if candidate == plan_id)
        if indexes != list(range(1, expected_trials + 1)):
            raise _error(f"plan {plan_id} does not contain exactly evaluation.trials records")
        schedules[plan_id] = [values[(plan_id, index)]["seed"] for index in indexes]
    return values, schedules


def _normalise_capabilities(
    plan_ids: set[str], rows: list[dict], trials: dict[tuple[str, int], dict]
) -> tuple[dict[tuple[str, int, str], int], dict[str, str]]:
    values = {}
    capabilities_by_trial = {}
    names = {}
    for row in rows:
        plan_id = row.get("plan_id", "").strip()
        if not plan_id:
            continue
        if plan_id not in plan_ids:
            raise _error(f"unknown plan in capability outcome: {plan_id}")
        trial_index = _integer(row.get("trial_index"), "capability trial_index")
        seed = _integer(row.get("seed"), "capability attack seed")
        trial = trials.get((plan_id, trial_index))
        if trial is None or trial["seed"] != seed:
            raise _error(f"capability row does not match trial: {plan_id}, {trial_index}")
        capability_id = row.get("capability_id", "").strip()
        capability_name = row.get("capability_name", "").strip()
        if not capability_id or not capability_name:
            raise _error("capability ID and name must be non-empty")
        if capability_id in names and names[capability_id] != capability_name:
            raise _error(f"conflicting capability names for ID: {capability_id}")
        names[capability_id] = capability_name
        key = (plan_id, seed, capability_id)
        if not key[2] or key in values:
            raise _error(f"duplicate capability record: {key}")
        capabilities_by_trial.setdefault((plan_id, seed), set()).add(key[2])
        disrupted = row.get("disrupted", "").lower()
        if disrupted not in ("true", "false", "1", "0"):
            raise _error(f"invalid disrupted value: {disrupted}")
        values[key] = int(disrupted in ("true", "1"))
    expected_trials = {(plan_id, trial["seed"]) for (plan_id, _), trial in trials.items()}
    capability_sets = {frozenset(ids) for ids in capabilities_by_trial.values()}
    if set(capabilities_by_trial) != expected_trials or len(capability_sets) != 1:
        raise _error("capability outcomes must cover every trial consistently")
    return values, names

__all__ = [
    "LoadedExport",
    "MODEL_VARIANTS",
    "OBJECTIVES",
    "PAYLOAD_FILES",
    "REQUIRED_FILES",
    "TRIAL_HEADERS",
    "CAPABILITY_HEADERS",
    "SUMMARY_HEADERS",
    "_load",
    "_configuration",
    "_manifest_requirements",
    "_declared_plans",
    "_normalise_trials",
    "_normalise_capabilities",
]
