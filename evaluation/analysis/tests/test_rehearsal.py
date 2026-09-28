"""Focused tests for the crossed study rehearsal fixtures and family size.

The values come from ``rehearsal_harness``. They are test-only and invented.
"""

import csv
import io
import json
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path

from network_defense_analysis import analyze_study
from network_defense_analysis.contracts import _load
from network_defense_analysis.study import comparison_id

import rehearsal_harness
from test_study import build_bundle, make_tier


class RehearsalFixtureTest(unittest.TestCase):
    def setUp(self):
        self.paths = []

    def tearDown(self):
        for path in self.paths:
            shutil.rmtree(path, ignore_errors=True)

    def test_fixtures_produce_loadable_three_tier_archives(self):
        output = Path(tempfile.mkdtemp())
        self.paths.append(output)
        manifest = rehearsal_harness.write_fixtures(output)
        spec = json.loads(Path(manifest["study_spec"]).read_text())

        self.assertEqual(manifest["labels"], list(rehearsal_harness.TIER_LABELS))
        self.assertEqual(len(spec["pilot_seed_schedule"]["selection"]), rehearsal_harness.PILOT_PLAN_COUNT)
        self.assertEqual(len(spec["final_seed_schedule"]["selection"]), rehearsal_harness.FINAL_PLAN_COUNT)
        self.assertEqual(
            set(spec["pilot_seed_schedule"]["selection"])
            & set(spec["final_seed_schedule"]["selection"]),
            set(),
        )
        self.assertEqual(
            set(manifest["seeds"]["pilot"]["attack"]) & set(manifest["seeds"]["final"]["attack"]),
            set(),
        )

        for key, expected_plans in (("pilot_tiers", 8), ("final_tiers", 5)):
            for label in manifest["labels"]:
                export = _load(manifest[key][label])
                self.paths.append(export.temporary)
                configuration = export.manifest["analysis"]
                self.assertEqual(export.manifest["schema_version"], 3)
                self.assertEqual(len(configuration["primary_comparisons"]), 12)
                self.assertEqual(configuration["multiplicity_correction"], "holm")
                strategy_runs = export.manifest["strategy_runs"]
                self.assertEqual(len(strategy_runs), 15)
                self.assertTrue(all(len(run["selection_seeds"]) == expected_plans for run in strategy_runs))

    def test_final_fixture_holds_one_non_informative_comparison_worth_of_zeros(self):
        output = Path(tempfile.mkdtemp())
        self.paths.append(output)
        manifest = rehearsal_harness.write_fixtures(output)
        final_amber = manifest["final_tiers"][rehearsal_harness.TIER_LABELS[0]]
        with zipfile.ZipFile(final_amber) as archive:
            plans = {
                record["id"]: (record["strategy"], int(record["requested_budget"]))
                for record in (
                    json.loads(line)
                    for line in archive.read("plans.jsonl").decode().splitlines()
                    if line.strip()
                )
            }
            rows = list(csv.DictReader(io.StringIO(archive.read("trials.csv").decode())))
        zero_cells = {
            plans[row["plan_id"]]
            for row in rows
            if float(row["mission_impact"]) == 0.0
        }
        # Only the declared zero comparison contributes zeros. Its two sides
        # are the alternative and the baseline at the declared budget.
        self.assertEqual(
            zero_cells,
            {
                (rehearsal_harness.NON_INFORMATIVE_STRATEGY, rehearsal_harness.NON_INFORMATIVE_BUDGET),
                (rehearsal_harness.BASELINE, rehearsal_harness.NON_INFORMATIVE_BUDGET),
            },
        )


class StudyFamily36Test(unittest.TestCase):
    """Explicit contract test for the declared 36-comparison study family."""

    def setUp(self):
        self.paths = []

    def tearDown(self):
        for path in self.paths:
            shutil.rmtree(path, ignore_errors=True)

    def test_declared_36_family_has_unique_stable_ids_and_one_holm_pass(self):
        alternatives = ("alt-a", "alt-b", "alt-c", "alt-d")
        budgets = (1, 2, 3)
        labels = ("tier-a", "tier-b", "tier-c")
        tiers = []
        for label in labels:
            directory = make_tier(
                label,
                list(alternatives),
                list(budgets),
                plan_count=5,
                attack_count=10,
                zero_pairs={("alt-a", 2), ("cvss", 2)},
            )
            self.paths.append(directory)
            tiers.append((label, directory))
        bundle, directory = build_bundle(tiers, strategies=list(alternatives), budgets=list(budgets))
        self.paths.append(bundle.parent)
        self.paths.append(directory)
        output = Path(tempfile.mkdtemp()) / "study-analysis.zip"
        self.paths.append(output.parent)

        analyze_study(bundle, output)

        with zipfile.ZipFile(output) as result:
            rows = list(csv.DictReader(io.StringIO(result.read("primary_results.csv").decode())))
            metadata = json.loads(result.read("study_metadata.json").decode())

        self.assertEqual(metadata["family_scope"], "study")
        self.assertEqual(metadata["family_size"], 36)
        self.assertEqual(metadata["multiplicity_correction"], "holm")
        self.assertEqual(len(rows), 36)

        ids = [row["comparison_id"] for row in rows]
        self.assertEqual(len(set(ids)), 36)
        self.assertEqual(ids, sorted(ids))

        seen = set()
        for row in rows:
            expected = comparison_id(
                row["tier"],
                {
                    "model_variant": row["model_variant"],
                    "strategy": row["strategy"],
                    "baseline_model_variant": row["baseline_model_variant"],
                    "baseline": row["baseline"],
                    "budget": int(row["budget"]),
                    "outcome": row["outcome"],
                },
            )
            self.assertEqual(row["comparison_id"], expected)
            key = (row["tier"], row["strategy"], row["budget"])
            self.assertNotIn(key, seen)
            seen.add(key)
            self.assertTrue(row["p_adjusted"])
            self.assertGreaterEqual(float(row["p_adjusted"]), 0.0)
            self.assertLessEqual(float(row["p_adjusted"]), 1.0)

        non_informative = [row for row in rows if row["strategy"] == "alt-a" and row["budget"] == "2"]
        self.assertEqual(len(non_informative), 3)
        for row in non_informative:
            self.assertEqual(row["informative"], "False")
            self.assertEqual(float(row["p_raw"]), 1.0)


if __name__ == "__main__":
    unittest.main()
