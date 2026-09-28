"""Study-level bundle loading and single Holm family correction.

The study layer treats every tier archive as immutable bytes. It reads the
declared tier archives through the existing archive loader. It builds one
primary family, validates the declared matrix, and applies one Holm correction
to all primary raw p-values.

Statistics stay in ``statistics.py``. This module owns bundle validation,
family assembly, two-dimensional pilot selection, and transport only.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path
from statistics import median

import numpy as np

from .archive import MAX_COMPRESSED_STDIN, _safe_extract, verify_checksum_file, write_result_zip
from .contracts import LoadedExport, _configuration, _dependency_versions, _finite, _integer, _load, _package_version
from .errors import _error
from .report import OUTPUT_HEADERS, _json_safe, _primary_comparisons, _runtime, _write_csv
from .statistics import (
    MIN_ATTACK_COUNT,
    MIN_PLAN_COUNT,
    CrossedComparison,
    _comparison_stream_seed,
    _crossed_statistics,
    _holm,
)

MAX_PILOT_CANDIDATES = 64
"""Maximum declared candidate counts in one pilot grid."""

STUDY_SEED_STRIDE = 1_000_000
"""Per-tier stream-seed stride for deterministic study resampling."""

STUDY_PRIMARY_HEADERS = ("tier", "comparison_id") + OUTPUT_HEADERS["primary_results.csv"]
"""Primary result columns for the study family. Older columns are unchanged."""

STUDY_FILES = (
    "study_metadata.json",
    "primary_results.csv",
    "primary_results.json",
    "tier_context.json",
)
"""Files in the study result ZIP. ``checksums.txt`` covers exactly these."""

MAX_PILOT_SUBSAMPLES = 500
"""Maximum outer subsamples in one pilot candidate evaluation."""

PILOT_SELECTION_RULE = "lowest_predicted_runtime"
"""Supported deterministic pilot candidate selection rule."""

PILOT_HEADERS = (
    "comparison_id",
    "tier",
    "informative",
    "candidate_plan_count",
    "candidate_attacks_per_plan",
    "guarded_ci_half_width",
    "target",
    "passes",
)
"""Pilot result columns. Order is fixed and deterministic."""

PILOT_FILES = (
    "study_metadata.json",
    "pilot_results.csv",
    "pilot_results.json",
)
"""Files in the pilot result ZIP. ``checksums.txt`` covers exactly these."""


@dataclass(frozen=True)
class PilotConfiguration:
    """Validated two-dimensional pilot grid and selection rules."""

    ci_half_width: float
    plan_count_candidates: tuple[int, ...]
    attacks_per_plan_candidates: tuple[int, ...]
    guard_quantile: float
    subsamples: int
    seed: int
    selection_rule: str


@dataclass(frozen=True)
class CandidateResult:
    """Guarded pilot outcome for one plan-and-attack candidate pair."""

    plan_count: int
    attacks_per_plan: int
    guarded_half_width: float
    passes: bool


@dataclass(frozen=True)
class PilotRecommendation:
    """One common sample recommendation or an explicit insufficient result."""

    plan_selection_seed_count: int | None
    attacks_per_plan: int | None
    insufficient_pilot: bool
    non_informative_comparisons: tuple[str, ...]


@dataclass(frozen=True)
class RuntimeInputs:
    """Measured runtime inputs for the deterministic selection heuristic."""

    median_plan_selection_ms: float
    median_attack_trial_ms: float
    strategy_group_count: int
    tier_count: int


@dataclass(frozen=True)
class _PilotComparison:
    """One declared comparison plus the pilot identity used for resampling."""

    tier_index: int
    comparison_index: int
    tier: str
    comparison_id: str
    crossed: CrossedComparison
    informative: bool


@dataclass(frozen=True)
class StudyTier:
    """One loaded tier archive and its immutable identity."""

    label: str
    archive_path: str
    archive_sha256: str
    loaded_export: LoadedExport


@dataclass(frozen=True)
class LoadedStudy:
    """A validated study bundle ready for family analysis."""

    study_id: str
    specification_version: int
    configuration: dict
    tiers: tuple[StudyTier, ...]


def comparison_id(tier: str, comparison: dict) -> str:
    """Return the stable cross-tier identity for one primary comparison."""

    return "|".join(
        [
            tier,
            comparison["model_variant"],
            comparison["strategy"],
            comparison["baseline_model_variant"],
            comparison["baseline"],
            str(comparison["budget"]),
            comparison["outcome"],
        ]
    )


def load_study_bundle(source: str | Path) -> LoadedStudy:
    """Load and validate one analysis-input study ZIP.

    Outer limits and safe paths are checked before extraction. Tier archives
    stay byte-identical. Each tier is loaded through the existing archive
    loader, which keeps the inner limits unchanged.
    """

    path = Path(source)
    if not path.is_file() or path.suffix.lower() != ".zip":
        raise _error("study input must be a ZIP file")
    if path.stat().st_size > MAX_COMPRESSED_STDIN:
        raise _error(f"study ZIP compressed byte limit exceeded: {MAX_COMPRESSED_STDIN}")

    root, temporary = _safe_extract(path)
    loaded: list[LoadedExport] = []
    try:
        for required in ("study.json", "checksums.txt"):
            if not (root / required).is_file():
                raise _error(f"missing study bundle file: {required}")

        spec = _parse_spec(root)
        study_id = spec.get("study_id")
        if not isinstance(study_id, str) or not study_id:
            raise _error("study.json study_id must be a non-empty string")
        specification_version = _integer(spec.get("specification_version"), "specification_version")
        if specification_version < 1:
            raise _error("specification_version must be positive")

        tier_entries = _spec_tiers(spec)
        expected_members = {"study.json", "checksums.txt"} | {entry["archive"] for entry in tier_entries}
        actual_members = _member_files(root)
        if actual_members != expected_members:
            missing = sorted(expected_members - actual_members)
            unexpected = sorted(actual_members - expected_members)
            raise _error(
                "study bundle members do not match the declaration: "
                f"missing={missing} unexpected={unexpected}"
            )
        _verify_outer_checksums(root, expected_members - {"checksums.txt"})

        family = _expected_family(spec)
        pilot = _pilot(spec)
        pilot_schedule = _seed_schedule(spec, "pilot_seed_schedule")
        final_schedule = _seed_schedule(spec, "final_seed_schedule")
        for key in ("selection", "evaluation"):
            if set(pilot_schedule[key]) & set(final_schedule[key]):
                raise _error(f"pilot and final {key} seed schedules overlap")
        if spec.get("multiplicity_correction") != "holm":
            raise _error("study multiplicity_correction must be holm")

        tiers = []
        for entry in tier_entries:
            tier_path = root / entry["archive"]
            if not tier_path.is_file():
                raise _error(f"missing tier archive: {entry['archive']}")
            digest = hashlib.sha256(tier_path.read_bytes()).hexdigest()
            if digest != entry["sha256"]:
                raise _error(f"tier archive checksum mismatch: {entry['label']}")
            export = _load(tier_path)
            loaded.append(export)
            tiers.append(StudyTier(entry["label"], entry["archive"], digest, export))

        analysis = _validate_common_settings(tiers)
        expected_pairs = _expected_pairs(family)
        for tier in tiers:
            _validate_matrix(tier, expected_pairs)
        _stable_ids(
            [
                (tier.label, comparison)
                for tier in tiers
                for comparison in _configuration(tier.loaded_export.manifest)["primary_comparisons"]
            ]
        )

        family_size = len(tiers) * len(family["strategies"]) * len(family["budgets"])
        configuration = {
            "expected_family": family,
            "family_size": family_size,
            "multiplicity_correction": "holm",
            "pilot": pilot,
            "pilot_seed_schedule": pilot_schedule,
            "final_seed_schedule": final_schedule,
            "analysis": analysis,
        }
        return LoadedStudy(study_id, specification_version, configuration, tuple(tiers))
    except Exception:
        _release_loaded(loaded)
        raise
    finally:
        shutil.rmtree(temporary, ignore_errors=True)


def analyze_study(source: str | Path | LoadedStudy, output: str | Path) -> None:
    """Analyze the full family and write one deterministic result ZIP.

    The task interface accepts an input path. A ``LoadedStudy`` is also
    accepted so callers that already validated a bundle can reuse it.
    """

    owns_study = not isinstance(source, LoadedStudy)
    study: LoadedStudy | None = None
    destination = Path(output)
    directory = Path(tempfile.mkdtemp())
    try:
        study = load_study_bundle(source) if owns_study else source
        _enforce_seed_schedule(study, "final")
        rows: list[dict] = []
        tier_context: list[dict] = []
        for tier_index, tier in enumerate(study.tiers):
            export = tier.loaded_export
            _, _, _, _, _, comparisons = _primary_comparisons(
                export.manifest,
                export.plans,
                export.trials,
                stream_seed_offset=tier_index * STUDY_SEED_STRIDE,
            )
            comparison_ids = []
            for item in comparisons:
                row = dict(item.row)
                row["tier"] = tier.label
                row["comparison_id"] = comparison_id(tier.label, item.comparison)
                comparison_ids.append(row["comparison_id"])
                rows.append(row)
            first = comparisons[0].statistics if comparisons else None
            tier_context.append(
                {
                    "label": tier.label,
                    "archive": tier.archive_path,
                    "archive_sha256": tier.archive_sha256,
                    "manifest_id": export.manifest.get("id"),
                    "model_version": export.manifest.get("model_version"),
                    "checksums_hash": export.checksum_hash,
                    "input_hashes": export.hashes,
                    "comparison_ids": sorted(comparison_ids),
                    "tested_plan_count": first.tested_plan_count if first else 0,
                    "baseline_plan_count": first.baseline_plan_count if first else 0,
                    "attacks_per_plan": first.attacks_per_plan if first else 0,
                }
            )

        family_size = study.configuration["family_size"]
        if len(rows) != family_size:
            raise _error("study family size does not match the specification")
        _apply_family_correction(rows, study.configuration["multiplicity_correction"])
        ordered = sorted(rows, key=lambda row: row["comparison_id"])

        metadata = {
            "study_id": study.study_id,
            "specification_version": study.specification_version,
            "family_scope": "study",
            "family_size": family_size,
            "multiplicity_correction": "holm",
            "tier_labels": [tier.label for tier in study.tiers],
            "expected_family": study.configuration["expected_family"],
            "pilot": study.configuration["pilot"],
            "analysis_configuration": study.configuration["analysis"],
            "tier_context": tier_context,
            "uncertainty_sources": ["plan_selection", "attack_outcome"],
            "estimand_note": "The interval includes independent plan-row and shared attack-column resampling.",
            "command_mode": "study-analyze",
            "package_version": _package_version(),
            "dependencies": _dependency_versions(),
        }

        _write_csv(directory / "primary_results.csv", ordered, STUDY_PRIMARY_HEADERS)
        (directory / "primary_results.json").write_text(
            json.dumps(_json_safe(ordered), sort_keys=True, indent=2) + "\n"
        )
        (directory / "tier_context.json").write_text(
            json.dumps(_json_safe(tier_context), sort_keys=True, indent=2) + "\n"
        )
        (directory / "study_metadata.json").write_text(
            json.dumps(_json_safe(metadata), sort_keys=True, indent=2) + "\n"
        )
        _write_checksums(directory, STUDY_FILES)

        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("wb") as stream:
            write_result_zip(directory, stream)
    finally:
        shutil.rmtree(directory, ignore_errors=True)
        if owns_study and study is not None:
            _release_study(study)


def _parse_spec(root: Path) -> dict:
    try:
        spec = json.loads((root / "study.json").read_text())
    except json.JSONDecodeError as exc:
        raise _error(f"invalid study.json: {exc}") from exc
    if not isinstance(spec, dict):
        raise _error("study.json must be an object")
    return spec


def _member_files(root: Path) -> set[str]:
    return {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
    }


def _safe_member_name(name) -> str:
    if not isinstance(name, str) or not name:
        raise _error("tier archive path must be a non-empty string")
    path = Path(name)
    if path.is_absolute() or ".." in path.parts:
        raise _error(f"unsafe tier archive path: {name}")
    if name in ("study.json", "checksums.txt"):
        raise _error(f"tier archive path conflicts with a bundle file: {name}")
    return name


def _spec_tiers(spec: dict) -> list[dict]:
    entries = spec.get("tiers")
    if not isinstance(entries, list) or not entries:
        raise _error("study.json tiers must be a non-empty list")
    parsed = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise _error("study.json tier entries must be objects")
        label = entry.get("label")
        if not isinstance(label, str) or not label:
            raise _error("tier label must be a non-empty string")
        archive = _safe_member_name(entry.get("archive"))
        digest = entry.get("sha256")
        if not isinstance(digest, str) or len(digest) != 64:
            raise _error(f"tier {label} sha256 must be a 64-character hex digest")
        try:
            int(digest, 16)
        except ValueError as exc:
            raise _error(f"tier {label} sha256 must be a hex digest") from exc
        parsed.append({"label": label, "archive": archive, "sha256": digest.lower()})
    labels = [entry["label"] for entry in parsed]
    if len(set(labels)) != len(labels):
        raise _error("tier labels must be unique")
    archives = [entry["archive"] for entry in parsed]
    if len(set(archives)) != len(archives):
        raise _error("tier archive paths must be unique")
    return parsed


def _verify_outer_checksums(root: Path, expected_names: set[str]) -> None:
    verify_checksum_file(
        root, expected_names, "checksums.txt does not cover exactly the bundle files"
    )


def _expected_family(spec: dict) -> dict:
    family = spec.get("expected_family")
    if not isinstance(family, dict):
        raise _error("study.json expected_family must be an object")
    strategies = family.get("strategies")
    if not isinstance(strategies, list) or not strategies:
        raise _error("expected_family.strategies must be a non-empty list")
    if any(not isinstance(strategy, str) or not strategy for strategy in strategies):
        raise _error("expected_family.strategies must be non-empty strings")
    if len(set(strategies)) != len(strategies):
        raise _error("expected_family.strategies must be unique")
    baseline = family.get("baseline")
    if not isinstance(baseline, str) or not baseline:
        raise _error("expected_family.baseline must be a non-empty string")
    if baseline in strategies:
        raise _error("expected_family.baseline must not be an alternative")
    budgets = family.get("budgets")
    if not isinstance(budgets, list) or not budgets:
        raise _error("expected_family.budgets must be a non-empty list")
    cleaned_budgets = []
    for budget in budgets:
        value = _integer(budget, "expected_family budget")
        if value < 1:
            raise _error("expected_family budgets must be positive")
        cleaned_budgets.append(value)
    if len(set(cleaned_budgets)) != len(cleaned_budgets):
        raise _error("expected_family budgets must be unique")
    outcome = family.get("outcome")
    if outcome != "mission_impact":
        raise _error("expected_family.outcome must be mission_impact")
    return {
        "strategies": list(strategies),
        "baseline": baseline,
        "budgets": cleaned_budgets,
        "outcome": outcome,
    }


def _expected_pairs(family: dict) -> set[tuple[str, int, str, str]]:
    return {
        (strategy, budget, family["baseline"], family["outcome"])
        for strategy in family["strategies"]
        for budget in family["budgets"]
    }


def _pilot(spec: dict) -> dict:
    pilot = spec.get("pilot")
    if not isinstance(pilot, dict):
        raise _error("study.json pilot must be an object")
    target = _finite(pilot.get("ci_half_width"), "pilot ci_half_width")
    if target <= 0:
        raise _error("pilot ci_half_width must be positive")
    configuration = {
        "ci_half_width": target,
        "plan_count_candidates": _pilot_candidates(pilot.get("plan_count_candidates"), MIN_PLAN_COUNT, "plan_count_candidates"),
        "attacks_per_plan_candidates": _pilot_candidates(pilot.get("attacks_per_plan_candidates"), MIN_ATTACK_COUNT, "attacks_per_plan_candidates"),
    }
    # The pilot-selection fields are surfaced when declared. They are validated
    # by the shared ``_pilot_configuration`` before any candidate is evaluated.
    for key in ("guard_quantile", "subsamples", "seed", "selection_rule"):
        if key in pilot:
            configuration[key] = pilot[key]
    return configuration


def _seed_list(value, field: str) -> list[int]:
    if not isinstance(value, list) or not value:
        raise _error(f"{field} must be a non-empty list")
    cleaned = []
    for item in value:
        seed = _integer(item, field)
        if seed < 0:
            raise _error(f"{field} seeds must be non-negative")
        cleaned.append(seed)
    if len(set(cleaned)) != len(cleaned):
        raise _error(f"{field} seeds must be unique")
    return cleaned


def _seed_schedule(spec: dict, name: str) -> dict[str, list[int]]:
    schedule = spec.get(name)
    if not isinstance(schedule, dict):
        raise _error(f"study.json {name} must be an object")
    return {
        key: _seed_list(schedule.get(key), f"{name}.{key}")
        for key in ("selection", "evaluation")
    }


def _tier_evaluation_seed(manifest: dict, label: str) -> int:
    """Return one tier's declared evaluation seed."""

    evaluation = manifest.get("evaluation")
    if not isinstance(evaluation, dict) or "seed" not in evaluation:
        raise _error(f"tier {label} evaluation.seed is required to validate the seed schedule")
    return _integer(evaluation["seed"], f"tier {label} evaluation.seed")


def _run_selection_seeds(run, label: str) -> list[int]:
    """Return one strategy run's declared selection seeds."""

    if not isinstance(run, dict):
        raise _error(f"tier {label} strategy run must be an object")
    seeds = run.get("selection_seeds")
    if not isinstance(seeds, list) or not seeds:
        raise _error(f"tier {label} strategy run selection_seeds must be a non-empty list")
    return [_integer(seed, f"tier {label} selection seed") for seed in seeds]


def _enforce_seed_schedule(study: LoadedStudy, phase: str) -> None:
    """Reject loaded tiers whose seeds do not match the declared schedule.

    ``phase`` is ``"pilot"`` or ``"final"``. Pilot mode uses the pilot
    schedule and analyze mode uses the final schedule. The evaluation seeds
    across tiers must equal the declared evaluation set. Every strategy run
    and exported plan must use a non-empty subset of the declared selection
    set. A final manifest may use only the pilot-selected subset, so not every
    declared selection seed must appear.
    """

    schedule = study.configuration[f"{phase}_seed_schedule"]
    declared_selection = set(schedule["selection"])
    declared_evaluation = set(schedule["evaluation"])
    observed_evaluation: set[int] = set()
    for tier in study.tiers:
        manifest = tier.loaded_export.manifest
        observed_evaluation.add(_tier_evaluation_seed(manifest, tier.label))
        runs = manifest.get("strategy_runs")
        if not isinstance(runs, list):
            raise _error(f"tier {tier.label} strategy_runs must be a list")
        for run in runs:
            seeds = _run_selection_seeds(run, tier.label)
            if not set(seeds) <= declared_selection:
                raise _error(
                    f"tier {tier.label} strategy run selection seeds are not "
                    f"in the declared {phase} schedule"
                )
        for plan in tier.loaded_export.plans:
            seed = _integer(plan.get("selection_seed"), "plan selection seed")
            if seed not in declared_selection:
                raise _error(
                    f"plan {plan.get('id')} selection seed is not in the "
                    f"declared {phase} schedule"
                )
    if observed_evaluation != declared_evaluation:
        raise _error(
            f"tier evaluation seeds do not match the declared {phase} schedule"
        )


def _validate_common_settings(tiers: list[StudyTier]) -> dict:
    configurations = [_configuration(tier.loaded_export.manifest) for tier in tiers]
    first = configurations[0]
    for tier, configuration in zip(tiers, configurations):
        if configuration["multiplicity_correction"] != "holm":
            raise _error(f"tier {tier.label} multiplicity_correction must be holm")
        for key in ("confidence_level", "bootstrap_resamples", "permutation_resamples", "multiplicity_correction", "seed"):
            if configuration[key] != first[key]:
                raise _error(f"tier {tier.label} analysis setting {key} disagrees with other tiers")
    _validate_single_model_variant(tiers)
    return first


def _validate_single_model_variant(tiers: list[StudyTier]) -> str:
    """Require one model variant across every loaded tier.

    The study specification supports one model variant. Multi-variant family
    math is not implemented.
    """

    variants: set[str] = set()
    for tier in tiers:
        declared = tier.loaded_export.manifest.get("model_variants")
        if not isinstance(declared, list) or not declared:
            raise _error(f"tier {tier.label} model_variants must be a non-empty list")
        ids = []
        for variant in declared:
            if not isinstance(variant, dict) or not isinstance(variant.get("id"), str) or not variant["id"]:
                raise _error(f"tier {tier.label} has a malformed model variant")
            ids.append(variant["id"])
        if len(set(ids)) != len(ids):
            raise _error(f"tier {tier.label} declares duplicate model variants")
        variants.update(ids)
    if len(variants) != 1:
        raise _error(
            "study supports exactly one model variant across all tiers: "
            f"found {sorted(variants)}"
        )
    return next(iter(variants))


def _comparison_pairs(configuration: dict) -> set[tuple]:
    required = {"strategy", "baseline", "budget", "model_variant", "baseline_model_variant", "outcome"}
    pairs = set()
    for comparison in configuration["primary_comparisons"]:
        if not isinstance(comparison, dict) or not required <= set(comparison):
            raise _error("malformed primary comparison")
        strategy = comparison["strategy"]
        baseline = comparison["baseline"]
        budget = _integer(comparison["budget"], "comparison budget")
        outcome = comparison["outcome"]
        pairs.add((strategy, budget, baseline, outcome))
    return pairs


def _validate_matrix(tier: StudyTier, expected_pairs: set[tuple]) -> None:
    configuration = _configuration(tier.loaded_export.manifest)
    comparisons = configuration["primary_comparisons"]
    pairs = _comparison_pairs(configuration)
    if len(pairs) != len(comparisons):
        raise _error(f"tier {tier.label} declares duplicate primary comparisons")
    if pairs != expected_pairs:
        raise _error(f"tier {tier.label} primary comparison matrix does not match expected_family")


def _stable_ids(pairs: list[tuple[str, dict]]) -> list[str]:
    ids = [comparison_id(tier, comparison) for tier, comparison in pairs]
    seen: set[str] = set()
    for value in ids:
        if value in seen:
            raise _error(f"duplicate primary comparison identity: {value}")
        seen.add(value)
    return ids


def _apply_family_correction(rows: list[dict], method: str) -> None:
    if method != "holm":
        raise _error(f"unsupported study multiplicity correction: {method}")
    ordered = sorted(rows, key=lambda row: row["comparison_id"])
    adjusted = _holm([float(row["p_raw"]) for row in ordered])
    for row, value in zip(ordered, adjusted):
        row["p_adjusted"] = float(value)


def _write_checksums(directory: Path, names: tuple[str, ...]) -> None:
    lines = [
        f"{name}  {hashlib.sha256((directory / name).read_bytes()).hexdigest()}"
        for name in names
    ]
    (directory / "checksums.txt").write_text("\n".join(lines) + "\n")


def pilot_study(source: str | Path | LoadedStudy, output: str | Path) -> None:
    """Select one common plan and attack count and write one result ZIP.

    The task interface accepts an input path. A ``LoadedStudy`` is also
    accepted so callers that already validated a bundle can reuse it. The
    runtime model is a selection heuristic only; it is not a statistical
    result.
    """

    owns_study = not isinstance(source, LoadedStudy)
    study: LoadedStudy | None = None
    destination = Path(output)
    directory = Path(tempfile.mkdtemp())
    try:
        study = load_study_bundle(source) if owns_study else source
        _enforce_seed_schedule(study, "pilot")
        configuration = _pilot_configuration(study.configuration["pilot"])
        analysis_configuration = study.configuration["analysis"]
        records = _pilot_comparisons(study)
        _validate_candidate_bounds(records, configuration)
        runtime_inputs = _runtime_inputs(study)

        rows: list[dict] = []
        summaries: list[CandidateResult] = []
        for plan_count in configuration.plan_count_candidates:
            for attacks_per_plan in configuration.attacks_per_plan_candidates:
                candidate_rows = []
                for record in records:
                    evaluation = _evaluate_candidate(
                        record.crossed,
                        plan_count=plan_count,
                        attacks_per_plan=attacks_per_plan,
                        configuration=configuration,
                        stream_seed=_comparison_stream_seed(
                            configuration.seed,
                            record.tier_index * STUDY_SEED_STRIDE,
                            record.comparison_index,
                        ),
                        analysis_configuration=analysis_configuration,
                    )
                    candidate_rows.append(
                        {
                            "comparison_id": record.comparison_id,
                            "tier": record.tier,
                            "informative": record.informative,
                            "candidate_plan_count": plan_count,
                            "candidate_attacks_per_plan": attacks_per_plan,
                            "guarded_ci_half_width": evaluation.guarded_half_width,
                            "target": configuration.ci_half_width,
                            "passes": bool(record.informative and evaluation.passes),
                        }
                    )
                rows.extend(candidate_rows)
                summaries.append(_aggregate_candidate(plan_count, attacks_per_plan, candidate_rows))

        non_informative = tuple(
            sorted({record.comparison_id for record in records if not record.informative})
        )
        recommendation = _recommendation(summaries, runtime_inputs, non_informative)
        ordered = sorted(
            rows,
            key=lambda row: (
                row["comparison_id"],
                row["candidate_plan_count"],
                row["candidate_attacks_per_plan"],
            ),
        )

        metadata = {
            "study_id": study.study_id,
            "specification_version": study.specification_version,
            "family_scope": "study",
            "family_size": study.configuration["family_size"],
            "command_mode": "study-pilot",
            "tier_labels": [tier.label for tier in study.tiers],
            "expected_family": study.configuration["expected_family"],
            "selection_rule": configuration.selection_rule,
            "pilot_configuration": asdict(configuration),
            "runtime_inputs": asdict(runtime_inputs),
            "runtime_model_note": "Runtime is a selection heuristic, not a statistical result.",
            "runtime_derivation": {
                "median_plan_selection_ms": "median plan runtime_ms across exported plans",
                "median_attack_trial_ms": (
                    "median of experiment runtime_ms divided by exported trial_count"
                ),
                "strategy_group_count": "maximum declared strategy_runs count across tiers",
                "plan_sample_count": sum(len(tier.loaded_export.plans) for tier in study.tiers),
                "experiment_sample_count": sum(len(tier.loaded_export.summary) for tier in study.tiers),
                "tier_count": len(study.tiers),
            },
            "recommendation": asdict(recommendation),
            "recommended_plan_selection_seed_count": recommendation.plan_selection_seed_count,
            "recommended_attacks_per_plan": recommendation.attacks_per_plan,
            "insufficient_pilot": recommendation.insufficient_pilot,
            "candidate_results": [asdict(result) for result in summaries],
            "non_informative_comparisons": list(recommendation.non_informative_comparisons),
            "uncertainty_sources": ["plan_selection", "attack_outcome"],
            "estimand_note": "The interval includes independent plan-row and shared attack-column resampling.",
            "analysis_configuration": analysis_configuration,
            "package_version": _package_version(),
            "dependencies": _dependency_versions(),
        }

        _write_csv(directory / "pilot_results.csv", ordered, PILOT_HEADERS)
        (directory / "pilot_results.json").write_text(
            json.dumps(_json_safe(ordered), sort_keys=True, indent=2) + "\n"
        )
        (directory / "study_metadata.json").write_text(
            json.dumps(_json_safe(metadata), sort_keys=True, indent=2) + "\n"
        )
        _write_checksums(directory, PILOT_FILES)

        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("wb") as stream:
            write_result_zip(directory, stream)
    finally:
        shutil.rmtree(directory, ignore_errors=True)
        if owns_study and study is not None:
            _release_study(study)


def _pilot_configuration(pilot: dict) -> PilotConfiguration:
    """Validate the declared pilot grid and selection rules."""

    target = _finite(pilot.get("ci_half_width"), "pilot ci_half_width")
    if target <= 0:
        raise _error("pilot ci_half_width must be positive")
    plans = _pilot_candidates(
        pilot.get("plan_count_candidates"), MIN_PLAN_COUNT, "plan_count_candidates"
    )
    attacks = _pilot_candidates(
        pilot.get("attacks_per_plan_candidates"), MIN_ATTACK_COUNT, "attacks_per_plan_candidates"
    )
    guard = _finite(pilot.get("guard_quantile"), "pilot guard_quantile")
    if not 0 < guard < 1:
        raise _error("pilot guard_quantile must be between zero and one")
    subsamples = _integer(pilot.get("subsamples"), "pilot subsamples")
    if subsamples < 1:
        raise _error("pilot subsamples must be positive")
    if subsamples > MAX_PILOT_SUBSAMPLES:
        raise _error(f"pilot subsamples exceeds the limit: {MAX_PILOT_SUBSAMPLES}")
    seed = _integer(pilot.get("seed"), "pilot seed")
    if seed < 0:
        raise _error("pilot seed must be non-negative")
    if pilot.get("selection_rule") != PILOT_SELECTION_RULE:
        raise _error(f"pilot selection_rule must be {PILOT_SELECTION_RULE}")
    return PilotConfiguration(
        ci_half_width=target,
        plan_count_candidates=tuple(plans),
        attacks_per_plan_candidates=tuple(attacks),
        guard_quantile=guard,
        subsamples=subsamples,
        seed=seed,
        selection_rule=PILOT_SELECTION_RULE,
    )


def _pilot_candidates(value, minimum: int, field: str) -> list[int]:
    """Return one unique, sorted, lower-bounded pilot candidate list."""

    if not isinstance(value, list) or not value:
        raise _error(f"pilot {field} must be a non-empty list")
    if len(value) > MAX_PILOT_CANDIDATES:
        raise _error(f"pilot {field} exceeds the candidate limit: {MAX_PILOT_CANDIDATES}")
    cleaned = []
    for item in value:
        count = _integer(item, field)
        if count < minimum:
            raise _error(f"pilot {field} entries must be at least {minimum}")
        cleaned.append(count)
    if len(set(cleaned)) != len(cleaned):
        raise _error(f"pilot {field} entries must be unique")
    if cleaned != sorted(cleaned):
        raise _error(f"pilot {field} entries must be sorted")
    return cleaned


def _pilot_comparisons(study: LoadedStudy) -> list[_PilotComparison]:
    """Build every declared crossed comparison across all tiers."""

    records = []
    for tier_index, tier in enumerate(study.tiers):
        export = tier.loaded_export
        _, _, _, _, _, comparisons = _primary_comparisons(
            export.manifest,
            export.plans,
            export.trials,
            stream_seed_offset=tier_index * STUDY_SEED_STRIDE,
        )
        for comparison_index, item in enumerate(comparisons):
            records.append(
                _PilotComparison(
                    tier_index=tier_index,
                    comparison_index=comparison_index,
                    tier=tier.label,
                    comparison_id=comparison_id(tier.label, item.comparison),
                    crossed=item.crossed,
                    informative=bool(item.statistics.informative),
                )
            )
    return records


def _validate_candidate_bounds(
    records: list[_PilotComparison], configuration: PilotConfiguration
) -> None:
    """Reject a candidate that is larger than any observed comparison."""

    for record in records:
        tested_plans, attack_count = record.crossed.tested.shape
        baseline_plans = record.crossed.baseline.shape[0]
        for plan_count in configuration.plan_count_candidates:
            if plan_count > tested_plans or plan_count > baseline_plans:
                raise _error(
                    "pilot plan candidate does not fit the observed comparison: "
                    f"{record.comparison_id} candidate={plan_count} "
                    f"tested={tested_plans} baseline={baseline_plans}"
                )
        for attacks_per_plan in configuration.attacks_per_plan_candidates:
            if attacks_per_plan > attack_count:
                raise _error(
                    "pilot attack candidate does not fit the observed comparison: "
                    f"{record.comparison_id} candidate={attacks_per_plan} attacks={attack_count}"
                )


def _evaluate_candidate(
    comparison: CrossedComparison,
    *,
    plan_count: int,
    attacks_per_plan: int,
    configuration: PilotConfiguration,
    stream_seed: int,
    analysis_configuration: dict,
) -> CandidateResult:
    """Evaluate one candidate pair on one observed comparison.

    Every outer subsample samples tested rows, baseline rows, and shared attack
    columns without replacement, then runs the crossed interval from its own
    deterministic child seed. The guarded half-width is the configured upper
    quantile of the subsample half-widths.

    ``analysis_configuration`` carries the shared ``confidence_level`` and
    ``bootstrap_resamples`` required by ``_crossed_statistics``.
    """

    tested_count, attack_count = comparison.tested.shape
    baseline_count = comparison.baseline.shape[0]
    if plan_count < MIN_PLAN_COUNT:
        raise _error(f"pilot plan candidate must be at least {MIN_PLAN_COUNT}")
    if attacks_per_plan < MIN_ATTACK_COUNT:
        raise _error(f"pilot attack candidate must be at least {MIN_ATTACK_COUNT}")
    if plan_count > tested_count or plan_count > baseline_count:
        raise _error("pilot plan candidate exceeds the observed comparison bounds")
    if attacks_per_plan > attack_count:
        raise _error("pilot attack candidate exceeds the observed attack count")
    if configuration.subsamples < 1:
        raise _error("pilot subsamples must be positive")

    sequence = np.random.SeedSequence([stream_seed, plan_count, attacks_per_plan])
    half_widths: list[float] = []
    informative = True
    for child in sequence.spawn(configuration.subsamples):
        sampling_sequence, bootstrap_sequence = child.spawn(2)
        rng = np.random.default_rng(sampling_sequence)
        tested_rows = rng.choice(tested_count, size=plan_count, replace=False)
        baseline_rows = rng.choice(baseline_count, size=plan_count, replace=False)
        attack_columns = rng.choice(attack_count, size=attacks_per_plan, replace=False)
        subsample = CrossedComparison(
            tested=comparison.tested[np.ix_(tested_rows, attack_columns)],
            baseline=comparison.baseline[np.ix_(baseline_rows, attack_columns)],
            tested_plan_ids=tuple(comparison.tested_plan_ids[index] for index in tested_rows),
            baseline_plan_ids=tuple(comparison.baseline_plan_ids[index] for index in baseline_rows),
            attack_seeds=tuple(comparison.attack_seeds[index] for index in attack_columns),
        )
        inner_seed = int(bootstrap_sequence.generate_state(1)[0])
        statistics = _crossed_statistics(subsample, analysis_configuration, inner_seed)
        half_widths.append(float(statistics.ci_half_width))
        informative = informative and bool(statistics.informative)

    guarded_half_width = float(
        np.quantile(np.asarray(half_widths, dtype=float), configuration.guard_quantile)
    )
    passes = bool(informative and guarded_half_width <= configuration.ci_half_width)
    return CandidateResult(plan_count, attacks_per_plan, guarded_half_width, passes)


def _aggregate_candidate(
    plan_count: int, attacks_per_plan: int, rows: list[dict]
) -> CandidateResult:
    """Collapse one candidate's comparison rows into one guarded result."""

    guarded_half_width = max(float(row["guarded_ci_half_width"]) for row in rows)
    passes = all(bool(row["passes"]) for row in rows)
    return CandidateResult(plan_count, attacks_per_plan, guarded_half_width, passes)


def _predicted_runtime_ms(
    plan_count: int,
    attacks_per_plan: int,
    runtime_inputs: RuntimeInputs,
) -> float:
    """Return the deterministic runtime selection heuristic in milliseconds."""

    selection = (
        runtime_inputs.tier_count
        * runtime_inputs.strategy_group_count
        * plan_count
        * runtime_inputs.median_plan_selection_ms
    )
    attacks = (
        runtime_inputs.tier_count
        * runtime_inputs.strategy_group_count
        * plan_count
        * attacks_per_plan
        * runtime_inputs.median_attack_trial_ms
    )
    return float(selection + attacks)


def _candidate_order(result: CandidateResult, runtime_inputs: RuntimeInputs) -> tuple:
    """Return the exact deterministic candidate ordering key."""

    return (
        _predicted_runtime_ms(result.plan_count, result.attacks_per_plan, runtime_inputs),
        -result.plan_count,
        result.attacks_per_plan,
    )


def _select_candidate(
    results: list[CandidateResult], runtime_inputs: RuntimeInputs
) -> CandidateResult | None:
    """Return the cheapest passing candidate or ``None``."""

    passing = [result for result in results if result.passes]
    if not passing:
        return None
    return min(passing, key=lambda result: _candidate_order(result, runtime_inputs))


def _recommendation(
    summaries: list[CandidateResult],
    runtime_inputs: RuntimeInputs,
    non_informative: tuple[str, ...],
) -> PilotRecommendation:
    """Return one common recommendation or an explicit insufficient result."""

    selected = _select_candidate(summaries, runtime_inputs)
    if selected is None:
        return PilotRecommendation(None, None, True, non_informative)
    return PilotRecommendation(selected.plan_count, selected.attacks_per_plan, False, non_informative)


def _per_trial_runtime(summary: dict) -> float:
    """Return one experiment runtime divided by its positive trial count."""

    trial_count = _integer(summary.get("trial_count"), "summary trial_count")
    if trial_count < 1:
        raise _error("summary trial_count must be positive")
    runtime_ms = _runtime(summary.get("runtime_ms"), "experiment runtime_ms")
    return runtime_ms / trial_count


def _runtime_inputs(study: LoadedStudy) -> RuntimeInputs:
    """Derive the measured runtime inputs used by the selection heuristic."""

    selection_samples = [
        _runtime(plan.get("runtime_ms"), "plan runtime_ms")
        for tier in study.tiers
        for plan in tier.loaded_export.plans
    ]
    attack_trial_samples = [
        _per_trial_runtime(summary)
        for tier in study.tiers
        for summary in tier.loaded_export.summary
    ]
    strategy_counts = [
        len(tier.loaded_export.manifest.get("strategy_runs") or [])
        for tier in study.tiers
    ]
    if not selection_samples:
        raise _error("pilot requires plan-selection runtime samples")
    if not attack_trial_samples:
        raise _error("pilot requires experiment runtime samples")
    if not strategy_counts or max(strategy_counts) < 1:
        raise _error("pilot requires declared strategy runs")
    return RuntimeInputs(
        median_plan_selection_ms=float(median(selection_samples)),
        median_attack_trial_ms=float(median(attack_trial_samples)),
        strategy_group_count=int(max(strategy_counts)),
        tier_count=len(study.tiers),
    )


def _release_loaded(exports: list[LoadedExport]) -> None:
    for export in exports:
        if export.temporary:
            shutil.rmtree(export.temporary, ignore_errors=True)


def _release_study(study: LoadedStudy) -> None:
    _release_loaded([tier.loaded_export for tier in study.tiers])


__all__ = [
    "StudyTier",
    "LoadedStudy",
    "PilotConfiguration",
    "CandidateResult",
    "PilotRecommendation",
    "RuntimeInputs",
    "PILOT_HEADERS",
    "PILOT_FILES",
    "PILOT_SELECTION_RULE",
    "MAX_PILOT_SUBSAMPLES",
    "load_study_bundle",
    "comparison_id",
    "analyze_study",
    "pilot_study",
]
