import copy
import json
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from evaluation_compute import statistics
from evaluation_compute.api import app
from evaluation_compute.contracts.pilot import CandidateComparisonRequest
from evaluation_compute.pilot import evaluate_candidate_comparison, pilot_issues
from evaluation_compute.pilot_limits import (
    PilotLimits,
    PilotLimitsUnavailable,
    load_pilot_limits,
    resource_issues,
)

client = TestClient(app, raise_server_exceptions=False)

CONTRACTS_ROOT = Path(__file__).resolve().parents[3] / "contracts" / "evaluation" / "pilot" / "v1"


def snapshot_document() -> dict:
    return json.loads((CONTRACTS_ROOT / "valid" / "pilot-small.snapshot.json").read_text())


def candidate_request(**overrides) -> dict:
    document = snapshot_document()
    comparison = document["payload"]["comparisons"][0]
    request = {
        "schema_version": 1,
        "method": "precision_pilot_candidate_v1",
        "pilot_id": "pilot-example",
        "study_revision_id": document["study_revision_id"],
        "family_id": document["family_id"],
        "snapshot_id": "af69d2ca-ff80-43aa-9800-67f6895be64d",
        "candidate_position": 0,
        "comparison_position": 0,
        "identity": comparison["identity"],
        "candidate": {"id": "small", "plan_count": 5, "attacks_per_plan": 10},
        "evidence": comparison["evidence"],
        "outer_subsamples": 20,
        "stream_seed": 700001,
        "guard_quantile": 0.9,
        "target_half_width": 0.5,
        "confidence_level": 0.95,
        "bootstrap_replicates": 200,
    }
    candidate = overrides.pop("candidate", None)
    request.update(overrides)
    if candidate is not None:
        request["candidate"] = {**request["candidate"], **candidate}
    return request


def validated(**overrides) -> CandidateComparisonRequest:
    return CandidateComparisonRequest.model_validate_json(
        json.dumps(candidate_request(**overrides)), strict=True
    )


def test_pilot_01_candidate_comparison_is_deterministic_and_echoes_inputs():
    request = validated()
    first = evaluate_candidate_comparison(request)
    second = evaluate_candidate_comparison(request)

    assert first == second
    assert first.guarded_half_width >= 0
    assert first.passes == (first.informative and first.guarded_half_width <= 0.5)
    dumped = first.model_dump(mode="json")
    for key, value in candidate_request().items():
        if key == "evidence":
            continue
        assert dumped[key] == value


def test_pilot_02_outer_stream_entropy_contains_seed_and_candidate_counts(monkeypatch):
    real_sequence = np.random.SeedSequence
    captured: list[object] = []

    class RecordingSequence(real_sequence):
        def __init__(self, entropy=None, *args, **kwargs):
            if not captured:
                captured.append(entropy)
            super().__init__(entropy, *args, **kwargs)

    monkeypatch.setattr("evaluation_compute.pilot.np.random.SeedSequence", RecordingSequence)

    evaluate_candidate_comparison(validated())

    assert captured == [[700001, 5, 10]]


HISTORICAL_OUTER_SAMPLES = [
    {
        "alternative_rows": [5, 1, 3, 0, 4],
        "reference_rows": [0, 2, 3, 5, 1],
        "attack_columns": [1, 0, 3, 9, 11, 2, 4, 8, 7, 5],
        "inner_seed": 2791947591,
    },
    {
        "alternative_rows": [2, 4, 5, 0, 3],
        "reference_rows": [5, 3, 4, 2, 1],
        "attack_columns": [0, 11, 1, 8, 7, 5, 3, 6, 2, 9],
        "inner_seed": 75497938,
    },
    {
        "alternative_rows": [4, 1, 5, 2, 0],
        "reference_rows": [1, 4, 5, 0, 3],
        "attack_columns": [5, 4, 6, 9, 7, 11, 8, 1, 0, 3],
        "inner_seed": 440231068,
    },
]
"""Fixed outer samples from the historical d94ba40 ``_evaluate_candidate``."""


def test_pilot_02b_historical_outer_sampling_and_inner_seeds_are_preserved(monkeypatch):
    recorded: list[dict] = []
    real_default_rng = np.random.default_rng

    class RecordingGenerator:
        def __init__(self, sequence):
            self._generator = real_default_rng(sequence)
            self._calls = 0

        def choice(self, *args, **kwargs):
            result = self._generator.choice(*args, **kwargs)
            if self._calls == 0:
                recorded.append({"alternative_rows": result.tolist()})
            elif self._calls == 1:
                recorded[-1]["reference_rows"] = result.tolist()
            else:
                recorded[-1]["attack_columns"] = result.tolist()
            self._calls += 1
            return result

    def recording_default_rng(sequence=None, *args, **kwargs):
        return RecordingGenerator(sequence)

    def recording_bootstrap(alternative, reference, *, replicates, confidence_level, seed):
        recorded[-1]["inner_seed"] = seed
        return SimpleNamespace(lower=0.0, upper=0.2, informative=True)

    monkeypatch.setattr("evaluation_compute.pilot.np.random.default_rng", recording_default_rng)
    monkeypatch.setattr("evaluation_compute.pilot.corrected_crossed_bootstrap", recording_bootstrap)

    result = evaluate_candidate_comparison(validated())

    assert len(recorded) == 20
    assert recorded[:3] == HISTORICAL_OUTER_SAMPLES
    assert result.informative is True
    assert result.guarded_half_width == 0.1
    assert result.passes is True


def test_pilot_03_each_outer_sample_uses_a_distinct_inner_bootstrap_stream(monkeypatch):
    seeds: list[int] = []
    real_bootstrap = evaluate_candidate_comparison.__globals__["corrected_crossed_bootstrap"]

    def record(alternative, reference, *, replicates, confidence_level, seed):
        seeds.append(seed)
        return real_bootstrap(
            alternative,
            reference,
            replicates=replicates,
            confidence_level=confidence_level,
            seed=seed,
        )

    monkeypatch.setattr("evaluation_compute.pilot.corrected_crossed_bootstrap", record)

    result = evaluate_candidate_comparison(validated())

    assert len(seeds) == 20
    assert len(set(seeds)) == 20
    assert result.informative is True


def test_pilot_04_stream_seed_changes_the_sample_without_changing_inputs():
    first = evaluate_candidate_comparison(validated(stream_seed=700001))
    second = evaluate_candidate_comparison(validated(stream_seed=700003))

    assert first.guarded_half_width != second.guarded_half_width


def test_pilot_05_target_and_guard_are_accepted_scientific_values():
    loose = evaluate_candidate_comparison(validated(target_half_width=100.0))
    tight = evaluate_candidate_comparison(validated(target_half_width=0.000001))
    guarded = evaluate_candidate_comparison(validated(guard_quantile=0.5))

    assert loose.passes is True
    assert tight.passes is False
    assert guarded.guarded_half_width <= loose.guarded_half_width


def test_pilot_06_candidate_bounds_are_rejected():
    plan_issues = pilot_issues(validated(candidate={"plan_count": 7, "attacks_per_plan": 10}))
    attack_issues = pilot_issues(validated(candidate={"plan_count": 5, "attacks_per_plan": 13}))

    assert [issue.code for issue in plan_issues] == ["candidate_exceeds_plan_rows"]
    assert plan_issues[0].path == ["candidate", "plan_count"]
    assert [issue.code for issue in attack_issues] == ["candidate_exceeds_attack_columns"]
    assert attack_issues[0].path == ["candidate", "attacks_per_plan"]


def test_pilot_07_identity_must_agree_with_evidence():
    identity = copy.deepcopy(candidate_request()["identity"])
    identity["alternative"] = "different-strategy"

    issues = pilot_issues(validated(identity=identity))

    assert [issue.code for issue in issues] == ["identity_mismatch"]
    assert issues[0].path == ["identity", "alternative"]
    assert issues[0].details["declared"] == identity["alternative"]


def test_pilot_08_api_returns_the_same_bounded_result():
    payload = candidate_request()
    response = client.post("/v1/pilots/candidate-comparisons", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == (set(payload) - {"evidence"}) | {
        "guarded_half_width",
        "informative",
        "passes",
    }
    assert body["identity"] == payload["identity"]
    assert body["guarded_half_width"] >= 0


def test_pilot_09_api_rejects_unknown_fields_and_wrong_numeric_types():
    unknown = client.post(
        "/v1/pilots/candidate-comparisons",
        json=candidate_request(unexpected_field=True),
    )
    wrong_type = client.post(
        "/v1/pilots/candidate-comparisons",
        json=candidate_request(candidate={"plan_count": 5.0, "attacks_per_plan": 10}),
    )
    unsupported = client.post(
        "/v1/pilots/candidate-comparisons",
        json=candidate_request(schema_version=2),
    )

    assert unknown.status_code == 422
    assert unknown.json()["error"]["code"] == "validation_failed"
    assert wrong_type.status_code == 422
    assert unsupported.status_code == 422
    for response in (unknown, wrong_type, unsupported):
        error = response.json()["error"]
        assert ("issues" in error) != ("schema_errors" in error)


def test_pilot_10_api_rejects_bounded_issues_before_calculation():
    response = client.post(
        "/v1/pilots/candidate-comparisons",
        json=candidate_request(candidate={"plan_count": 99, "attacks_per_plan": 10}),
    )

    assert response.status_code == 422
    assert response.json()["error"]["issues"][0]["code"] == "candidate_exceeds_plan_rows"


def test_pilot_11_api_uses_the_shared_http_boundary():
    response = client.post(
        "/v1/pilots/candidate-comparisons",
        content=b" " * 1_048_577,
        headers={"content-type": "application/json"},
    )

    assert response.status_code == 413
    assert response.json()["error"]["code"] == "request_too_large"


LIMIT_ENV = (
    "EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES",
    "EVALUATION_PILOT_MAX_BOOTSTRAP_REPLICATES",
    "EVALUATION_PILOT_MAX_COMBINED_BOOTSTRAP_WORK",
)


def set_limits(monkeypatch, outer="128", replicates="1024", work="131072"):
    monkeypatch.setenv("EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES", outer)
    monkeypatch.setenv("EVALUATION_PILOT_MAX_BOOTSTRAP_REPLICATES", replicates)
    monkeypatch.setenv("EVALUATION_PILOT_MAX_COMBINED_BOOTSTRAP_WORK", work)


def test_pilot_12_missing_or_malformed_compute_limits_fail_the_route_safely(monkeypatch):
    for name in LIMIT_ENV:
        monkeypatch.delenv(name)

    response = client.post("/v1/pilots/candidate-comparisons", json=candidate_request())
    assert response.status_code == 500
    error = response.json()["error"]
    assert error["code"] == "compute_failed"
    assert error["issues"][0]["code"] == "configuration_invalid"
    assert len(error["issues"][0]["message"].encode("utf-8")) <= 256

    with pytest.raises(PilotLimitsUnavailable):
        load_pilot_limits()

    for name, value in (
        ("EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES", "abc"),
        ("EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES", "0"),
        ("EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES", "-1"),
        ("EVALUATION_PILOT_MAX_BOOTSTRAP_REPLICATES", "1.5"),
    ):
        set_limits(monkeypatch)
        monkeypatch.setenv(name, value)

        with pytest.raises(PilotLimitsUnavailable):
            load_pilot_limits()

        response = client.post("/v1/pilots/candidate-comparisons", json=candidate_request())
        assert response.status_code == 500
        assert response.json()["error"]["issues"][0]["code"] == "configuration_invalid"


def test_pilot_13_missing_pilot_limits_keep_other_routes_usable(monkeypatch, valid_request):
    for name in LIMIT_ENV:
        monkeypatch.delenv(name)

    identity = {
        "tier": "core",
        "budget": 4,
        "alternative": "simulation_informed",
        "reference": "cvss",
        "outcome": "mission_impact",
    }

    comparison = client.post("/v1/comparisons/corrected-crossed-bootstrap", json=valid_request)
    holm = client.post(
        "/v1/families/holm",
        json={
            "schema_version": 1,
            "family_id": "family-example",
            "method": "holm",
            "alpha": 0.05,
            "expected_comparisons": [identity],
            "raw_results": [{"identity": identity, "raw_p_value": 0.01}],
        },
    )

    assert comparison.status_code == 200
    assert holm.status_code == 200

    pilot = client.post("/v1/pilots/candidate-comparisons", json=candidate_request())
    assert pilot.status_code == 500
    assert pilot.json()["error"]["issues"][0]["code"] == "configuration_invalid"


def test_pilot_14_each_resource_cap_rejects_before_calculation(monkeypatch):
    limits = load_pilot_limits()
    assert limits.max_outer_subsamples == 128
    assert limits.max_bootstrap_replicates == 1024
    assert limits.max_combined_bootstrap_work == 131072

    cases = [
        ("128", "1024", "1000000", {"outer_subsamples": 129}, ["outer_subsamples"]),
        (
            "128",
            "1024",
            "1000000",
            {"bootstrap_replicates": 1025},
            ["bootstrap_replicates"],
        ),
        (
            "128",
            "1024",
            "100000",
            {"outer_subsamples": 128, "bootstrap_replicates": 1024},
            ["outer_subsamples", "bootstrap_replicates"],
        ),
    ]

    for outer, replicates, work, overrides, expected_path in cases:
        set_limits(monkeypatch, outer, replicates, work)

        issues = resource_issues(validated(**overrides), load_pilot_limits())

        assert [issue.code for issue in issues] == ["invalid_analysis_setting"]
        assert issues[0].path == expected_path

        response = client.post(
            "/v1/pilots/candidate-comparisons", json=candidate_request(**overrides)
        )
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "validation_failed"
        assert response.json()["error"]["issues"][0]["code"] == "invalid_analysis_setting"

    set_limits(monkeypatch)
    monkeypatch.setattr(
        "evaluation_compute.api.evaluate_candidate_comparison",
        lambda *_args, **_kwargs: pytest.fail("calculation must not start"),
    )
    response = client.post(
        "/v1/pilots/candidate-comparisons",
        json=candidate_request(outer_subsamples=129),
    )
    assert response.status_code == 422


def test_pilot_15_trillion_scale_product_is_rejected_without_allocation(monkeypatch):
    body = candidate_request(outer_subsamples=10**12, bootstrap_replicates=10**12)
    assert len(json.dumps(body).encode("utf-8")) < 1_048_576

    monkeypatch.setattr(
        "evaluation_compute.api.evaluate_candidate_comparison",
        lambda *_args, **_kwargs: pytest.fail("calculation must not start"),
    )

    response = client.post("/v1/pilots/candidate-comparisons", json=body)

    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "validation_failed"
    assert {issue["code"] for issue in error["issues"]} == {"invalid_analysis_setting"}
    assert all(len(issue["message"].encode("utf-8")) <= 256 for issue in error["issues"])


def test_pilot_16_resource_issues_are_empty_within_the_configured_caps():
    limits = load_pilot_limits()

    assert resource_issues(validated(), limits) == []
    assert resource_issues(validated(outer_subsamples=limits.max_outer_subsamples), limits) == []


def test_pilot_20_astronomical_request_integers_get_bounded_diagnostics(monkeypatch):
    limits = load_pilot_limits()
    huge = 10**400

    issues = resource_issues(validated(outer_subsamples=huge), limits)
    assert [issue.path for issue in issues] == [
        ["outer_subsamples"],
        ["outer_subsamples", "bootstrap_replicates"],
    ]
    assert {issue.code for issue in issues} == {"invalid_analysis_setting"}
    assert issues[0].details == {"limit": limits.max_outer_subsamples}

    for overrides, paths in (
        (
            {"outer_subsamples": huge},
            [["outer_subsamples"], ["outer_subsamples", "bootstrap_replicates"]],
        ),
        (
            {"bootstrap_replicates": huge},
            [["bootstrap_replicates"], ["outer_subsamples", "bootstrap_replicates"]],
        ),
        (
            {"outer_subsamples": huge, "bootstrap_replicates": huge},
            [
                ["outer_subsamples"],
                ["bootstrap_replicates"],
                ["outer_subsamples", "bootstrap_replicates"],
            ],
        ),
    ):
        issues = resource_issues(validated(**overrides), limits)

        assert [issue.path for issue in issues] == paths
        assert {issue.code for issue in issues} == {"invalid_analysis_setting"}
        for issue in issues:
            assert set(issue.details) == {"limit"}
            assert all(type(value) is int and value <= 10**15 for value in issue.details.values())

        body = candidate_request(**overrides)
        assert len(json.dumps(body).encode("utf-8")) < 1_048_576

        monkeypatch.setattr(
            "evaluation_compute.api.evaluate_candidate_comparison",
            lambda *_args, **_kwargs: pytest.fail("calculation must not start"),
        )

        response = client.post("/v1/pilots/candidate-comparisons", json=body)

        assert response.status_code == 422
        error = response.json()["error"]
        assert error["code"] == "validation_failed"
        assert all(issue["code"] == "invalid_analysis_setting" for issue in error["issues"])
        assert all(issue["path"] for issue in error["issues"])
        assert all(len(issue["message"].encode("utf-8")) <= 256 for issue in error["issues"])
        assert all(set(issue["details"]) == {"limit"} for issue in error["issues"])
        assert len(response.content) <= 65_536


def test_pilot_21_extremely_long_limit_text_is_unavailable(monkeypatch):
    for value in ("9" * 16, "9" * 400, "9" * 4301, "9" * 10_000, "1" + "0" * 5000):
        set_limits(monkeypatch)
        monkeypatch.setenv("EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES", value)

        with pytest.raises(PilotLimitsUnavailable):
            load_pilot_limits()

        response = client.post("/v1/pilots/candidate-comparisons", json=candidate_request())

        assert response.status_code == 500
        error = response.json()["error"]
        assert error["code"] == "compute_failed"
        assert error["issues"][0]["code"] == "configuration_invalid"
        assert len(error["issues"][0]["message"].encode("utf-8")) <= 256

    with pytest.raises(ValidationError):
        PilotLimits(
            max_outer_subsamples=10**400,
            max_bootstrap_replicates=1024,
            max_combined_bootstrap_work=131072,
        )


def _evidence_with_matrices(rows: list[list[float]]) -> dict:
    """Return fixture evidence with explicit plan matrices and the fixture identity."""

    evidence = copy.deepcopy(candidate_request()["evidence"])
    for side_name, matrix in zip(("alternative", "reference"), rows, strict=True):
        for plan, impacts in zip(evidence[side_name]["plans"], matrix, strict=True):
            plan["mission_impacts"] = impacts

    return evidence


def test_pilot_22_wholly_non_informative_evidence_blocks_the_candidate():
    zeros = [[0.0] * 12] * 6
    evidence = _evidence_with_matrices([zeros, zeros])

    result = evaluate_candidate_comparison(validated(evidence=evidence, target_half_width=10.0))

    assert result.guarded_half_width == 0.0
    assert result.informative is False
    assert result.passes is False


def test_pilot_23_endpoint_runs_the_real_calculation_on_non_informative_evidence():
    zeros = [[0.0] * 12] * 6
    wholly = _evidence_with_matrices([zeros, zeros])

    response = client.post(
        "/v1/pilots/candidate-comparisons",
        json=candidate_request(evidence=wholly, target_half_width=10.0),
    )

    assert response.status_code == 200
    result = response.json()
    assert result["guarded_half_width"] == 0.0
    assert result["informative"] is False
    assert result["passes"] is False

    alternative = [[1.0] * 12] * 6
    reference = [[1.0] * 12] * 5 + [[3.0] * 12]
    mixed = _evidence_with_matrices([alternative, reference])

    response = client.post(
        "/v1/pilots/candidate-comparisons",
        json=candidate_request(evidence=mixed, target_half_width=1.0, outer_subsamples=128),
    )

    assert response.status_code == 200
    result = response.json()
    assert 0.0 < result["guarded_half_width"] <= 1.0
    assert result["informative"] is False
    assert result["passes"] is False


def test_pilot_24_mixed_outer_samples_block_an_otherwise_passing_candidate():
    alternative = [[1.0] * 12] * 6
    reference = [[1.0] * 12] * 5 + [[3.0] * 12]
    evidence = _evidence_with_matrices([alternative, reference])

    result = evaluate_candidate_comparison(
        validated(
            evidence=evidence,
            outer_subsamples=128,
            target_half_width=1.0,
            bootstrap_replicates=100,
        )
    )

    # A zero guarded half width would mean every outer sample was
    # non-informative. A positive width below the target proves that at least
    # one informative sample passed on its own, so only the non-informative
    # samples block this candidate.
    assert 0.0 < result.guarded_half_width <= 1.0
    assert result.informative is False
    assert result.passes is False


def _tier_positions(expected_comparisons: list[dict]) -> dict[tuple, tuple[int, int]]:
    ranks: dict[str, int] = {}
    occurrences: dict[str, int] = {}
    positions = {}

    for comparison in expected_comparisons:
        key = (
            comparison["tier"],
            comparison["budget"],
            comparison["alternative"],
            comparison["reference"],
            comparison["outcome"],
        )
        tier = comparison["tier"]
        ranks.setdefault(tier, len(ranks))
        occurrence = occurrences.get(tier, 0)
        occurrences[tier] = occurrence + 1
        positions[key] = (ranks[tier], occurrence)

    return positions


def test_pilot_17_checked_in_candidate_responses_are_exactly_reproduced():
    snapshot = snapshot_document()
    request = json.loads((CONTRACTS_ROOT / "valid" / "pilot-small.request.json").read_text())
    limits = load_pilot_limits()

    candidates = request["candidates"]
    positions = _tier_positions(request["expected_comparisons"])
    comparisons = snapshot["payload"]["comparisons"]

    for candidate_position, candidate in enumerate(candidates):
        for comparison_position, comparison in enumerate(comparisons):
            identity = comparison["identity"]
            key = (
                identity["tier"],
                identity["budget"],
                identity["alternative"],
                identity["reference"],
                identity["outcome"],
            )
            tier_rank, occurrence = positions[key]
            stream_seed = request["pilot_sampling"]["seed"] + tier_rank * 1_000_000 + occurrence * 2

            document = {
                "schema_version": 1,
                "method": "precision_pilot_candidate_v1",
                "pilot_id": request["pilot_id"],
                "study_revision_id": request["study_revision_id"],
                "family_id": request["family_id"],
                "snapshot_id": request["snapshot_id"],
                "candidate_position": candidate_position,
                "comparison_position": comparison_position,
                "identity": identity,
                "candidate": candidate,
                "evidence": comparison["evidence"],
                "outer_subsamples": request["pilot_sampling"]["outer_subsamples"],
                "stream_seed": stream_seed,
                "guard_quantile": request["precision"]["guard_quantile"],
                "target_half_width": request["precision"]["target_half_width"],
                "confidence_level": request["precision"]["confidence_level"],
                "bootstrap_replicates": request["precision"]["bootstrap_replicates"],
            }

            parsed = CandidateComparisonRequest.model_validate_json(
                json.dumps(document), strict=True
            )
            computed = evaluate_candidate_comparison(parsed, limits).model_dump(mode="json")
            fixture_path = (
                CONTRACTS_ROOT
                / "valid"
                / "candidate-responses"
                / f"{candidate_position * len(comparisons) + comparison_position}.json"
            )
            assert computed == json.loads(fixture_path.read_text()), fixture_path.name


def test_pilot_18_inner_split_preserves_historical_child_seeds(monkeypatch):
    recorded: list[int] = []
    real_draws = statistics.corrected_crossed_draws

    def record(alternative, reference, *, replicates, seed):
        recorded.append(seed)
        return real_draws(alternative, reference, replicates=replicates, seed=seed)

    monkeypatch.setattr(statistics, "corrected_crossed_draws", record)

    evaluate_candidate_comparison(validated(bootstrap_replicates=32), load_pilot_limits())

    # First two inner seeds are HISTORICAL_OUTER_SAMPLES[0:2]. Their interval
    # and null child states were recorded from the historical d94ba40
    # `_child_seeds` function.
    assert recorded[:4] == [387241343, 2362555641, 1211332338, 2430703953]
