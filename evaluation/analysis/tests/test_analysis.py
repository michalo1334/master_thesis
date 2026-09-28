import csv
import hashlib
import json
import math
import shutil
import stat
import subprocess
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path

import numpy as np

import network_defense_analysis.statistics as statistics_module
from network_defense_analysis import AnalysisError, analyze
from network_defense_analysis.archive import _safe_extract
from network_defense_analysis.contracts import _dependency_versions, _package_version
from network_defense_analysis.report import _plan_variation_values
from network_defense_analysis.statistics import (
    CrossedComparison,
    DegenerateContrastWarning,
    _bootstrap_contrast,
    _child_seeds,
    _comparison_stream_seed,
    _crossed_comparison,
    _crossed_statistics,
    _finite_sample_correction,
    _holm,
)


class AnalysisTest(unittest.TestCase):
    @staticmethod
    def make_fixture(*, two_comparisons=False, cross_model=False, cross_scenario="feasibility_only"):
        directory = Path(tempfile.mkdtemp())
        variants = [
            {"id": "full", "objective": "mission_then_blast_radius", "require_pre_attack_feasibility": True},
        ]
        runs = [
            {"model_variant": "full", "strategy": "unusual-tested", "budget": 8, "selection_seeds": [101, 102, 103, 104, 105]},
            {"model_variant": "full", "strategy": "ordinary-baseline", "budget": 8, "selection_seeds": [202, 203, 204, 205, 206]},
        ]
        comparisons = [
            {"strategy": "unusual-tested", "model_variant": "full", "baseline": "ordinary-baseline", "baseline_model_variant": "full", "budget": 8, "outcome": "blast_radius"}
        ]
        if two_comparisons:
            runs.extend([
                {"model_variant": "full", "strategy": "second-tested", "budget": 8, "selection_seeds": [303, 304, 305, 306, 307]},
                {"model_variant": "full", "strategy": "second-baseline", "budget": 8, "selection_seeds": [404, 405, 406, 407, 408]},
            ])
            comparisons.append(
                {"strategy": "second-tested", "model_variant": "full", "baseline": "second-baseline", "baseline_model_variant": "full", "budget": 8, "outcome": "blast_radius"}
            )
        if cross_model:
            cross_variants = {
                "feasibility_only": ("full_unconstrained", "mission_then_blast_radius", False),
                "objective_only": ("blast_only", "blast_radius_only", True),
                "confounded": ("blast_only_unconstrained", "blast_radius_only", False),
            }
            cross_id, cross_objective, cross_feasibility = cross_variants[cross_scenario]
            variants.append({"id": cross_id, "objective": cross_objective, "require_pre_attack_feasibility": cross_feasibility})
            runs.extend([
                {"model_variant": "full", "strategy": "simulation_informed", "budget": 8, "selection_seeds": [101, 102, 103, 104, 105]},
                {"model_variant": cross_id, "strategy": "simulation_informed", "budget": 8, "selection_seeds": [101, 102, 103, 104, 105]},
            ])
            comparisons.append(
                {"strategy": "simulation_informed", "model_variant": cross_id, "baseline": "simulation_informed", "baseline_model_variant": "full", "budget": 8, "outcome": "blast_radius"}
            )
        manifest = {
            "schema_version": 3,
            "model_version": "test-model",
            "id": "test-manifest",
            "model_variants": variants,
            "evaluation": {"trials": 10},
            "strategy_runs": runs,
            "analysis": {
                "primary_comparisons": comparisons,
                "confidence_level": 0.9,
                "bootstrap_resamples": 200,
                "permutation_resamples": 200,
                "multiplicity_correction": "holm" if two_comparisons else "none",
                "seed": 700,
            },
        }
        (directory / "manifest.resolved.json").write_text(json.dumps(manifest))
        (directory / "graph.json").write_text("{}\n")
        declarations = {variant["id"]: variant for variant in variants}
        plans = []
        for run in runs:
            declaration = declarations[run["model_variant"]]
            for selection_seed in run["selection_seeds"]:
                plans.append(
                    {
                        "id": f"{run['model_variant']}-{run['strategy']}-{selection_seed}",
                        "model_variant": run["model_variant"],
                        "strategy": run["strategy"],
                        "requested_budget": run["budget"],
                        "selection_seed": selection_seed,
                        "objective": declaration["objective"],
                        "require_pre_attack_feasibility": declaration["require_pre_attack_feasibility"],
                        "status": "completed",
                        "runtime_ms": 3,
                    }
                )
        (directory / "plans.jsonl").write_text("\n".join(json.dumps(plan) for plan in plans) + "\n")
        values = {
            ("full", "unusual-tested"): [3.0, 4.0, 3.0, 4.0, 3.0, 4.0, 3.0, 4.0, 3.0, 4.0],
            ("full", "ordinary-baseline"): [6.0, 8.0, 6.0, 8.0, 6.0, 8.0, 6.0, 8.0, 6.0, 8.0],
            ("full", "second-tested"): [2.0, 4.0, 2.0, 4.0, 2.0, 4.0, 2.0, 4.0, 2.0, 4.0],
            ("full", "second-baseline"): [3.0, 7.0, 3.0, 7.0, 3.0, 7.0, 3.0, 7.0, 3.0, 7.0],
        }
        if cross_model:
            values[("full", "simulation_informed")] = [3.0, 4.0, 3.0, 4.0, 3.0, 4.0, 3.0, 4.0, 3.0, 4.0]
            values[(cross_id, "simulation_informed")] = [5.0, 6.0, 5.0, 6.0, 5.0, 6.0, 5.0, 6.0, 5.0, 6.0]
        trial_rows = []
        capability_rows = []
        flow_rows = []
        host_rows = []
        for plan in plans:
            plan_values = values[(plan["model_variant"], plan["strategy"])]
            plan_id = plan["id"]
            for index, value in enumerate(plan_values, 1):
                trial_rows.append({
                    "experiment_id": f"experiment-{plan_id}",
                    "plan_id": plan_id,
                    "trial_index": index,
                    "seed": 900 + index,
                    "blast_radius": value,
                    "mission_impact": value / 2,
                })
                capability_rows.append({
                    "experiment_id": f"experiment-{plan_id}",
                    "plan_id": plan_id,
                    "trial_index": index,
                    "seed": 900 + index,
                    "capability_id": "cap-alpha",
                    "capability_name": "Capability alpha",
                    "disrupted": "true" if value >= 5 else "false",
                    "impact_weight": value / 2,
                })
                host_rows.extend([
                    {"experiment_id": f"experiment-{plan_id}", "plan_id": plan_id, "trial_index": index, "seed": 900 + index, "host_id": "host-entry", "host_name": "Entry host", "entry_host": "true", "compromised": "true"},
                    {"experiment_id": f"experiment-{plan_id}", "plan_id": plan_id, "trial_index": index, "seed": 900 + index, "host_id": "host-beta", "host_name": "Host beta", "entry_host": "false", "compromised": "true" if value >= 5 else "false"},
                ])
            flow_rows.append({"experiment_id": f"experiment-{plan_id}", "plan_id": plan_id, "capability_id": "cap-alpha", "capability_name": "Capability alpha", "source_segment_id": "segment-alpha", "target_service_id": "service-alpha", "available": "true"})
        for index in range(1, 11):
            trial_rows.append({"experiment_id": "experiment-baseline", "plan_id": "", "trial_index": index, "seed": 900 + index, "blast_radius": 99, "mission_impact": 99})
            host_rows.extend([
                {"experiment_id": "experiment-baseline", "plan_id": "", "trial_index": index, "seed": 900 + index, "host_id": "host-entry", "host_name": "Entry host", "entry_host": "true", "compromised": "true"},
                {"experiment_id": "experiment-baseline", "plan_id": "", "trial_index": index, "seed": 900 + index, "host_id": "host-beta", "host_name": "Host beta", "entry_host": "false", "compromised": "true"},
            ])
        flow_rows.append({"experiment_id": "experiment-baseline", "plan_id": "", "capability_id": "cap-alpha", "capability_name": "Capability alpha", "source_segment_id": "segment-alpha", "target_service_id": "service-alpha", "available": "false"})
        AnalysisTest.write_csv(directory / "trials.csv", trial_rows)
        AnalysisTest.write_csv(directory / "capability_outcomes.csv", capability_rows)
        AnalysisTest.write_csv(directory / "pre_attack_flow_statuses.csv", flow_rows)
        AnalysisTest.write_csv(directory / "host_compromises.csv", host_rows)
        AnalysisTest.write_csv(
            directory / "summary.csv",
            [
                {
                    "experiment_id": f"experiment-{plan['id']}",
                    "plan_id": plan["id"],
                    "trial_count": 10,
                    "expected_blast_radius": 4,
                    "median_blast_radius": 4,
                    "blast_radius_p95": 4,
                    "blast_radius_p99": 4,
                    "min_blast_radius": 3,
                    "max_blast_radius": 5,
                    "runtime_ms": 4,
                }
                for plan in plans
            ] + [{
                "experiment_id": "experiment-baseline",
                "plan_id": "",
                "trial_count": 10,
                "expected_blast_radius": 99,
                "median_blast_radius": 99,
                "blast_radius_p95": 99,
                "blast_radius_p99": 99,
                "min_blast_radius": 99,
                "max_blast_radius": 99,
                "runtime_ms": 4,
            }],
        )
        AnalysisTest.write_csv(directory / "evaluator_runtime.csv", [{"runtime_ms": 12}])
        AnalysisTest.write_checksums(directory)
        return directory

    @staticmethod
    def write_csv(path, rows):
        fields = list(rows[0])
        with path.open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)

    @staticmethod
    def write_checksums(directory):
        names = [
            "manifest.resolved.json",
            "graph.json",
            "plans.jsonl",
            "trials.csv",
            "capability_outcomes.csv",
            "pre_attack_flow_statuses.csv",
            "host_compromises.csv",
            "summary.csv",
            "evaluator_runtime.csv",
        ]
        lines = [f"{name}  {hashlib.sha256((directory / name).read_bytes()).hexdigest()}" for name in names]
        (directory / "checksums.txt").write_text("\n".join(lines) + "\n")

    def tearDown(self):
        for path in getattr(self, "temporary_paths", []):
            if path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
            else:
                path.unlink(missing_ok=True)

    def remember(self, path):
        self.temporary_paths = getattr(self, "temporary_paths", []) + [path]
        return path

    def test_arbitrary_names_and_paired_sign(self):
        directory = self.remember(self.make_fixture())
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "primary_results.csv").open(newline="") as stream:
            result = next(csv.DictReader(stream))
        self.assertAlmostEqual(float(result["paired_mean_difference"]), -3.5)

    def test_deterministic_machine_outputs(self):
        directory = self.remember(self.make_fixture())
        first = self.remember(Path(tempfile.mkdtemp()))
        second = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, first)
        analyze(directory, second)
        for name in ("primary_results.csv", "secondary_results.csv", "capability_results.csv", "cdf.csv"):
            self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())
        first_metadata = json.loads((first / "analysis.json").read_text())
        second_metadata = json.loads((second / "analysis.json").read_text())
        first_metadata.pop("analysis_runtime_seconds")
        second_metadata.pop("analysis_runtime_seconds")
        self.assertEqual(first_metadata, second_metadata)

    def test_holm_adjustment(self):
        directory = self.remember(self.make_fixture(two_comparisons=True))
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "primary_results.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(float(row["p_adjusted"]) >= float(row["p_raw"]) for row in rows))

    def test_exact_holm_values(self):
        self.assertEqual(_holm([0.01, 0.04, 0.03]), [0.03, 0.06, 0.06])

    def test_multiple_selection_seeds_are_aggregated(self):
        directory = self.remember(self.make_fixture())
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "plan_variation.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 10)
        with (output / "primary_results.csv").open(newline="") as stream:
            self.assertAlmostEqual(float(next(csv.DictReader(stream))["paired_mean_difference"]), -3.5)

    def test_primary_rows_preserve_old_fields_and_add_crossed_fields(self):
        directory = self.remember(self.make_fixture())
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "primary_results.csv").open(newline="") as stream:
            reader = csv.DictReader(stream)
            headers = list(reader.fieldnames)
            row = next(reader)
        for field in (
            "comparison", "strategy", "model_variant", "baseline", "baseline_model_variant",
            "budget", "outcome", "paired_mean_difference", "ci_lower", "ci_upper",
            "ci_half_width", "d_z", "p_raw", "p_adjusted",
        ):
            self.assertIn(field, headers)
        for field in ("informative", "tested_plan_count", "baseline_plan_count", "attacks_per_plan"):
            self.assertIn(field, headers)
        self.assertEqual(row["d_z"], "")
        self.assertEqual(row["informative"], "True")
        self.assertEqual(row["tested_plan_count"], "5")
        self.assertEqual(row["baseline_plan_count"], "5")
        self.assertEqual(row["attacks_per_plan"], "10")
        analysis = json.loads((output / "analysis.json").read_text())
        primary_row = analysis["primary_results"][0]
        self.assertIsNone(primary_row["d_z"])
        self.assertIs(primary_row["informative"], True)
        self.assertEqual(primary_row["tested_plan_count"], 5)
        self.assertEqual(primary_row["baseline_plan_count"], 5)
        self.assertEqual(primary_row["attacks_per_plan"], 10)

    def test_secondary_results_keep_their_columns(self):
        directory = self.remember(self.make_fixture())
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "secondary_results.csv").open(newline="") as stream:
            reader = csv.DictReader(stream)
            headers = list(reader.fieldnames)
            row = next(reader)
        self.assertEqual(
            headers,
            [
                "comparison", "strategy", "model_variant", "baseline", "baseline_model_variant",
                "budget", "outcome", "mean_difference", "ci_lower", "ci_upper", "ci_half_width",
            ],
        )
        self.assertNotIn("informative", headers)
        self.assertEqual(row["outcome"], "mission_impact")

    def test_metadata_declares_crossed_uncertainty(self):
        directory = self.remember(self.make_fixture())
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        for name in ("metadata.json", "analysis.json"):
            metadata = json.loads((output / name).read_text())
            self.assertIs(metadata["simulator_only_uncertainty"], False)
            self.assertEqual(metadata["uncertainty_sources"], ["plan_selection", "attack_outcome"])
            self.assertEqual(
                metadata["estimand_note"],
                "The interval includes independent plan-row and shared attack-column resampling.",
            )

    def test_missing_pair_rejected(self):
        directory = self.remember(self.make_fixture())
        lines = (directory / "trials.csv").read_text().splitlines()
        (directory / "trials.csv").write_text("\n".join(lines[:-2]) + "\n")
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_balanced_truncation_rejected(self):
        directory = self.remember(self.make_fixture())
        with (directory / "trials.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        rows = [row for row in rows if not (row["plan_id"].startswith(("full-unusual-tested", "full-ordinary-baseline")) and row["trial_index"] == "2")]
        self.write_csv(directory / "trials.csv", rows)
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_omitted_checksum_line_rejected(self):
        directory = self.remember(self.make_fixture())
        lines = (directory / "checksums.txt").read_text().splitlines()
        (directory / "checksums.txt").write_text("\n".join(lines[:-1]) + "\n")
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_schema_mismatch_rejected(self):
        directory = self.remember(self.make_fixture())
        manifest = json.loads((directory / "manifest.resolved.json").read_text())
        for version in (1, 2):
            manifest["schema_version"] = version
            (directory / "manifest.resolved.json").write_text(json.dumps(manifest))
            self.write_checksums(directory)
            with self.assertRaises(AnalysisError):
                analyze(directory, directory / "out")

        (directory / "manifest.resolved.json").write_text("[]")
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_missing_model_variants_rejected(self):
        directory = self.remember(self.make_fixture())
        manifest = json.loads((directory / "manifest.resolved.json").read_text())
        manifest["model_variants"] = []
        (directory / "manifest.resolved.json").write_text(json.dumps(manifest))
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_malformed_plan_identity_rejected(self):
        mutations = [
            lambda plan: plan.pop("model_variant"),
            lambda plan: plan.pop("strategy"),
            lambda plan: plan.pop("selection_seed"),
        ]
        for mutation in mutations:
            directory = self.remember(self.make_fixture())
            plans = [json.loads(line) for line in (directory / "plans.jsonl").read_text().splitlines()]
            mutation(plans[0])
            (directory / "plans.jsonl").write_text("\n".join(json.dumps(plan) for plan in plans) + "\n")
            self.write_checksums(directory)
            with self.assertRaises(AnalysisError):
                analyze(directory, directory / "out")

    def test_cross_model_comparison_keeps_variants_separate(self):
        directory = self.remember(self.make_fixture(cross_model=True))
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "primary_results.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 2)
        self.assertEqual(
            [(row["model_variant"], row["baseline_model_variant"]) for row in rows],
            [("full", "full"), ("full_unconstrained", "full")],
        )
        self.assertAlmostEqual(float(rows[1]["paired_mean_difference"]), 2.0)
        with (output / "cdf.csv").open(newline="") as stream:
            cdf_rows = list(csv.DictReader(stream))
        self.assertEqual({row["model_variant"] for row in cdf_rows}, {"full", "full_unconstrained"})
        metadata = json.loads((output / "metadata.json").read_text())
        self.assertEqual([variant["id"] for variant in metadata["model_variants"]], ["full", "full_unconstrained"])
        analysis = json.loads((output / "analysis.json").read_text())
        self.assertEqual(len(analysis["capability_results"]), 2)
        self.assertEqual(
            {(row["model_variant"], row["baseline_model_variant"]) for row in analysis["capability_results"]},
            {("full", "full"), ("full_unconstrained", "full")},
        )

    def test_objective_only_cross_model_comparison_analyzes(self):
        directory = self.remember(self.make_fixture(cross_model=True, cross_scenario="objective_only"))
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "primary_results.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 2)
        self.assertEqual(
            [(row["model_variant"], row["baseline_model_variant"]) for row in rows],
            [("full", "full"), ("blast_only", "full")],
        )
        self.assertAlmostEqual(float(rows[1]["paired_mean_difference"]), 2.0)
        metadata = json.loads((output / "metadata.json").read_text())
        self.assertEqual([variant["id"] for variant in metadata["model_variants"]], ["full", "blast_only"])

    def test_arbitrary_model_labels_and_self_comparison_analyzed(self):
        directory = self.remember(self.make_fixture())
        manifest = json.loads((directory / "manifest.resolved.json").read_text())
        manifest["model_variants"] = [
            {"id": "homemade-model", "objective": "custom_objective", "require_pre_attack_feasibility": False}
        ]
        for run in manifest["strategy_runs"]:
            run["model_variant"] = "homemade-model"
        comparison = manifest["analysis"]["primary_comparisons"][0]
        comparison["model_variant"] = "homemade-model"
        comparison["baseline_model_variant"] = "homemade-model"
        comparison["baseline"] = comparison["strategy"]
        (directory / "manifest.resolved.json").write_text(json.dumps(manifest))
        plans = [json.loads(line) for line in (directory / "plans.jsonl").read_text().splitlines()]
        for plan in plans:
            plan["model_variant"] = "homemade-model"
            plan["objective"] = "custom_objective"
            plan["require_pre_attack_feasibility"] = False
        (directory / "plans.jsonl").write_text("\n".join(json.dumps(plan) for plan in plans) + "\n")
        self.write_checksums(directory)
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "primary_results.csv").open(newline="") as stream:
            result = next(csv.DictReader(stream))
        self.assertAlmostEqual(float(result["paired_mean_difference"]), 0.0)

    def test_malformed_plan_types_rejected(self):
        directory = self.remember(self.make_fixture())
        plans = [json.loads(line) for line in (directory / "plans.jsonl").read_text().splitlines()]
        plans[0]["id"] = []
        (directory / "plans.jsonl").write_text("\n".join(json.dumps(plan) for plan in plans) + "\n")
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_non_integer_and_single_trial_settings_rejected(self):
        directory = self.remember(self.make_fixture())
        manifest = json.loads((directory / "manifest.resolved.json").read_text())
        manifest["analysis"]["bootstrap_resamples"] = 2.5
        (directory / "manifest.resolved.json").write_text(json.dumps(manifest))
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

        manifest["analysis"]["bootstrap_resamples"] = 200
        manifest["evaluation"]["trials"] = 1
        (directory / "manifest.resolved.json").write_text(json.dumps(manifest))
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_duplicate_trial_rejected(self):
        directory = self.remember(self.make_fixture())
        with (directory / "trials.csv").open() as stream:
            content = stream.read()
        (directory / "trials.csv").write_text(content + content.splitlines()[1] + "\n")
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_capability_trial_mismatch_rejected(self):
        directory = self.remember(self.make_fixture())
        with (directory / "capability_outcomes.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        rows[0]["trial_index"] = "2"
        self.write_csv(directory / "capability_outcomes.csv", rows)
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

        directory = self.remember(self.make_fixture())
        with (directory / "capability_outcomes.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.write_csv(directory / "capability_outcomes.csv", rows[:-1])
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_malformed_csv_and_negative_value_rejected(self):
        directory = self.remember(self.make_fixture())
        (directory / "trials.csv").write_text("plan_id,plan_id,trial_index,seed,blast_radius,mission_impact\n")
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

        directory = self.remember(self.make_fixture())
        lines = (directory / "trials.csv").read_text().splitlines()
        lines[0] = "plan_id,experiment_id,trial_index,seed,blast_radius,mission_impact"
        (directory / "trials.csv").write_text("\n".join(lines) + "\n")
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

        directory = self.remember(self.make_fixture())
        with (directory / "trials.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        rows[0]["blast_radius"] = "-1"
        self.write_csv(directory / "trials.csv", rows)
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_checksum_rejected(self):
        directory = self.remember(self.make_fixture())
        (directory / "trials.csv").write_text("invalid\n")
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_stale_legacy_pilot_output_is_removed(self):
        directory = self.remember(self.make_fixture())
        output = self.remember(Path(tempfile.mkdtemp()))
        stale = output / "pilot_results.csv"
        stale.write_text("comparison,passes\n")
        analyze(directory, output)
        self.assertFalse(stale.exists())
        self.assertEqual(
            json.loads((output / "metadata.json").read_text())["command_mode"],
            "analyze",
        )

    def test_capability_and_secondary_outputs(self):
        directory = self.remember(self.make_fixture())
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "capability_results.csv").open(newline="") as stream:
            capability = next(csv.DictReader(stream))
        self.assertEqual(capability["capability_name"], "Capability alpha")
        analysis = json.loads((output / "analysis.json").read_text())
        self.assertEqual(analysis["capability_results"][0]["capability_name"], "Capability alpha")
        self.assertAlmostEqual(float(capability["probability_difference"]), -1.0)
        with (output / "secondary_results.csv").open(newline="") as stream:
            self.assertEqual(len(list(csv.DictReader(stream))), 1)

    def test_phase_one_outputs(self):
        directory = self.remember(self.make_fixture())
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "host_probabilities.csv").open(newline="") as stream:
            hosts = list(csv.DictReader(stream))
        self.assertEqual(len(hosts), 4)
        tested_host = next(row for row in hosts if row["strategy"] == "unusual-tested" and row["host_id"] == "host-beta")
        self.assertEqual(tested_host["compromise_probability"], "0.0")
        with (output / "feasibility_summary.csv").open(newline="") as stream:
            feasibility = list(csv.DictReader(stream))
        baseline = next(row for row in feasibility if not row["plan_id"])
        self.assertEqual(baseline["pre_attack_feasible"], "False")
        self.assertEqual(baseline["affected_capability_count"], "1")
        with (output / "runtime_summary.csv").open(newline="") as stream:
            runtime = next(csv.DictReader(stream))
        self.assertEqual(runtime, {"median_plan_selection_runtime_ms": "3.0", "median_simulation_runtime_ms": "4.0", "evaluator_runtime_ms": "12.0"})
        analysis = json.loads((output / "analysis.json").read_text())
        self.assertEqual(len(analysis["host_probabilities"]), 4)
        self.assertEqual(len(analysis["feasibility_summary"]), 11)
        self.assertEqual(analysis["runtime_summary"]["evaluator_runtime_ms"], 12.0)

    def test_incomplete_phase_one_evidence_rejected(self):
        directory = self.remember(self.make_fixture())
        with (directory / "pre_attack_flow_statuses.csv").open(newline="") as stream:
            flows = list(csv.DictReader(stream))
        self.write_csv(directory / "pre_attack_flow_statuses.csv", flows[:-1])
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

        directory = self.remember(self.make_fixture())
        with (directory / "host_compromises.csv").open(newline="") as stream:
            hosts = list(csv.DictReader(stream))
        self.write_csv(directory / "host_compromises.csv", hosts[:-1])
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_header_only_flow_statuses_are_feasible(self):
        directory = self.remember(self.make_fixture())
        (directory / "pre_attack_flow_statuses.csv").write_text(
            "experiment_id,plan_id,capability_id,capability_name,source_segment_id,target_service_id,available\n"
        )
        self.write_checksums(directory)
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "feasibility_summary.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertTrue(all(row["pre_attack_feasible"] == "True" for row in rows))
        self.assertTrue(all(row["unavailable_required_flow_count"] == "0" and row["affected_capability_count"] == "0" for row in rows))

    def test_missing_summary_coverage_rejected(self):
        directory = self.remember(self.make_fixture())
        with (directory / "summary.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.write_csv(directory / "summary.csv", rows[:-1])
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_conflicting_capability_names_rejected(self):
        directory = self.remember(self.make_fixture())
        with (directory / "capability_outcomes.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        rows[1]["capability_name"] = "Different name"
        self.write_csv(directory / "capability_outcomes.csv", rows)
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

    def test_zip_and_cli_smoke(self):
        directory = self.remember(self.make_fixture())
        archive = directory.parent / "input.zip"
        with zipfile.ZipFile(archive, "w") as target:
            for path in directory.iterdir():
                target.write(path, path.name)
            target.writestr("unrelated.txt", "ignored")
        self.remember(archive)
        output = self.remember(Path(tempfile.mkdtemp()))
        command = ["uv", "run", "network-defense-analysis", "analyze", str(archive), "--output", str(output)]
        completed = subprocess.run(command, cwd=Path(__file__).parents[1], capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertTrue((output / "figures" / "blast_radius_cdf.png").is_file())

    def test_cli_rejects_legacy_pilot_command(self):
        completed = subprocess.run(
            ["uv", "run", "network-defense-analysis", "pilot", "input.zip", "--output", "out.zip"],
            cwd=Path(__file__).parents[1], capture_output=True,
        )
        self.assertNotEqual(completed.returncode, 0)

    def test_unsafe_zip_rejected(self):
        archive = Path(tempfile.mkdtemp()) / "unsafe.zip"
        with zipfile.ZipFile(archive, "w") as target:
            target.writestr("../escape", "bad")
        with self.assertRaises(AnalysisError):
            analyze(archive, archive.parent / "out")

    def test_cli_stdin_stdout_is_binary_zip_only(self):
        directory = self.remember(self.make_fixture())
        archive = self.remember(directory.parent / "stream.zip")
        with zipfile.ZipFile(archive, "w") as target:
            for path in directory.iterdir():
                target.write(path, path.name)
        completed = subprocess.run(
            ["uv", "run", "network-defense-analysis", "analyze", "-", "--output", "-"],
            cwd=Path(__file__).parents[1], input=archive.read_bytes(), capture_output=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr.decode())
        self.assertEqual(completed.stderr, b"")
        with zipfile.ZipFile(__import__("io").BytesIO(completed.stdout)) as result:
            names = result.namelist()
        self.assertEqual(names, sorted(names))
        self.assertIn("analysis.json", names)
        self.assertIn("figures/blast_radius_cdf.png", names)

    def test_cli_invalid_stdin_has_no_stdout(self):
        completed = subprocess.run(
            ["uv", "run", "network-defense-analysis", "analyze", "-", "--output", "-"],
            cwd=Path(__file__).parents[1], input=b"not a zip", capture_output=True,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(completed.stdout, b"")
        self.assertTrue(completed.stderr)

    def test_duplicate_zip_names_rejected_by_cli(self):
        archive = self.remember(Path(tempfile.mkdtemp()) / "duplicate.zip")
        with zipfile.ZipFile(archive, "w") as target:
            target.writestr("manifest.resolved.json", "one")
            target.writestr("manifest.resolved.json", "two")
        completed = subprocess.run(
            ["uv", "run", "network-defense-analysis", "analyze", str(archive), "--output", "-"],
            cwd=Path(__file__).parents[1], capture_output=True,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(completed.stdout, b"")
        self.assertIn(b"duplicate ZIP member", completed.stderr)

    def mutate_for_replica(self, directory):
        """Rewrite volatile IDs and runtimes so identical semantics still compare equal."""
        plans = [json.loads(line) for line in (directory / "plans.jsonl").read_text().splitlines()]
        rename = {}
        for index, plan in enumerate(plans):
            rename[plan["id"]] = f"replica-plan-{index}"
            plan["id"] = f"replica-plan-{index}"
            plan["runtime_ms"] = 100 + index
        (directory / "plans.jsonl").write_text("\n".join(json.dumps(plan) for plan in plans) + "\n")
        for name in ("trials.csv", "summary.csv", "capability_outcomes.csv", "host_compromises.csv", "pre_attack_flow_statuses.csv"):
            with (directory / name).open(newline="") as stream:
                rows = list(csv.DictReader(stream))
            for row in rows:
                row["experiment_id"] = f"replica-experiment-{row['plan_id'] or 'baseline'}"
                if row["plan_id"] in rename:
                    row["plan_id"] = rename[row["plan_id"]]
                if name == "summary.csv":
                    row["runtime_ms"] = "50"
            self.write_csv(directory / name, rows)
        self.write_checksums(directory)

    def test_compare_equal_despite_volatile_ids_and_runtimes(self):
        from network_defense_analysis.compare import compare
        reference = self.remember(self.make_fixture())
        candidate = self.remember(self.make_fixture())
        self.mutate_for_replica(candidate)
        equal, differences = compare(reference, candidate)
        self.assertTrue(equal, differences)
        self.assertEqual(differences, [])

    def test_compare_detects_groups_identity_mismatch(self):
        from network_defense_analysis.compare import compare
        reference = self.remember(self.make_fixture())
        candidate = self.remember(self.make_fixture())
        self.mutate_for_replica(candidate)
        with (candidate / "host_compromises.csv").open(newline="") as stream:
            hosts = list(csv.DictReader(stream))
        hosts[0]["compromised"] = "false" if hosts[0]["compromised"] == "true" else "true"
        self.write_csv(candidate / "host_compromises.csv", hosts)
        self.write_checksums(candidate)
        equal, differences = compare(reference, candidate)
        self.assertFalse(equal)
        self.assertIn("host_compromises", differences)

    def test_compare_detects_trial_mismatch(self):
        from network_defense_analysis.compare import compare
        reference = self.remember(self.make_fixture())
        candidate = self.remember(self.make_fixture())
        self.mutate_for_replica(candidate)
        with (candidate / "trials.csv").open(newline="") as stream:
            trials = list(csv.DictReader(stream))
        trials[0]["blast_radius"] = "55"
        self.write_csv(candidate / "trials.csv", trials)
        self.write_checksums(candidate)
        equal, differences = compare(reference, candidate)
        self.assertFalse(equal)
        self.assertIn("trials", differences)

    def test_compare_detects_manifest_mismatch(self):
        from network_defense_analysis.compare import compare
        reference = self.remember(self.make_fixture())
        candidate = self.remember(self.make_fixture())
        manifest = json.loads((candidate / "manifest.resolved.json").read_text())
        manifest["id"] = "different-manifest"
        (candidate / "manifest.resolved.json").write_text(json.dumps(manifest))
        self.write_checksums(candidate)
        equal, differences = compare(reference, candidate)
        self.assertFalse(equal)
        self.assertIn("manifest", differences)

    def test_compare_malformed_archive_exits_two(self):
        candidate = self.remember(self.make_fixture())
        (candidate / "trials.csv").write_text("invalid\n")
        completed = subprocess.run(
            ["uv", "run", "network-defense-analysis", "compare", str(candidate), str(candidate)],
            cwd=Path(__file__).parents[1], capture_output=True, text=True,
        )
        self.assertEqual(completed.returncode, 2)

    def test_compare_cli_equal_exits_zero(self):
        directory = self.remember(self.make_fixture())
        completed = subprocess.run(
            ["uv", "run", "network-defense-analysis", "compare", str(directory), str(directory)],
            cwd=Path(__file__).parents[1], capture_output=True, text=True,
        )
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(json.loads(completed.stdout), {"equal": True})

    def test_compare_cli_mismatch_exits_one(self):
        reference = self.remember(self.make_fixture())
        candidate = self.remember(self.make_fixture())
        with (candidate / "trials.csv").open(newline="") as stream:
            trials = list(csv.DictReader(stream))
        trials[0]["mission_impact"] = "77"
        self.write_csv(candidate / "trials.csv", trials)
        self.write_checksums(candidate)
        completed = subprocess.run(
            ["uv", "run", "network-defense-analysis", "compare", str(reference), str(candidate)],
            cwd=Path(__file__).parents[1], capture_output=True, text=True,
        )
        self.assertEqual(completed.returncode, 1)
        result = json.loads(completed.stdout)
        self.assertEqual(result["equal"], False)
        self.assertIn("trials", result["differences"])


class RefactorHelperTest(unittest.TestCase):
    def test_comparison_stream_seed_preserves_existing_arithmetic(self):
        self.assertEqual(_comparison_stream_seed(700, 0, 0), 700)
        self.assertEqual(_comparison_stream_seed(700, 0, 3), 706)
        self.assertEqual(_comparison_stream_seed(6300, 2_000_000, 5), 2_006_310)
        self.assertEqual(_comparison_stream_seed("700", 0, 1), 702)

    def test_legacy_paired_statistics_removed(self):
        self.assertFalse(hasattr(statistics_module, "_paired_statistics"))

    def test_plan_variation_uses_indexed_lookup(self):
        by_seed = {
            ("plan-a", seed): {"seed": seed, "mission_impact": float(seed)}
            for seed in (1, 2, 3)
        }
        self.assertEqual(
            _plan_variation_values(by_seed, "plan-a", [1, 2, 3], "mission_impact"),
            [1.0, 2.0, 3.0],
        )

    def test_plan_variation_missing_cell_raises_analysis_error(self):
        by_seed = {("plan-a", 1): {"seed": 1, "blast_radius": 2.0}}
        with self.assertRaises(AnalysisError):
            _plan_variation_values(by_seed, "plan-a", [1, 2], "blast_radius")

    def test_package_metadata_helpers(self):
        self.assertTrue(_package_version())
        versions = _dependency_versions()
        self.assertEqual(set(versions), {"numpy", "scipy", "matplotlib"})
        self.assertTrue(all(versions.values()))

    def test_non_regular_zip_member_rejected(self):
        archive = Path(tempfile.mkdtemp()) / "fifo.zip"
        with zipfile.ZipFile(archive, "w") as target:
            info = zipfile.ZipInfo("fifo")
            info.create_system = 3
            info.external_attr = (stat.S_IFIFO | 0o600) << 16
            target.writestr(info, "bad")
        with self.assertRaises(AnalysisError):
            analyze(archive, archive.parent / "out")

    def test_symlink_zip_member_rejected(self):
        archive = Path(tempfile.mkdtemp()) / "link.zip"
        with zipfile.ZipFile(archive, "w") as target:
            info = zipfile.ZipInfo("link")
            info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            target.writestr(info, "target")
        with self.assertRaises(AnalysisError):
            analyze(archive, archive.parent / "out")

    def test_zero_unix_mode_member_accepted(self):
        archive = Path(tempfile.mkdtemp()) / "plain.zip"
        with zipfile.ZipFile(archive, "w") as target:
            info = zipfile.ZipInfo("plain.txt")
            info.create_system = 3
            info.external_attr = 0
            target.writestr(info, "ok")
        root, temporary = _safe_extract(archive)
        try:
            self.assertEqual((root / "plain.txt").read_text(), "ok")
        finally:
            shutil.rmtree(temporary, ignore_errors=True)


class CrossedComparisonTest(unittest.TestCase):
    @staticmethod
    def crossed_inputs(*, tested_plan_count=6, baseline_plan_count=5, attack_count=12):
        """Return normalized crossed inputs in the archive loader shape.

        Plan IDs run opposite to the selection-seed order. A constructor that
        sorts by plan ID would produce a different row order than one that
        sorts by the normalized plan identity.
        """

        attack_seeds = [7001 + index for index in range(attack_count)]
        tested_ids = [f"tested-{index}" for index in reversed(range(tested_plan_count))]
        baseline_ids = [f"baseline-{index}" for index in reversed(range(baseline_plan_count))]
        tested_seeds = [41 + index for index in range(tested_plan_count)]
        baseline_seeds = [61 + index for index in range(baseline_plan_count)]
        sides = [
            (tested_ids, tested_seeds, "unusual-tested", 100.0),
            (baseline_ids, baseline_seeds, "ordinary-baseline", 200.0),
        ]
        identities = {}
        trials = {}
        schedules = {}
        expected = {}
        for plan_ids, selection_seeds, strategy, base in sides:
            for plan_id, selection_seed in zip(plan_ids, selection_seeds):
                identities[plan_id] = ("full", strategy, 8, selection_seed)
                schedules[plan_id] = list(attack_seeds)
                rows = []
                for trial_index, seed in enumerate(attack_seeds, 1):
                    value = base + selection_seed + trial_index
                    trials[(plan_id, trial_index)] = {
                        "seed": seed,
                        "blast_radius": value,
                        "mission_impact": value,
                    }
                    rows.append(value)
                expected[plan_id] = rows
        return {
            "attack_seeds": attack_seeds,
            "identities": identities,
            "trials": trials,
            "schedules": schedules,
            "tested": tested_ids,
            "baseline": baseline_ids,
            "expected": expected,
        }

    @staticmethod
    def build(data):
        return _crossed_comparison(
            data["tested"],
            data["baseline"],
            data["identities"],
            data["trials"],
            data["schedules"],
            "mission_impact",
        )

    def test_matrix_values_and_shape(self):
        data = self.crossed_inputs(tested_plan_count=6, baseline_plan_count=5, attack_count=12)
        comparison = self.build(data)
        self.assertEqual(comparison.tested.shape, (6, 12))
        self.assertEqual(comparison.baseline.shape, (5, 12))
        self.assertEqual(comparison.attack_seeds, tuple(data["attack_seeds"]))
        self.assertEqual(
            comparison.tested_plan_ids,
            ("tested-5", "tested-4", "tested-3", "tested-2", "tested-1", "tested-0"),
        )
        self.assertEqual(
            comparison.baseline_plan_ids,
            ("baseline-4", "baseline-3", "baseline-2", "baseline-1", "baseline-0"),
        )
        for index, plan_id in enumerate(comparison.tested_plan_ids):
            np.testing.assert_array_equal(
                comparison.tested[index],
                np.asarray(data["expected"][plan_id], dtype=float),
            )
        for index, plan_id in enumerate(comparison.baseline_plan_ids):
            np.testing.assert_array_equal(
                comparison.baseline[index],
                np.asarray(data["expected"][plan_id], dtype=float),
            )

    def test_different_plan_counts_on_each_side(self):
        data = self.crossed_inputs(tested_plan_count=7, baseline_plan_count=5, attack_count=12)
        comparison = self.build(data)
        self.assertEqual(comparison.tested.shape, (7, 12))
        self.assertEqual(comparison.baseline.shape, (5, 12))
        self.assertEqual(len(comparison.tested_plan_ids), 7)
        self.assertEqual(len(comparison.baseline_plan_ids), 5)

    def test_plan_rows_follow_normalized_identity_order(self):
        data = self.crossed_inputs()
        comparison = _crossed_comparison(
            list(reversed(data["tested"])),
            list(reversed(data["baseline"])),
            data["identities"],
            data["trials"],
            data["schedules"],
            "mission_impact",
        )
        self.assertEqual(
            list(comparison.tested_plan_ids),
            sorted(data["tested"], key=data["identities"].__getitem__),
        )
        self.assertEqual(
            list(comparison.baseline_plan_ids),
            sorted(data["baseline"], key=data["identities"].__getitem__),
        )
        # The constructor must not sort by generated plan ID.
        self.assertNotEqual(list(comparison.tested_plan_ids), sorted(data["tested"]))
        self.assertEqual(comparison.tested_plan_ids[0], "tested-5")
        self.assertLess(
            data["identities"][comparison.tested_plan_ids[0]][3],
            data["identities"][comparison.tested_plan_ids[-1]][3],
        )

    def test_attack_columns_follow_declared_schedule_order(self):
        data = self.crossed_inputs()
        reversed_seeds = list(reversed(data["attack_seeds"]))
        data["schedules"] = {
            plan_id: list(reversed_seeds) for plan_id in data["schedules"]
        }
        comparison = self.build(data)
        self.assertEqual(comparison.attack_seeds, tuple(reversed_seeds))
        for index, plan_id in enumerate(comparison.tested_plan_ids):
            np.testing.assert_array_equal(
                comparison.tested[index],
                np.asarray(list(reversed(data["expected"][plan_id])), dtype=float),
            )

    def test_empty_side_rejected(self):
        data = self.crossed_inputs()
        with self.assertRaises(AnalysisError):
            _crossed_comparison(
                [],
                data["baseline"],
                data["identities"],
                data["trials"],
                data["schedules"],
                "mission_impact",
            )
        with self.assertRaises(AnalysisError):
            _crossed_comparison(
                data["tested"],
                [],
                data["identities"],
                data["trials"],
                data["schedules"],
                "mission_impact",
            )

    def test_missing_cell_rejected_with_plan_and_seed(self):
        data = self.crossed_inputs()
        del data["trials"][("tested-3", 1)]
        with self.assertRaises(AnalysisError) as context:
            self.build(data)
        message = str(context.exception)
        self.assertIn("tested-3", message)
        self.assertIn(str(data["attack_seeds"][0]), message)

    def test_inconsistent_schedule_rejected(self):
        data = self.crossed_inputs()
        data["schedules"]["baseline-2"] = list(reversed(data["attack_seeds"]))
        with self.assertRaises(AnalysisError):
            self.build(data)

    def test_bootstrap_is_deterministic_from_one_seed(self):
        comparison = self.build(self.crossed_inputs())
        first = _bootstrap_contrast(comparison, resamples=64, seed=4242)
        second = _bootstrap_contrast(comparison, resamples=64, seed=4242)
        self.assertEqual(first.shape, (64,))
        np.testing.assert_array_equal(first, second)

    def test_exact_finite_sample_correction_factor(self):
        expected = math.sqrt((5.0 / 4.0) * (10.0 / 9.0))
        self.assertAlmostEqual(_finite_sample_correction(5, 6, 10), expected, places=12)
        self.assertAlmostEqual(_finite_sample_correction(6, 5, 10), expected, places=12)
        larger_ratio = math.sqrt((6.0 / 5.0) * (10.0 / 9.0))
        self.assertAlmostEqual(_finite_sample_correction(6, 7, 10), larger_ratio, places=12)

    def test_finite_sample_correction_rejects_degenerate_counts(self):
        for counts in ((1, 5, 10), (5, 1, 10), (5, 5, 1)):
            with self.assertRaises(AnalysisError):
                _finite_sample_correction(*counts)

    def test_bootstrap_rejects_small_plan_and_attack_counts(self):
        short_tested = self.build(
            self.crossed_inputs(tested_plan_count=4, baseline_plan_count=5, attack_count=12)
        )
        with self.assertRaises(AnalysisError):
            _bootstrap_contrast(short_tested, resamples=16, seed=1)
        short_baseline = self.build(
            self.crossed_inputs(tested_plan_count=5, baseline_plan_count=4, attack_count=12)
        )
        with self.assertRaises(AnalysisError):
            _bootstrap_contrast(short_baseline, resamples=16, seed=1)
        short_attacks = self.build(
            self.crossed_inputs(tested_plan_count=5, baseline_plan_count=5, attack_count=9)
        )
        with self.assertRaises(AnalysisError):
            _bootstrap_contrast(short_attacks, resamples=16, seed=1)

    def test_bootstrap_accepts_minimum_counts_and_rejects_zero_resamples(self):
        comparison = self.build(
            self.crossed_inputs(tested_plan_count=5, baseline_plan_count=5, attack_count=10)
        )
        values = _bootstrap_contrast(comparison, resamples=32, seed=7)
        self.assertEqual(values.shape, (32,))
        self.assertTrue(np.all(np.isfinite(values)))
        with self.assertRaises(AnalysisError):
            _bootstrap_contrast(comparison, resamples=0, seed=7)

    def test_bootstrap_pairs_attack_columns_across_sides(self):
        # Every tested row equals its matching baseline row plus 3.0. Both
        # sides share one attack-column profile. Paired column sampling keeps
        # every replicate at 3.0. Independent column sampling would mix column
        # means and add visible spread, so this test fails if the columns are
        # sampled separately.
        base = np.arange(12, dtype=float)
        tested = np.broadcast_to(base + 3.0, (6, 12)).copy()
        baseline = np.broadcast_to(base, (5, 12)).copy()
        comparison = CrossedComparison(
            tested=tested,
            baseline=baseline,
            tested_plan_ids=tuple(f"tested-{index}" for index in range(6)),
            baseline_plan_ids=tuple(f"baseline-{index}" for index in range(5)),
            attack_seeds=tuple(range(12)),
        )
        observed = float(comparison.tested.mean() - comparison.baseline.mean())
        self.assertAlmostEqual(observed, 3.0, places=12)
        values = _bootstrap_contrast(comparison, resamples=200, seed=11)
        np.testing.assert_allclose(values, 3.0, rtol=0.0, atol=1e-9)

    def test_crossed_comparison_rejects_mismatched_attack_columns(self):
        with self.assertRaises(AnalysisError):
            CrossedComparison(
                tested=np.zeros((5, 10)),
                baseline=np.zeros((5, 9)),
                tested_plan_ids=tuple(f"tested-{index}" for index in range(5)),
                baseline_plan_ids=tuple(f"baseline-{index}" for index in range(5)),
                attack_seeds=tuple(range(10)),
            )
        with self.assertRaises(AnalysisError):
            CrossedComparison(
                tested=np.zeros(10),
                baseline=np.zeros(10),
                tested_plan_ids=("tested-0",),
                baseline_plan_ids=("baseline-0",),
                attack_seeds=tuple(range(10)),
            )


class CrossedStatisticsTest(unittest.TestCase):
    CONFIGURATION = {"confidence_level": 0.9, "bootstrap_resamples": 400}

    @staticmethod
    def comparison(tested, baseline):
        tested = np.asarray(tested, dtype=float)
        baseline = np.asarray(baseline, dtype=float)
        return CrossedComparison(
            tested=tested,
            baseline=baseline,
            tested_plan_ids=tuple(f"tested-{index}" for index in range(tested.shape[0])),
            baseline_plan_ids=tuple(f"baseline-{index}" for index in range(baseline.shape[0])),
            attack_seeds=tuple(range(tested.shape[1])),
        )

    @staticmethod
    def varied(rows, columns, shift=0.0):
        row_effect = np.arange(rows, dtype=float)[:, None]
        column_effect = np.arange(columns, dtype=float)[None, :] * 0.5
        return shift + row_effect + column_effect

    def test_positive_and_negative_contrast_signs(self):
        base = self.varied(5, 10, 5.0)
        positive = _crossed_statistics(self.comparison(base + 2.0, base), self.CONFIGURATION, 31)
        negative = _crossed_statistics(self.comparison(base, base + 2.0), self.CONFIGURATION, 31)
        self.assertAlmostEqual(positive.mean_difference, 2.0, places=9)
        self.assertAlmostEqual(negative.mean_difference, -2.0, places=9)
        self.assertTrue(positive.informative)
        self.assertTrue(negative.informative)

    def test_plan_variation_changes_interval_width(self):
        columns = np.arange(10, dtype=float)[None, :] * 0.2
        baseline = 5.0 + np.zeros((5, 1)) + columns
        low_plan = np.linspace(0.0, 0.2, 5)[:, None] + columns
        high_plan = np.linspace(0.0, 8.0, 5)[:, None] + columns
        low = _crossed_statistics(self.comparison(low_plan, baseline), self.CONFIGURATION, 32)
        high = _crossed_statistics(self.comparison(high_plan, baseline), self.CONFIGURATION, 32)
        self.assertGreater(high.ci_half_width, low.ci_half_width)

    def test_attack_variation_changes_interval_width(self):
        rows = np.arange(5, dtype=float)[:, None] * 0.1
        baseline = 5.0 + rows + np.zeros((1, 10))
        low_attack = 3.0 + rows + np.linspace(0.0, 0.1, 10)[None, :]
        high_attack = 3.0 + rows + np.linspace(0.0, 8.0, 10)[None, :]
        low = _crossed_statistics(self.comparison(low_attack, baseline), self.CONFIGURATION, 33)
        high = _crossed_statistics(self.comparison(high_attack, baseline), self.CONFIGURATION, 33)
        self.assertGreater(high.ci_half_width, low.ci_half_width)

    def test_all_zero_is_non_informative_with_unit_p_value(self):
        zeros = np.zeros((5, 10))
        with warnings.catch_warnings(record=True) as records:
            warnings.simplefilter("always")
            result = _crossed_statistics(self.comparison(zeros, zeros), self.CONFIGURATION, 34)
        self.assertFalse(result.informative)
        self.assertEqual(result.p_raw, 1.0)
        self.assertEqual(result.ci_lower, 0.0)
        self.assertEqual(result.ci_upper, 0.0)
        self.assertEqual(records, [])

    def test_zero_width_non_zero_contrast_warns_and_stays_informative(self):
        baseline = np.full((5, 10), 4.0)
        tested = np.full((5, 10), 7.0)
        with warnings.catch_warnings(record=True) as records:
            warnings.simplefilter("always")
            result = _crossed_statistics(self.comparison(tested, baseline), self.CONFIGURATION, 35)
        self.assertTrue(result.informative)
        self.assertAlmostEqual(result.mean_difference, 3.0, places=9)
        self.assertEqual(result.ci_lower, result.ci_upper)
        self.assertEqual(len(records), 1)
        self.assertIs(records[0].category, DegenerateContrastWarning)
        self.assertEqual(
            str(records[0].message),
            "informative primary contrast has a zero-width confidence interval",
        )
        self.assertGreater(result.p_raw, 0.0)

    def test_p_value_is_deterministic_and_never_zero(self):
        base = self.varied(5, 10, 4.0)
        comparison = self.comparison(base + 1.5, base)
        first = _crossed_statistics(comparison, self.CONFIGURATION, 36)
        second = _crossed_statistics(comparison, self.CONFIGURATION, 36)
        self.assertEqual(first.p_raw, second.p_raw)
        self.assertGreater(first.p_raw, 0.0)
        self.assertLessEqual(first.p_raw, 1.0)

    def test_interval_and_null_streams_use_distinct_child_seeds(self):
        interval_seed, null_seed = _child_seeds(1234)
        self.assertNotEqual(interval_seed, null_seed)
        self.assertEqual(_child_seeds(1234), (interval_seed, null_seed))


if __name__ == "__main__":
    unittest.main()
