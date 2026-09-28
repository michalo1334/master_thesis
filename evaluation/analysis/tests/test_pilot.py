"""Focused tests for the two-dimensional pilot.

The synthetic values here are test-only. They are not production pilot values.
"""

import csv
import io
import json
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import numpy as np
from starlette.testclient import TestClient

from network_defense_analysis import AnalysisError, service
from network_defense_analysis.statistics import CrossedComparison
from network_defense_analysis.study import (
    MAX_PILOT_SUBSAMPLES,
    PILOT_HEADERS,
    PILOT_SELECTION_RULE,
    CandidateResult,
    PilotConfiguration,
    PilotRecommendation,
    RuntimeInputs,
    _aggregate_candidate,
    _evaluate_candidate,
    _pilot_configuration,
    _predicted_runtime_ms,
    _recommendation,
    _select_candidate,
    pilot_study,
)
from test_analysis import AnalysisTest
from test_study import (
    CAPABILITY_HEADERS,
    FLOW_HEADERS,
    HOST_HEADERS,
    SUMMARY_HEADERS,
    TIER_LABELS,
    TRIAL_HEADERS,
    build_bundle,
    empty_zip_bytes,
    write_csv,
)

PILOT_ALTERNATIVES = ("alt-a", "alt-b")
PILOT_BUDGETS = (1,)
PLAN_COUNT = 8
ATTACK_COUNT = 16
ATTACK_SEEDS = [9200 + index for index in range(ATTACK_COUNT)]
PLAN_RUNTIME_MS = 4
ATTACK_TRIAL_MS = 2
TARGET = 100.0


def pilot_configuration(**overrides):
    values = {
        "ci_half_width": TARGET,
        "plan_count_candidates": [5, 6],
        "attacks_per_plan_candidates": [10, 12],
        "guard_quantile": 0.9,
        "subsamples": 2,
        "seed": 7,
        "selection_rule": PILOT_SELECTION_RULE,
    }
    values.update(overrides)
    return values


def make_pilot_tier(
    label,
    alternatives,
    budgets,
    *,
    baseline="cvss",
    plan_count=PLAN_COUNT,
    attack_count=ATTACK_COUNT,
    zero_pairs=(),
    seed=6000,
):
    """Build one valid measurement archive directory for pilot tests."""

    directory = Path(tempfile.mkdtemp())
    strategies = list(alternatives) + [baseline]
    zero = set(zero_pairs)
    seeds_by_run = {}
    plan_records = []
    selection = 200
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
        "model_version": "pilot-model",
        "id": f"{label}-manifest",
        "model_variants": [{"id": "full", "objective": "mission_then_blast_radius", "require_pre_attack_feasibility": True}],
        "evaluation": {"trials": attack_count, "seed": seed},
        "strategy_runs": runs,
        "analysis": {
            "primary_comparisons": comparisons,
            "confidence_level": 0.9,
            "bootstrap_resamples": 60,
            "permutation_resamples": 60,
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
            "runtime_ms": PLAN_RUNTIME_MS,
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
    ):
        (directory / name).write_text(",".join(headers) + "\n")
    summary_rows = [
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
            "runtime_ms": attack_count * ATTACK_TRIAL_MS,
        }
        for plan_id, _, _, _ in plan_records
    ]
    write_csv(directory / "summary.csv", SUMMARY_HEADERS, summary_rows)
    write_csv(directory / "evaluator_runtime.csv", ("runtime_ms",), [{"runtime_ms": 12}])
    AnalysisTest.write_checksums(directory)
    return directory


class PilotTestCase(unittest.TestCase):
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

    def sample_tiers(self, *, plan_count=PLAN_COUNT, attack_count=ATTACK_COUNT, zero_pairs=()):
        tiers = []
        for label in TIER_LABELS:
            directory = self.remember(
                make_pilot_tier(
                    label,
                    list(PILOT_ALTERNATIVES),
                    list(PILOT_BUDGETS),
                    plan_count=plan_count,
                    attack_count=attack_count,
                    zero_pairs=zero_pairs,
                )
            )
            tiers.append((label, directory))
        return tiers

    def build_sample(self, *, pilot=None, plan_count=PLAN_COUNT, attack_count=ATTACK_COUNT, target=TARGET, zero_pairs=(), extra_mutate=None):
        tiers = self.sample_tiers(plan_count=plan_count, attack_count=attack_count, zero_pairs=zero_pairs)

        def mutate(spec):
            spec["pilot"] = pilot_configuration(ci_half_width=target) if pilot is None else pilot
            if extra_mutate is not None:
                extra_mutate(spec)

        bundle, directory = build_bundle(
            tiers,
            strategies=list(PILOT_ALTERNATIVES),
            budgets=list(PILOT_BUDGETS),
            mutate_spec=mutate,
            mode="pilot",
        )
        self.remember(bundle.parent)
        self.remember(directory)
        return bundle

    def read_pilot(self, output):
        with zipfile.ZipFile(output) as result:
            names = set(result.namelist())
            rows = list(csv.DictReader(io.StringIO(result.read("pilot_results.csv").decode())))
            metadata = json.loads(result.read("study_metadata.json").decode())
        return rows, metadata, names


class PilotConfigurationTest(PilotTestCase):
    def test_valid_configuration_returns_sorted_tuples(self):
        configuration = _pilot_configuration(pilot_configuration())
        self.assertIsInstance(configuration, PilotConfiguration)
        self.assertEqual(configuration.plan_count_candidates, (5, 6))
        self.assertEqual(configuration.attacks_per_plan_candidates, (10, 12))
        self.assertEqual(configuration.selection_rule, PILOT_SELECTION_RULE)

    def test_plan_candidate_below_minimum_rejected(self):
        with self.assertRaises(AnalysisError):
            _pilot_configuration(pilot_configuration(plan_count_candidates=[4, 5]))

    def test_attack_candidate_below_minimum_rejected(self):
        with self.assertRaises(AnalysisError):
            _pilot_configuration(pilot_configuration(attacks_per_plan_candidates=[9, 10]))

    def test_unsorted_candidates_rejected(self):
        with self.assertRaises(AnalysisError):
            _pilot_configuration(pilot_configuration(plan_count_candidates=[6, 5]))

    def test_duplicate_candidates_rejected(self):
        with self.assertRaises(AnalysisError):
            _pilot_configuration(pilot_configuration(attacks_per_plan_candidates=[10, 10]))

    def test_empty_candidates_rejected(self):
        with self.assertRaises(AnalysisError):
            _pilot_configuration(pilot_configuration(plan_count_candidates=[]))

    def test_guard_quantile_bounds_rejected(self):
        for value in (0.0, 1.0, -0.1, 1.5):
            with self.assertRaises(AnalysisError):
                _pilot_configuration(pilot_configuration(guard_quantile=value))

    def test_subsample_count_bounds_rejected(self):
        with self.assertRaises(AnalysisError):
            _pilot_configuration(pilot_configuration(subsamples=0))
        with self.assertRaises(AnalysisError):
            _pilot_configuration(pilot_configuration(subsamples=MAX_PILOT_SUBSAMPLES + 1))

    def test_selection_rule_rejected(self):
        with self.assertRaises(AnalysisError):
            _pilot_configuration(pilot_configuration(selection_rule="cheapest"))

    def test_missing_field_rejected(self):
        incomplete = pilot_configuration()
        del incomplete["guard_quantile"]
        with self.assertRaises(AnalysisError):
            _pilot_configuration(incomplete)


class CandidateEvaluationTest(PilotTestCase):
    def sample_comparison(self, *, plan_count=PLAN_COUNT, attack_count=ATTACK_COUNT):
        rng = np.random.default_rng(4242)
        tested = rng.normal(size=(plan_count, attack_count))
        baseline = rng.normal(size=(plan_count, attack_count)) + 0.5
        return CrossedComparison(
            tested=tested,
            baseline=baseline,
            tested_plan_ids=tuple(f"tested-{index}" for index in range(plan_count)),
            baseline_plan_ids=tuple(f"baseline-{index}" for index in range(plan_count)),
            attack_seeds=tuple(ATTACK_SEEDS[:attack_count]),
        )

    def analysis_configuration(self):
        return {"confidence_level": 0.9, "bootstrap_resamples": 40}

    def test_evaluation_is_deterministic(self):
        comparison = self.sample_comparison()
        configuration = _pilot_configuration(pilot_configuration())
        first = _evaluate_candidate(
            comparison,
            plan_count=5,
            attacks_per_plan=10,
            configuration=configuration,
            stream_seed=31,
            analysis_configuration=self.analysis_configuration(),
        )
        second = _evaluate_candidate(
            comparison,
            plan_count=5,
            attacks_per_plan=10,
            configuration=configuration,
            stream_seed=31,
            analysis_configuration=self.analysis_configuration(),
        )
        self.assertEqual(first, second)
        self.assertGreaterEqual(first.guarded_half_width, 0.0)

    def test_different_stream_seed_changes_subsampling(self):
        comparison = self.sample_comparison()
        configuration = _pilot_configuration(pilot_configuration(subsamples=3))
        first = _evaluate_candidate(
            comparison,
            plan_count=5,
            attacks_per_plan=10,
            configuration=configuration,
            stream_seed=31,
            analysis_configuration=self.analysis_configuration(),
        )
        second = _evaluate_candidate(
            comparison,
            plan_count=5,
            attacks_per_plan=10,
            configuration=configuration,
            stream_seed=99,
            analysis_configuration=self.analysis_configuration(),
        )
        self.assertNotEqual(first.guarded_half_width, second.guarded_half_width)

    def test_candidate_larger_than_rows_rejected(self):
        comparison = self.sample_comparison(plan_count=5, attack_count=12)
        with self.assertRaises(AnalysisError):
            _evaluate_candidate(
                comparison,
                plan_count=6,
                attacks_per_plan=10,
                configuration=_pilot_configuration(pilot_configuration()),
                stream_seed=31,
                analysis_configuration=self.analysis_configuration(),
            )

    def test_candidate_larger_than_attacks_rejected(self):
        comparison = self.sample_comparison(plan_count=8, attack_count=11)
        with self.assertRaises(AnalysisError):
            _evaluate_candidate(
                comparison,
                plan_count=5,
                attacks_per_plan=12,
                configuration=_pilot_configuration(pilot_configuration()),
                stream_seed=31,
                analysis_configuration=self.analysis_configuration(),
            )

    def test_predicted_runtime_matches_formula(self):
        inputs = RuntimeInputs(2.0, 3.0, 4, 5)
        expected = 5 * 4 * 7 * 2.0 + 5 * 4 * 7 * 11 * 3.0
        self.assertAlmostEqual(_predicted_runtime_ms(7, 11, inputs), expected, places=9)


class CandidateSelectionTest(PilotTestCase):
    def test_worst_comparison_controls_recommendation(self):
        failing = _aggregate_candidate(
            5,
            10,
            [
                {"guarded_ci_half_width": 0.4, "passes": True},
                {"guarded_ci_half_width": 2.0, "passes": False},
            ],
        )
        self.assertEqual(failing.guarded_half_width, 2.0)
        self.assertFalse(failing.passes)
        passing = _aggregate_candidate(
            6,
            12,
            [
                {"guarded_ci_half_width": 0.6, "passes": True},
                {"guarded_ci_half_width": 0.7, "passes": True},
            ],
        )
        self.assertTrue(passing.passes)
        inputs = RuntimeInputs(1.0, 1.0, 1, 1)
        self.assertEqual(_select_candidate([failing, passing], inputs), passing)

    def test_lowest_runtime_wins(self):
        inputs = RuntimeInputs(2.0, 1.0, 2, 3)
        cheap = CandidateResult(5, 10, 0.1, True)
        costly = CandidateResult(8, 16, 0.1, True)
        self.assertLess(
            _predicted_runtime_ms(5, 10, inputs),
            _predicted_runtime_ms(8, 16, inputs),
        )
        self.assertEqual(_select_candidate([costly, cheap], inputs), cheap)

    def test_highest_plan_count_breaks_runtime_tie(self):
        inputs = RuntimeInputs(0.0, 1.0, 2, 3)
        small_plan = CandidateResult(5, 12, 0.1, True)
        large_plan = CandidateResult(6, 10, 0.1, True)
        self.assertAlmostEqual(
            _predicted_runtime_ms(5, 12, inputs),
            _predicted_runtime_ms(6, 10, inputs),
        )
        self.assertEqual(_select_candidate([small_plan, large_plan], inputs), large_plan)

    def test_lowest_attacks_breaks_remaining_tie(self):
        inputs = RuntimeInputs(1.0, 0.0, 2, 3)
        fewer = CandidateResult(5, 10, 0.1, True)
        more = CandidateResult(5, 12, 0.1, True)
        self.assertAlmostEqual(
            _predicted_runtime_ms(5, 10, inputs),
            _predicted_runtime_ms(5, 12, inputs),
        )
        self.assertEqual(_select_candidate([more, fewer], inputs), fewer)

    def test_no_feasible_candidate_is_insufficient(self):
        refused = [CandidateResult(5, 10, 3.0, False)]
        recommendation = _recommendation(refused, RuntimeInputs(1.0, 1.0, 1, 1), ())
        self.assertEqual(recommendation, PilotRecommendation(None, None, True, ()))


class PilotStudyTest(PilotTestCase):
    def test_valid_pilot_recommends_cheapest_candidate(self):
        bundle = self.build_sample()
        output = self.remember(Path(tempfile.mkdtemp()) / "pilot.zip")
        pilot_study(bundle, output)
        rows, metadata, names = self.read_pilot(output)
        self.assertEqual(
            metadata["recommendation"]["plan_selection_seed_count"], 5
        )
        self.assertEqual(metadata["recommendation"]["attacks_per_plan"], 10)
        self.assertFalse(metadata["recommendation"]["insufficient_pilot"])
        self.assertEqual(metadata["recommended_plan_selection_seed_count"], 5)
        self.assertEqual(metadata["recommended_attacks_per_plan"], 10)
        self.assertFalse(metadata["insufficient_pilot"])
        self.assertEqual(metadata["selection_rule"], PILOT_SELECTION_RULE)
        self.assertIn("study_metadata.json", names)
        self.assertIn("checksums.txt", names)
        self.assertEqual(tuple(rows[0].keys()), PILOT_HEADERS)

    def test_pilot_rows_cover_every_candidate_and_comparison(self):
        bundle = self.build_sample()
        output = self.remember(Path(tempfile.mkdtemp()) / "pilot.zip")
        pilot_study(bundle, output)
        rows, _, _ = self.read_pilot(output)
        candidates = {(int(row["candidate_plan_count"]), int(row["candidate_attacks_per_plan"])) for row in rows}
        self.assertEqual(candidates, {(5, 10), (5, 12), (6, 10), (6, 12)})
        comparisons = {row["comparison_id"] for row in rows}
        self.assertEqual(len(comparisons), len(TIER_LABELS) * len(PILOT_ALTERNATIVES) * len(PILOT_BUDGETS))
        for row in rows:
            self.assertEqual(float(row["target"]), TARGET)

    def test_candidate_larger_than_pilot_data_rejected(self):
        bundle = self.build_sample(plan_count=5, attack_count=12)
        output = self.remember(Path(tempfile.mkdtemp()) / "pilot.zip")
        with self.assertRaises(AnalysisError):
            pilot_study(bundle, output)

    def test_non_informative_comparison_blocks_every_candidate(self):
        bundle = self.build_sample(zero_pairs={("alt-a", 1), ("cvss", 1)})
        output = self.remember(Path(tempfile.mkdtemp()) / "pilot.zip")
        pilot_study(bundle, output)
        rows, metadata, _ = self.read_pilot(output)
        self.assertTrue(metadata["recommendation"]["insufficient_pilot"])
        self.assertIsNone(metadata["recommendation"]["plan_selection_seed_count"])
        self.assertIsNone(metadata["recommendation"]["attacks_per_plan"])
        self.assertEqual(
            len(metadata["recommendation"]["non_informative_comparisons"]),
            len(TIER_LABELS),
        )
        blocked_ids = set(metadata["recommendation"]["non_informative_comparisons"])
        blocked = [row for row in rows if row["comparison_id"] in blocked_ids]
        self.assertTrue(blocked)
        for row in blocked:
            self.assertEqual(row["informative"], "False")
            self.assertEqual(row["passes"], "False")

    def test_tiny_target_has_no_feasible_candidate(self):
        bundle = self.build_sample(target=1e-6)
        output = self.remember(Path(tempfile.mkdtemp()) / "pilot.zip")
        pilot_study(bundle, output)
        _, metadata, _ = self.read_pilot(output)
        self.assertTrue(metadata["recommendation"]["insufficient_pilot"])
        self.assertIsNone(metadata["recommendation"]["plan_selection_seed_count"])
        self.assertIsNone(metadata["recommendation"]["attacks_per_plan"])
        self.assertEqual(metadata["recommendation"]["non_informative_comparisons"], [])

    def test_pilot_rejects_evaluation_seed_set_mismatch(self):
        def mutate(spec):
            spec["pilot_seed_schedule"]["evaluation"] = [8_000_000]

        bundle = self.build_sample(extra_mutate=mutate)
        output = self.remember(Path(tempfile.mkdtemp()) / "pilot.zip")
        with self.assertRaises(AnalysisError):
            pilot_study(bundle, output)

    def test_metadata_records_runtime_derivation(self):
        bundle = self.build_sample()
        output = self.remember(Path(tempfile.mkdtemp()) / "pilot.zip")
        pilot_study(bundle, output)
        _, metadata, _ = self.read_pilot(output)
        self.assertIn("runtime_inputs", metadata)
        self.assertIn("runtime_derivation", metadata)
        self.assertEqual(metadata["runtime_model_note"], "Runtime is a selection heuristic, not a statistical result.")
        self.assertAlmostEqual(metadata["runtime_inputs"]["median_plan_selection_ms"], PLAN_RUNTIME_MS)
        self.assertAlmostEqual(metadata["runtime_inputs"]["median_attack_trial_ms"], ATTACK_TRIAL_MS)
        self.assertIn("divided by", metadata["runtime_derivation"]["median_attack_trial_ms"])
        self.assertEqual(metadata["runtime_inputs"]["tier_count"], len(TIER_LABELS))
        self.assertEqual(metadata["runtime_inputs"]["strategy_group_count"], 3)


class PilotServiceTest(PilotTestCase):
    def setUp(self):
        super().setUp()
        self.client = TestClient(service.create_app())

    def test_pilot_route_returns_zip(self):
        def fake(source, output):
            with zipfile.ZipFile(output, "w") as result:
                result.writestr("study_metadata.json", "{}")

        with patch.object(service, "pilot_study", side_effect=fake):
            response = self.client.post(
                "/v1/study/pilot",
                content=empty_zip_bytes(),
                headers={"content-type": "application/zip"},
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-type"], "application/zip")
        with zipfile.ZipFile(io.BytesIO(response.content)) as result:
            self.assertIn("study_metadata.json", result.namelist())

    def test_pilot_route_rejects_bad_content_type(self):
        self.assertEqual(
            self.client.post("/v1/study/pilot", content=b"x", headers={"content-type": "text/plain"}).status_code,
            415,
        )

    def test_existing_study_analyze_route_unchanged(self):
        with patch.object(service, "analyze_study", side_effect=lambda source, output: Path(output).write_bytes(b"zip")):
            response = self.client.post(
                "/v1/study/analyze",
                content=empty_zip_bytes(),
                headers={"content-type": "application/zip"},
            )
        self.assertEqual(response.status_code, 200)


class PilotCliTest(PilotTestCase):
    def test_cli_study_pilot_round_trip(self):
        bundle = self.build_sample()
        output = self.remember(Path(tempfile.mkdtemp()) / "pilot.zip")
        completed = subprocess.run(
            ["uv", "run", "network-defense-analysis", "study-pilot", str(bundle), "--output", str(output)],
            cwd=Path(__file__).parents[1],
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        with zipfile.ZipFile(output) as result:
            self.assertIn("pilot_results.csv", result.namelist())


if __name__ == "__main__":
    unittest.main()
