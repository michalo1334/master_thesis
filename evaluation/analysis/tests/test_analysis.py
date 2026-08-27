import csv
import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

from network_defense_analysis import AnalysisError, analyze
from network_defense_analysis.statistics import _holm


class AnalysisTest(unittest.TestCase):
    @staticmethod
    def make_fixture(*, confidence_width=1.0, two_comparisons=False, multiple_selection=False, cross_model=False, cross_scenario="feasibility_only"):
        directory = Path(tempfile.mkdtemp())
        variants = [
            {"id": "full", "objective": "mission_then_blast_radius", "require_pre_attack_feasibility": True},
        ]
        runs = [
            {"model_variant": "full", "strategy": "unusual-tested", "budget": 8, "selection_seeds": [101, 111] if multiple_selection else [101]},
            {"model_variant": "full", "strategy": "ordinary-baseline", "budget": 8, "selection_seeds": [202, 222] if multiple_selection else [202]},
        ]
        comparisons = [
            {"strategy": "unusual-tested", "model_variant": "full", "baseline": "ordinary-baseline", "baseline_model_variant": "full", "budget": 8, "outcome": "blast_radius"}
        ]
        if two_comparisons:
            runs.extend([
                {"model_variant": "full", "strategy": "second-tested", "budget": 8, "selection_seeds": [303, 333] if multiple_selection else [303]},
                {"model_variant": "full", "strategy": "second-baseline", "budget": 8, "selection_seeds": [404, 444] if multiple_selection else [404]},
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
                {"model_variant": "full", "strategy": "simulation_informed", "budget": 8, "selection_seeds": [101]},
                {"model_variant": cross_id, "strategy": "simulation_informed", "budget": 8, "selection_seeds": [101]},
            ])
            comparisons.append(
                {"strategy": "simulation_informed", "model_variant": cross_id, "baseline": "simulation_informed", "baseline_model_variant": "full", "budget": 8, "outcome": "blast_radius"}
            )
        manifest = {
            "schema_version": 3,
            "model_version": "test-model",
            "id": "test-manifest",
            "model_variants": variants,
            "evaluation": {"trials": 2},
            "strategy_runs": runs,
            "analysis": {
                "primary_comparisons": comparisons,
                "confidence_level": 0.9,
                "bootstrap_resamples": 200,
                "permutation_resamples": 200,
                "multiplicity_correction": "holm" if two_comparisons else "none",
                "seed": 700,
                "pilot": {"ci_half_width": confidence_width},
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
            ("full", "unusual-tested"): [3.0, 4.0],
            ("full", "ordinary-baseline"): [6.0, 8.0],
            ("full", "second-tested"): [2.0, 4.0],
            ("full", "second-baseline"): [3.0, 7.0],
        }
        if cross_model:
            values[("full", "simulation_informed")] = [3.0, 4.0]
            values[(cross_id, "simulation_informed")] = [5.0, 6.0]
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
        for index in range(1, 3):
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
                    "trial_count": 2,
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
                "trial_count": 2,
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
        directory = self.remember(self.make_fixture(multiple_selection=True))
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output)
        with (output / "plan_variation.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 4)
        with (output / "primary_results.csv").open(newline="") as stream:
            self.assertAlmostEqual(float(next(csv.DictReader(stream))["paired_mean_difference"]), -3.5)

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

    def test_pilot_pass_and_fail_recommendation(self):
        passing = self.remember(self.make_fixture(confidence_width=10))
        pass_output = self.remember(Path(tempfile.mkdtemp()))
        analyze(passing, pass_output, "pilot")
        with (pass_output / "pilot_results.csv").open(newline="") as stream:
            self.assertEqual(next(csv.DictReader(stream))["passes"], "True")

        failing = self.remember(self.make_fixture(confidence_width=0.00001))
        fail_output = self.remember(Path(tempfile.mkdtemp()))
        analyze(failing, fail_output, "pilot")
        with (fail_output / "pilot_results.csv").open(newline="") as stream:
            row = next(csv.DictReader(stream))
        self.assertEqual(row["passes"], "False")
        self.assertGreater(int(row["approximate_trials"]), 2)
        metadata = json.loads((fail_output / "metadata.json").read_text())
        self.assertFalse(metadata["pilot_all_pass"])

    def test_stale_pilot_output_is_removed(self):
        directory = self.remember(self.make_fixture())
        output = self.remember(Path(tempfile.mkdtemp()))
        analyze(directory, output, "pilot")
        self.assertTrue((output / "pilot_results.csv").exists())
        analyze(directory, output, "analyze")
        self.assertFalse((output / "pilot_results.csv").exists())

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
        self.assertEqual(len(analysis["feasibility_summary"]), 3)
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
