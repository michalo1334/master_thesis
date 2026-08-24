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
    def make_fixture(self, *, confidence_width=1.0, two_comparisons=False, multiple_selection=False):
        directory = Path(tempfile.mkdtemp())
        runs = [
            {"strategy": "unusual-tested", "budget": 8, "selection_seeds": [101, 111] if multiple_selection else [101]},
            {"strategy": "ordinary-baseline", "budget": 8, "selection_seeds": [202, 222] if multiple_selection else [202]},
        ]
        comparisons = [
            {"strategy": "unusual-tested", "baseline": "ordinary-baseline", "budget": 8, "outcome": "blast_radius"}
        ]
        if two_comparisons:
            runs.extend([
                {"strategy": "second-tested", "budget": 8, "selection_seeds": [303, 333] if multiple_selection else [303]},
                {"strategy": "second-baseline", "budget": 8, "selection_seeds": [404, 444] if multiple_selection else [404]},
            ])
            comparisons.append(
                {"strategy": "second-tested", "baseline": "second-baseline", "budget": 8, "outcome": "blast_radius"}
            )
        manifest = {
            "schema_version": 2,
            "model_version": "test-model",
            "id": "test-manifest",
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
        plans = []
        for run in runs:
            for selection_seed in run["selection_seeds"]:
                plans.append(
                    {
                        "id": f"{run['strategy']}-{selection_seed}",
                        "strategy": run["strategy"],
                        "requested_budget": run["budget"],
                        "selection_seed": selection_seed,
                        "status": "completed",
                        "runtime_ms": 3,
                    }
                )
        (directory / "plans.jsonl").write_text("\n".join(json.dumps(plan) for plan in plans) + "\n")
        values = {
            "unusual-tested": [3.0, 4.0],
            "ordinary-baseline": [6.0, 8.0],
            "second-tested": [2.0, 4.0],
            "second-baseline": [3.0, 7.0],
        }
        trial_rows = []
        capability_rows = []
        for plan in plans:
            strategy = plan["strategy"]
            plan_id = plan["id"]
            plan_values = values[strategy]
            if plan_id not in {item["id"] for item in plans}:
                continue
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
        trial_rows.append({"experiment_id": "", "plan_id": "", "trial_index": 1, "seed": 900, "blast_radius": 99, "mission_impact": 99})
        self.write_csv(directory / "trials.csv", trial_rows)
        self.write_csv(directory / "capability_outcomes.csv", capability_rows)
        self.write_csv(
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
            ],
        )
        self.write_checksums(directory)
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
            "summary.csv",
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
        rows = [row for row in rows if not (row["plan_id"].startswith(("unusual-tested", "ordinary-baseline")) and row["trial_index"] == "2")]
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
        manifest["schema_version"] = 1
        (directory / "manifest.resolved.json").write_text(json.dumps(manifest))
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

        (directory / "manifest.resolved.json").write_text("[]")
        self.write_checksums(directory)
        with self.assertRaises(AnalysisError):
            analyze(directory, directory / "out")

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
        self.assertAlmostEqual(float(capability["probability_difference"]), -1.0)
        with (output / "secondary_results.csv").open(newline="") as stream:
            self.assertEqual(len(list(csv.DictReader(stream))), 1)

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
