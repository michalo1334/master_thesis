"""Focused tests for the study bundle loader and family correction.

The synthetic values here are test-only. They are not production study values.
"""

import csv
import hashlib
import io
import json
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from starlette.testclient import TestClient

from network_defense_analysis import AnalysisError, service
from network_defense_analysis import archive as archive_module
from network_defense_analysis.study import (
    _apply_family_correction,
    _enforce_seed_schedule,
    _release_study,
    _stable_ids,
    _tier_context,
    _validate_result_tier_context,
    analyze_study,
    comparison_id,
    load_study_bundle,
)
from test_analysis import AnalysisTest

TIER_LABELS = ("tier-z", "tier-a", "tier-m")
ALTERNATIVES = ("alt-a", "alt-b")
BUDGETS = (1,)
PLAN_COUNT = 5
ATTACK_COUNT = 10
ATTACK_SEEDS = [9100 + index for index in range(ATTACK_COUNT)]

TRIAL_HEADERS = ("experiment_id", "plan_id", "trial_index", "seed", "blast_radius", "mission_impact")
CAPABILITY_HEADERS = ("experiment_id", "plan_id", "trial_index", "seed", "capability_id", "capability_name", "disrupted", "impact_weight")
FLOW_HEADERS = ("experiment_id", "plan_id", "capability_id", "capability_name", "source_segment_id", "target_service_id", "available")
HOST_HEADERS = ("experiment_id", "plan_id", "trial_index", "seed", "host_id", "host_name", "entry_host", "compromised")
SUMMARY_HEADERS = ("experiment_id", "plan_id", "trial_count", "expected_blast_radius", "median_blast_radius", "blast_radius_p95", "blast_radius_p99", "min_blast_radius", "max_blast_radius", "runtime_ms")


def write_csv(path, headers, rows):
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def zip_directory(source, target):
    with zipfile.ZipFile(target, "w") as archive:
        for path in sorted(candidate for candidate in source.rglob("*") if candidate.is_file()):
            archive.write(path, path.relative_to(source).as_posix())


def empty_zip_bytes():
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w"):
        pass
    return stream.getvalue()


def make_tier(label, alternatives, budgets, *, baseline="cvss", plan_count=PLAN_COUNT, attack_count=ATTACK_COUNT, seed=5000, zero_pairs=()):
    """Build one valid evaluation archive directory for study tests."""

    directory = Path(tempfile.mkdtemp())
    strategies = list(alternatives) + [baseline]
    zero = set(zero_pairs)
    seeds_by_run = {}
    plan_records = []
    selection = 100
    for strategy in strategies:
        for budget in budgets:
            seeds = []
            for _ in range(plan_count):
                selection += 1
                seeds.append(selection)
                plan_records.append((f"{strategy}-{budget}-{selection}", strategy, budget, selection))
            seeds_by_run[(strategy, budget)] = seeds
    runs = [
        {"model_variant": "full", "strategy": strategy, "budget": budget, "selection_seeds": seeds_by_run[(strategy, budget)]}
        for strategy in strategies
        for budget in budgets
    ]
    comparisons = [
        {
            "strategy": strategy,
            "model_variant": "full",
            "baseline": baseline,
            "baseline_model_variant": "full",
            "budget": budget,
            "outcome": "mission_impact",
        }
        for strategy in alternatives
        for budget in budgets
    ]
    manifest = {
        "schema_version": 3,
        "model_version": "study-model",
        "id": f"{label}-manifest",
        "model_variants": [{"id": "full", "objective": "mission_then_blast_radius", "require_pre_attack_feasibility": True}],
        "evaluation": {"trials": attack_count, "seed": seed},
        "strategy_runs": runs,
        "analysis": {
            "primary_comparisons": comparisons,
            "confidence_level": 0.9,
            "bootstrap_resamples": 100,
            "permutation_resamples": 100,
            "multiplicity_correction": "holm",
            "seed": seed,
        },
    }
    (directory / "manifest.resolved.json").write_text(json.dumps(manifest))
    (directory / "graph.json").write_text("{}\n")
    plans = [
        {
            "id": plan_id,
            "model_variant": "full",
            "strategy": strategy,
            "requested_budget": budget,
            "selection_seed": selection_seed,
            "objective": "mission_then_blast_radius",
            "require_pre_attack_feasibility": True,
            "status": "completed",
            "runtime_ms": 3,
        }
        for plan_id, strategy, budget, selection_seed in plan_records
    ]
    (directory / "plans.jsonl").write_text("\n".join(json.dumps(plan) for plan in plans) + "\n")
    strategy_index = {strategy: index for index, strategy in enumerate(strategies)}
    trial_rows = []
    for plan_id, strategy, budget, selection_seed in plan_records:
        for index, attack_seed in enumerate(ATTACK_SEEDS[:attack_count], 1):
            if (strategy, budget) in zero:
                value = 0.0
            else:
                value = float(strategy_index[strategy] * 10 + budget + (selection_seed % 5) * 0.5 + index * 0.25)
            trial_rows.append(
                {
                    "experiment_id": f"experiment-{plan_id}",
                    "plan_id": plan_id,
                    "trial_index": index,
                    "seed": attack_seed,
                    "blast_radius": value,
                    "mission_impact": value,
                }
            )
    write_csv(directory / "trials.csv", TRIAL_HEADERS, trial_rows)
    for name, headers in (
        ("capability_outcomes.csv", CAPABILITY_HEADERS),
        ("pre_attack_flow_statuses.csv", FLOW_HEADERS),
        ("host_compromises.csv", HOST_HEADERS),
        ("summary.csv", SUMMARY_HEADERS),
    ):
        (directory / name).write_text(",".join(headers) + "\n")
    write_csv(directory / "evaluator_runtime.csv", ("runtime_ms",), [{"runtime_ms": 12}])
    AnalysisTest.write_checksums(directory)
    return directory


def _tier_seed_sets(tiers):
    """Return the selection and evaluation seeds declared by tier manifests."""

    selection = set()
    evaluation = set()
    for _, tier_directory in tiers:
        manifest = json.loads((tier_directory / "manifest.resolved.json").read_text())
        evaluation.add(manifest["evaluation"]["seed"])
        for run in manifest["strategy_runs"]:
            selection.update(run["selection_seeds"])
    return sorted(selection), sorted(evaluation)


def build_bundle(tiers, *, strategies, budgets, baseline="cvss", study_id="study-1", tier_order=None, mutate_spec=None, mode="analyze"):
    """Assemble an outer study bundle from tier directories.

    ``mode`` decides which declared seed schedule matches the tier manifests.
    The other schedule stays disjoint so the loader accepts the bundle.
    """

    directory = Path(tempfile.mkdtemp())
    tier_dir = directory / "tiers"
    tier_dir.mkdir()
    entries = []
    for label, tier_directory in tiers:
        archive = tier_dir / f"{label}.zip"
        zip_directory(tier_directory, archive)
        entries.append(
            {
                "label": label,
                "archive": f"tiers/{label}.zip",
                "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            }
        )
    if tier_order is not None:
        entries = [entries[index] for index in tier_order]
    selection, evaluation = _tier_seed_sets(tiers)
    schedules = {
        "pilot_seed_schedule": {
            "selection": [seed + 1_000_000 for seed in selection],
            "evaluation": [seed + 1_000_000 for seed in evaluation],
        },
        "final_seed_schedule": {
            "selection": [seed + 2_000_000 for seed in selection],
            "evaluation": [seed + 2_000_000 for seed in evaluation],
        },
    }
    active = "final_seed_schedule" if mode == "analyze" else "pilot_seed_schedule"
    schedules[active] = {"selection": selection, "evaluation": evaluation}
    spec = {
        "study_id": study_id,
        "specification_version": 1,
        "tiers": entries,
        "expected_family": {
            "strategies": list(strategies),
            "baseline": baseline,
            "budgets": list(budgets),
            "outcome": "mission_impact",
        },
        "pilot": {"ci_half_width": 1.0, "plan_count_candidates": [5, 6], "attacks_per_plan_candidates": [10, 12]},
        "multiplicity_correction": "holm",
        "pilot_seed_schedule": schedules["pilot_seed_schedule"],
        "final_seed_schedule": schedules["final_seed_schedule"],
    }
    if mutate_spec is not None:
        mutate_spec(spec)
    (directory / "study.json").write_text(json.dumps(spec))
    names = ["study.json"] + [entry["archive"] for entry in spec["tiers"]]
    lines = [f"{name}  {hashlib.sha256((directory / name).read_bytes()).hexdigest()}" for name in names]
    (directory / "checksums.txt").write_text("\n".join(lines) + "\n")
    bundle = Path(tempfile.mkdtemp()) / "study.zip"
    zip_directory(directory, bundle)
    return bundle, directory


class StudyBundleTest(unittest.TestCase):
    def setUp(self):
        self.paths = []

    def tearDown(self):
        for path in self.paths:
            if isinstance(path, Path) and path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
            elif isinstance(path, Path):
                path.unlink(missing_ok=True)

    def remember(self, path):
        self.paths.append(Path(path))
        return path

    def sample_tiers(self, *, alternatives=ALTERNATIVES, budgets=BUDGETS, zero_pairs=(), seed=5000):
        tiers = []
        for label in TIER_LABELS:
            directory = self.remember(make_tier(label, list(alternatives), list(budgets), seed=seed, zero_pairs=zero_pairs))
            tiers.append((label, directory))
        return tiers

    def build_sample(self, *, tier_order=None, alternatives=ALTERNATIVES, budgets=BUDGETS, zero_pairs=(), mutate_spec=None, tiers=None, mode="analyze"):
        tiers = self.sample_tiers(alternatives=alternatives, budgets=budgets, zero_pairs=zero_pairs) if tiers is None else tiers
        bundle, directory = build_bundle(
            tiers,
            strategies=list(alternatives),
            budgets=list(budgets),
            tier_order=tier_order,
            mutate_spec=mutate_spec,
            mode=mode,
        )
        self.remember(bundle.parent)
        self.remember(directory)
        return bundle, directory, tiers

    def load_and_release(self, bundle):
        study = load_study_bundle(bundle)
        self.addCleanup(_release_study, study)
        return study

    def read_primary(self, output):
        with zipfile.ZipFile(output) as result:
            self.assertEqual(
                set(result.namelist()),
                {
                    "checksums.txt",
                    "primary_results.csv",
                    "primary_results.json",
                    "study_metadata.json",
                    "tier_context.json",
                },
            )
            payload = result.read("primary_results.csv").decode()
            metadata = json.loads(result.read("study_metadata.json").decode())
        return list(csv.DictReader(io.StringIO(payload))), metadata

    # -- valid path -----------------------------------------------------

    def test_valid_study_loads_with_family_metadata(self):
        bundle, _, _ = self.build_sample()
        study = self.load_and_release(bundle)
        self.assertEqual(study.study_id, "study-1")
        self.assertEqual(study.specification_version, 1)
        self.assertEqual(len(study.tiers), 3)
        self.assertEqual(study.configuration["family_size"], 6)
        self.assertEqual(study.configuration["multiplicity_correction"], "holm")
        self.assertEqual([tier.label for tier in study.tiers], list(TIER_LABELS))
        for index, label in enumerate(TIER_LABELS):
            self.assertEqual(study.tiers[index].label, label)
            self.assertEqual(study.tiers[index].archive_path, f"tiers/{label}.zip")
            self.assertEqual(len(study.tiers[index].archive_sha256), 64)

    def test_tier_context_rejects_missing_duplicate_and_mismatched_archives(self):
        bundle, _, _ = self.build_sample()
        study = self.load_and_release(bundle)
        context = _tier_context(study)

        self.assertEqual(len(context), len(TIER_LABELS))
        _validate_result_tier_context(context, study)

        with self.assertRaises(AnalysisError):
            _validate_result_tier_context([], study)
        with self.assertRaises(AnalysisError):
            _validate_result_tier_context([context[0], context[0]], study)
        with self.assertRaises(AnalysisError):
            _validate_result_tier_context(
                [{**context[0], "archive_sha256": "0" * 64}], study
            )

    def test_valid_study_analyzes_with_one_family(self):
        bundle, _, _ = self.build_sample()
        output = self.remember(Path(tempfile.mkdtemp()) / "study-analysis.zip")
        analyze_study(bundle, output)
        rows, metadata = self.read_primary(output)
        self.assertEqual(len(rows), 6)
        self.assertEqual(metadata["family_scope"], "study")
        self.assertEqual(metadata["family_size"], 6)
        self.assertEqual(metadata["multiplicity_correction"], "holm")
        self.assertEqual(len(metadata["tier_context"]), 3)
        self.assertEqual(
            [entry["archive_sha256"] for entry in metadata["tier_context"]],
            [tier.archive_sha256 for tier in self.load_and_release(bundle).tiers],
        )
        ids = [row["comparison_id"] for row in rows]
        self.assertEqual(ids, sorted(ids))
        self.assertEqual(len(set(ids)), len(ids))

    def test_adjusted_values_match_holm_over_id_order(self):
        bundle, _, _ = self.build_sample()
        output = self.remember(Path(tempfile.mkdtemp()) / "study-analysis.zip")
        analyze_study(bundle, output)
        rows, _ = self.read_primary(output)
        expected = dict(zip((row["comparison_id"] for row in rows), _holm_of([float(row["p_raw"]) for row in rows])))
        for row in rows:
            self.assertAlmostEqual(float(row["p_adjusted"]), expected[row["comparison_id"]], places=12)

    # -- tier membership -------------------------------------------------

    def test_missing_tier_rejected(self):
        _, directory, _ = self.build_sample()
        missing_bundle = Path(tempfile.mkdtemp()) / "missing.zip"
        self.remember(missing_bundle.parent)
        (directory / "tiers" / "tier-a.zip").unlink()
        zip_directory(directory, missing_bundle)
        with self.assertRaises(AnalysisError):
            load_study_bundle(missing_bundle)

    def test_unexpected_tier_rejected(self):
        _, directory, _ = self.build_sample()
        extra_bundle = Path(tempfile.mkdtemp()) / "extra.zip"
        self.remember(extra_bundle.parent)
        (directory / "tiers" / "extra.zip").write_bytes(b"extra")
        zip_directory(directory, extra_bundle)
        with self.assertRaises(AnalysisError):
            load_study_bundle(extra_bundle)

    def test_duplicate_tier_label_rejected(self):
        def mutate(spec):
            spec["tiers"][1]["label"] = spec["tiers"][0]["label"]

        bundle, _, _ = self.build_sample(mutate_spec=mutate)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    def test_duplicate_tier_path_rejected(self):
        def mutate(spec):
            spec["tiers"][1]["archive"] = spec["tiers"][0]["archive"]

        bundle, _, _ = self.build_sample(mutate_spec=mutate)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    # -- family membership ----------------------------------------------

    def test_missing_primary_comparison_rejected(self):
        tiers = self.sample_tiers()
        manifest_path = tiers[0][1] / "manifest.resolved.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["analysis"]["primary_comparisons"].pop()
        manifest_path.write_text(json.dumps(manifest))
        AnalysisTest.write_checksums(tiers[0][1])
        bundle, _, _ = self.build_sample(tiers=tiers)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    def test_duplicate_primary_comparison_rejected(self):
        tiers = self.sample_tiers()
        manifest_path = tiers[0][1] / "manifest.resolved.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["analysis"]["primary_comparisons"].append(dict(manifest["analysis"]["primary_comparisons"][0]))
        manifest_path.write_text(json.dumps(manifest))
        AnalysisTest.write_checksums(tiers[0][1])
        bundle, _, _ = self.build_sample(tiers=tiers)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    def test_different_matrix_in_one_tier_rejected(self):
        tiers = self.sample_tiers()
        manifest_path = tiers[0][1] / "manifest.resolved.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["analysis"]["primary_comparisons"][0]["budget"] = 99
        manifest_path.write_text(json.dumps(manifest))
        AnalysisTest.write_checksums(tiers[0][1])
        bundle, _, _ = self.build_sample(tiers=tiers)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    def test_incompatible_analysis_settings_rejected(self):
        tiers = self.sample_tiers()
        manifest_path = tiers[0][1] / "manifest.resolved.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["analysis"]["confidence_level"] = 0.8
        manifest_path.write_text(json.dumps(manifest))
        AnalysisTest.write_checksums(tiers[0][1])
        bundle, _, _ = self.build_sample(tiers=tiers)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    # -- checksums -------------------------------------------------------

    def test_outer_checksum_failure_rejected(self):
        _, directory, _ = self.build_sample()
        tampered_bundle = Path(tempfile.mkdtemp()) / "tampered.zip"
        self.remember(tampered_bundle.parent)
        archive = directory / "tiers" / "tier-a.zip"
        archive.write_bytes(archive.read_bytes() + b"0")
        zip_directory(directory, tampered_bundle)
        with self.assertRaises(AnalysisError):
            load_study_bundle(tampered_bundle)

    def test_declared_inner_hash_mismatch_rejected(self):
        def mutate(spec):
            spec["tiers"][0]["sha256"] = "0" * 64

        bundle, _, _ = self.build_sample(mutate_spec=mutate)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    def test_inner_checksum_failure_rejected(self):
        tiers = self.sample_tiers()
        trials = tiers[0][1] / "trials.csv"
        trials.write_text(trials.read_text() + "extra\n")
        bundle, _, _ = self.build_sample(tiers=tiers)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    # -- safety limits ---------------------------------------------------

    def test_path_traversal_rejected(self):
        bundle = Path(tempfile.mkdtemp()) / "escape.zip"
        self.remember(bundle.parent)
        with zipfile.ZipFile(bundle, "w") as target:
            target.writestr("../escape", "bad")
            target.writestr("study.json", "{}")
            target.writestr("checksums.txt", "")
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    def test_member_limit_rejected(self):
        bundle, _, _ = self.build_sample()
        with patch.object(archive_module, "MAX_ZIP_MEMBERS", 1):
            with self.assertRaises(AnalysisError):
                load_study_bundle(bundle)

    def test_extracted_size_limit_rejected(self):
        bundle, _, _ = self.build_sample()
        with patch.object(archive_module, "MAX_ZIP_BYTES", 1):
            with self.assertRaises(AnalysisError):
                load_study_bundle(bundle)

    def test_seed_schedule_overlap_rejected(self):
        def mutate(spec):
            spec["final_seed_schedule"]["selection"] = list(
                spec["pilot_seed_schedule"]["selection"]
            )

        bundle, _, _ = self.build_sample(mutate_spec=mutate)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    # -- seed schedule enforcement --------------------------------------

    def test_analyze_requires_one_model_variant(self):
        tiers = self.sample_tiers()
        manifest_path = tiers[0][1] / "manifest.resolved.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["model_variants"].append(
            {"id": "extra", "objective": "x", "require_pre_attack_feasibility": False}
        )
        manifest_path.write_text(json.dumps(manifest))
        AnalysisTest.write_checksums(tiers[0][1])
        bundle, _, _ = self.build_sample(tiers=tiers)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    def test_analyze_rejects_evaluation_seed_set_mismatch(self):
        def mutate(spec):
            spec["final_seed_schedule"]["evaluation"] = [7_000_000]

        bundle, _, _ = self.build_sample(mutate_spec=mutate)
        output = self.remember(Path(tempfile.mkdtemp()) / "study-analysis.zip")
        with self.assertRaises(AnalysisError):
            analyze_study(bundle, output)

    def test_analyze_rejects_strategy_run_selection_seed_outside_schedule(self):
        def mutate(spec):
            spec["final_seed_schedule"]["selection"] = spec["final_seed_schedule"][
                "selection"
            ][:-1]

        bundle, _, _ = self.build_sample(mutate_spec=mutate)
        output = self.remember(Path(tempfile.mkdtemp()) / "study-analysis.zip")
        with self.assertRaises(AnalysisError):
            analyze_study(bundle, output)

    def test_analyze_rejects_plan_selection_seed_outside_schedule(self):
        tiers = self.sample_tiers()
        plans_path = tiers[0][1] / "plans.jsonl"
        plans = [json.loads(line) for line in plans_path.read_text().splitlines()]
        plans[0]["selection_seed"] = 999_999_999
        plans_path.write_text("\n".join(json.dumps(plan) for plan in plans) + "\n")
        AnalysisTest.write_checksums(tiers[0][1])
        bundle, _, _ = self.build_sample(tiers=tiers)
        output = self.remember(Path(tempfile.mkdtemp()) / "study-analysis.zip")
        with self.assertRaises(AnalysisError):
            analyze_study(bundle, output)

    def test_pilot_bundle_satisfies_only_the_pilot_schedule(self):
        bundle, _, _ = self.build_sample(mode="pilot")
        study = self.load_and_release(bundle)

        _enforce_seed_schedule(study, "pilot")
        with self.assertRaises(AnalysisError):
            _enforce_seed_schedule(study, "final")

    def test_final_bundle_satisfies_only_the_final_schedule(self):
        bundle, _, _ = self.build_sample(mode="analyze")
        study = self.load_and_release(bundle)

        _enforce_seed_schedule(study, "final")
        with self.assertRaises(AnalysisError):
            _enforce_seed_schedule(study, "pilot")

    def test_analyze_allows_declared_selection_superset(self):
        def mutate(spec):
            spec["final_seed_schedule"]["selection"] = sorted(
                spec["final_seed_schedule"]["selection"] + [9_000_000]
            )

        bundle, _, _ = self.build_sample(mutate_spec=mutate)
        output = self.remember(Path(tempfile.mkdtemp()) / "study-analysis.zip")
        analyze_study(bundle, output)
        rows, _ = self.read_primary(output)
        self.assertEqual(len(rows), 6)

    def test_unsorted_pilot_candidates_rejected_at_load(self):
        def mutate(spec):
            spec["pilot"]["plan_count_candidates"] = [6, 5]

        bundle, _, _ = self.build_sample(mutate_spec=mutate)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    def test_duplicate_pilot_candidates_rejected_at_load(self):
        def mutate(spec):
            spec["pilot"]["attacks_per_plan_candidates"] = [10, 10]

        bundle, _, _ = self.build_sample(mutate_spec=mutate)
        with self.assertRaises(AnalysisError):
            load_study_bundle(bundle)

    # -- stable identity and ordering -----------------------------------

    def test_comparison_id_uses_declared_field_order(self):
        comparison = {
            "model_variant": "full",
            "strategy": "alt-a",
            "baseline_model_variant": "full",
            "baseline": "cvss",
            "budget": 2,
            "outcome": "mission_impact",
        }
        self.assertEqual(comparison_id("tier-a", comparison), "tier-a|full|alt-a|full|cvss|2|mission_impact")

    def test_duplicate_stable_ids_rejected(self):
        comparison = {
            "model_variant": "full",
            "strategy": "alt-a",
            "baseline_model_variant": "full",
            "baseline": "cvss",
            "budget": 1,
            "outcome": "mission_impact",
        }
        with self.assertRaises(AnalysisError):
            _stable_ids([("tier-a", comparison), ("tier-a", dict(comparison))])

    def test_holm_mapping_uses_stable_id_not_row_position(self):
        rows = [
            {"comparison_id": "tier-z|full|alt-a|full|cvss|1|mission_impact", "p_raw": 0.04},
            {"comparison_id": "tier-a|full|alt-a|full|cvss|1|mission_impact", "p_raw": 0.01},
            {"comparison_id": "tier-m|full|alt-a|full|cvss|1|mission_impact", "p_raw": 0.03},
        ]
        _apply_family_correction(rows, "holm")
        values = {row["comparison_id"].split("|", 1)[0]: row["p_adjusted"] for row in rows}
        self.assertEqual(values["tier-a"], 0.03)
        self.assertEqual(values["tier-m"], 0.06)
        self.assertEqual(values["tier-z"], 0.06)
        with self.assertRaises(AnalysisError):
            _apply_family_correction(rows, "bonferroni")

    def test_primary_rows_are_ordered_by_stable_id(self):
        bundle, _, _ = self.build_sample(tier_order=[2, 1, 0])
        output = self.remember(Path(tempfile.mkdtemp()) / "study-analysis.zip")
        analyze_study(bundle, output)
        rows, _ = self.read_primary(output)
        ids = [row["comparison_id"] for row in rows]
        self.assertEqual(ids, sorted(ids))
        self.assertTrue(ids[0].startswith("tier-a|"))
        self.assertEqual({row["tier"] for row in rows}, set(TIER_LABELS))

    # -- non-informative rows -------------------------------------------

    def test_non_informative_row_stays_in_family(self):
        bundle, _, _ = self.build_sample(zero_pairs={("alt-a", 1), ("cvss", 1)})
        output = self.remember(Path(tempfile.mkdtemp()) / "study-analysis.zip")
        analyze_study(bundle, output)
        rows, metadata = self.read_primary(output)
        self.assertEqual(len(rows), 6)
        self.assertEqual(metadata["family_size"], 6)
        zero_rows = [row for row in rows if row["strategy"] == "alt-a"]
        self.assertEqual(len(zero_rows), 3)
        for row in zero_rows:
            self.assertEqual(row["informative"], "False")
            self.assertEqual(float(row["p_raw"]), 1.0)
        self.assertEqual(len({row["comparison_id"] for row in rows}), 6)


def _holm_of(values):
    order = sorted(range(len(values)), key=values.__getitem__)
    adjusted = [0.0] * len(values)
    previous = 0.0
    for rank, index in enumerate(order):
        previous = max(previous, (len(values) - rank) * values[index])
        adjusted[index] = min(1.0, previous)
    return adjusted


class StudyServiceTest(unittest.TestCase):
    def setUp(self):
        self.app = service.create_app()
        self.client = TestClient(self.app)

    def test_study_route_returns_zip(self):
        def fake(source, output):
            with zipfile.ZipFile(output, "w") as result:
                result.writestr("study_metadata.json", "{}")

        with patch.object(service, "analyze_study", side_effect=fake):
            response = self.client.post(
                "/v1/study/analyze",
                content=empty_zip_bytes(),
                headers={"content-type": "application/zip"},
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-type"], "application/zip")
        with zipfile.ZipFile(io.BytesIO(response.content)) as result:
            self.assertIn("study_metadata.json", result.namelist())

    def test_study_route_rejects_bad_content_type(self):
        self.assertEqual(
            self.client.post("/v1/study/analyze", content=b"x", headers={"content-type": "text/plain"}).status_code,
            415,
        )

    def test_existing_single_archive_route_unchanged(self):
        with patch.object(service, "analyze", side_effect=lambda source, output: (output / "result.txt").write_text("analyze")):
            response = self.client.post(
                "/v1/analyze",
                content=empty_zip_bytes(),
                headers={"content-type": "application/zip"},
            )
        self.assertEqual(response.status_code, 200)
        with zipfile.ZipFile(io.BytesIO(response.content)) as result:
            self.assertIn("result.txt", result.namelist())


class StudyCliTest(unittest.TestCase):
    def setUp(self):
        self.paths = []

    def tearDown(self):
        for path in self.paths:
            if path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
            else:
                path.unlink(missing_ok=True)

    def remember(self, path):
        self.paths.append(Path(path))
        return path

    def test_cli_study_analyze_round_trip(self):
        tiers = []
        for label in TIER_LABELS:
            directory = self.remember(make_tier(label, list(ALTERNATIVES), list(BUDGETS)))
            tiers.append((label, directory))
        bundle, directory = build_bundle(tiers, strategies=list(ALTERNATIVES), budgets=list(BUDGETS))
        self.remember(bundle.parent)
        self.remember(directory)
        output = self.remember(Path(tempfile.mkdtemp()) / "study-analysis.zip")
        completed = subprocess.run(
            ["uv", "run", "network-defense-analysis", "study-analyze", str(bundle), "--output", str(output)],
            cwd=Path(__file__).parents[1],
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        with zipfile.ZipFile(output) as result:
            self.assertIn("primary_results.csv", result.namelist())


if __name__ == "__main__":
    unittest.main()
