"""Conformance tests for the shared checked-in family examples.

Both runtimes read the files under ``contracts/evaluation/family/v1``. Python
produces them and Elixir consumes them. These tests hold Python to the same
files, so a change in either runtime cannot pass unnoticed.
"""

import json
from decimal import Decimal
from pathlib import Path
from typing import Any, get_args

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from evaluation_compute import api
from evaluation_compute.contracts.errors import ComparisonError, ComparisonIssue, IssueCode
from evaluation_compute.contracts.family import (
    FamilyIdentity,
    HolmRequest,
    HolmResponse,
    identity_key,
)
from evaluation_compute.contracts.request import ComparisonRequest
from evaluation_compute.holm import adjust_holm, holm_issues
from evaluation_compute.service import compare, evidence_issues

client = TestClient(api.app)
PATH = "/v1/families/holm"


@pytest.fixture(scope="module")
def family_root() -> Path:
    return Path(__file__).resolve().parents[3] / "contracts" / "evaluation" / "family" / "v1"


def read(root: Path, relative_path: str) -> Any:
    return json.loads((root / relative_path).read_text())


@pytest.fixture(scope="module")
def family_request(family_root: Path) -> dict:
    return read(family_root, "valid/holm-small.request.json")


@pytest.fixture(scope="module")
def stored_result(family_root: Path) -> dict:
    return read(family_root, "valid/holm-small.result.json")


def key(identity: dict) -> tuple[str, int, str, str, str]:
    return identity_key(FamilyIdentity.model_validate(identity, strict=True))


def test_conf_01_the_example_family_request_declares_four_members(family_request: dict):
    assert family_request["schema_version"] == 1
    assert family_request["evidence_role"] == "synthetic_prototype"
    assert family_request["family_id"] == "primary-comparisons-small"
    assert family_request["method"] == "holm"
    assert family_request["alpha"] == 0.05

    expected = family_request["expected_comparisons"]
    supplied = [member["identity"] for member in family_request["comparisons"]]

    assert len(expected) == 4
    assert len(supplied) == 4
    assert expected == supplied
    assert [identity["budget"] for identity in expected] == [4, 6, 4, 6]

    assert [identity["alternative"] for identity in expected] == [
        "simulation_informed",
        "simulation_informed",
        "heuristic",
        "heuristic",
    ]

    assert len({key(identity) for identity in expected}) == 4


def test_conf_02_the_checked_in_correction_response_is_reproducible(
    family_root: Path, stored_result: dict
):
    """The correction response must be exactly what this service computes."""

    correction_request = read(family_root, "valid/holm-small.correction-request.json")
    checked_in = read(family_root, "valid/holm-small.correction-response.json")

    request = HolmRequest.model_validate(correction_request, strict=True)
    assert holm_issues(request) == []

    computed = adjust_holm(request).model_dump(mode="json")

    assert computed == checked_in
    assert computed["family_size"] == 4
    assert [row["adjusted_p_value"] for row in computed["results"]] == [
        row["adjustment"]["adjusted_p_value"] for row in stored_result["comparisons"]
    ]


def test_conf_03_the_endpoint_returns_the_checked_in_response(family_root: Path):
    correction_request = read(family_root, "valid/holm-small.correction-request.json")
    checked_in = read(family_root, "valid/holm-small.correction-response.json")

    response = client.post(PATH, json=correction_request)

    assert response.status_code == 200
    assert response.json() == checked_in


def test_conf_04_the_member_statistics_are_reproducible(family_request: dict, stored_result: dict):
    """Each member statistic must follow from the checked-in request."""

    assert len(family_request["comparisons"]) == len(stored_result["comparisons"]) == 4

    for member, expected in zip(
        family_request["comparisons"], stored_result["comparisons"], strict=True
    ):
        parsed = ComparisonRequest.model_validate(member["request"], strict=True)

        assert evidence_issues(parsed) == []
        assert compare(parsed).model_dump(mode="json") == expected["statistics"]


def test_conf_05_the_stored_result_matches_the_declaration(
    family_request: dict, stored_result: dict
):
    expected = family_request["expected_comparisons"]
    stored = [comparison["identity"] for comparison in stored_result["comparisons"]]

    assert [key(identity) for identity in stored] == [key(identity) for identity in expected]

    assert stored_result["family_id"] == family_request["family_id"]
    assert stored_result["method"] == family_request["method"]
    assert stored_result["alpha"] == family_request["alpha"]
    assert stored_result["family_size"] == len(expected)
    assert stored_result["evidence_role"] == "synthetic_prototype"


def test_conf_06_one_member_rejects_the_raw_null_but_not_the_corrected_null(
    stored_result: dict,
):
    flips = [
        comparison
        for comparison in stored_result["comparisons"]
        if comparison["statistics"]["test"]["raw_p_value"] <= 0.05
        and comparison["adjustment"]["adjusted_p_value"] > 0.05
        and comparison["adjustment"]["reject_null"] is False
    ]

    assert len(flips) == 1


def test_conf_07_the_stored_result_is_a_valid_correction_response(stored_result: dict):
    response = HolmResponse.model_validate(
        {
            "schema_version": stored_result["schema_version"],
            "family_id": stored_result["family_id"],
            "method": stored_result["method"],
            "alpha": stored_result["alpha"],
            "family_size": stored_result["family_size"],
            "results": [
                {
                    "identity": comparison["identity"],
                    "raw_p_value": comparison["statistics"]["test"]["raw_p_value"],
                    "adjusted_p_value": comparison["adjustment"]["adjusted_p_value"],
                    "reject_null": comparison["adjustment"]["reject_null"],
                }
                for comparison in stored_result["comparisons"]
            ],
        },
        strict=True,
    )

    for row in response.results:
        assert (Decimal(row.adjusted_p_value) <= Decimal(str(response.alpha))) is (row.reject_null)


def test_conf_08_the_shared_correction_request_is_a_valid_holm_request(
    family_root: Path,
):
    """Positive control: the checked-in correction request parses with no issues.

    The Holm correction contract is owned by the shared family schema and the
    Python compute service. Root family requests are not Holm requests, so this
    test never feeds a root request into this model.
    """

    payload = read(family_root, "valid/holm-small.correction-request.json")

    request = HolmRequest.model_validate(payload, strict=True)

    assert holm_issues(request) == []
    assert len(request.raw_results) == len(request.expected_comparisons) == 4


@pytest.mark.parametrize(
    ("name", "case"),
    [
        ("unexpected-field.holm-request.json", "unknown_field"),
        ("p-value-out-of-range.holm-request.json", "out_of_range"),
    ],
)
def test_conf_09_a_structural_holm_failure_is_a_validation_error(
    family_root: Path, name: str, case: str
):
    """Structural failures stop at the strict model, with no cross-field check."""

    payload = read(family_root, f"invalid/holm/{name}")

    with pytest.raises(ValidationError):
        HolmRequest.model_validate(payload, strict=True)

    assert case in {"unknown_field", "out_of_range"}


def _cross_field_codes(root: Path, name: str) -> list[str]:
    """Parse a structurally valid Holm request, then check the family set."""

    request = HolmRequest.model_validate(read(root, f"invalid/holm/{name}"), strict=True)

    return [issue.code for issue in holm_issues(request)]


@pytest.mark.parametrize(
    ("name", "expected_codes"),
    [
        ("duplicate-identity.holm-request.json", ["duplicate_comparison_identity"]),
        ("missing-identity.holm-request.json", ["missing_comparison"]),
        ("unexpected-identity.holm-request.json", ["unexpected_comparison"]),
    ],
)
def test_conf_10_a_cross_field_holm_failure_reports_its_exact_code(
    family_root: Path, name: str, expected_codes: list[str]
):
    """The checked-in cross-field examples must produce one exact code each.

    They are shared fixtures: Elixir never loads them, because the correction
    request set is checked by this service before a calculation.
    """

    assert _cross_field_codes(family_root, name) == expected_codes


@pytest.mark.parametrize(
    ("name", "member_index"),
    [
        ("nested-attack-column-mismatch", 1),
        ("nested-duplicate-plan-id", 0),
    ],
)
def test_conf_11_nested_member_requests_are_rejected(
    family_root: Path, name: str, member_index: int
):
    """Both runtimes must reject the same nested member request."""

    payload = read(family_root, f"invalid/{name}.request.json")

    for index, member in enumerate(payload["comparisons"]):
        try:
            parsed = ComparisonRequest.model_validate(member["request"], strict=True)
        except ValidationError:
            assert index == member_index
            continue

        issues = evidence_issues(parsed)
        assert bool(issues) is (index == member_index)


def test_conf_12_the_shared_error_envelope_parses_through_the_python_model(
    family_root: Path,
):
    """The family error envelope uses the shared bounded error body model.

    The shared schema owns the permitted issue codes, so the Python model must
    accept every envelope the Elixir boundary can produce.
    """

    payload = read(family_root, "valid/holm-small.error.json")

    error = ComparisonError.model_validate(payload, strict=True)

    assert error.schema_version == 1
    assert error.error.code == "validation_failed"
    assert [issue.code for issue in error.error.issues or []] == ["changed_family_member"]


@pytest.mark.parametrize(
    ("code", "path"),
    [
        ("invalid_comparison_request", ["comparisons", 0, "request"]),
        ("changed_family_member", ["comparisons", 1, "request", "resampling", "seed"]),
    ],
)
def test_conf_13_the_python_error_model_accepts_family_only_codes(code: str, path: list):
    """Family-only issue codes stay inside the bounded shared error body."""

    issue = ComparisonIssue.model_validate(
        {
            "code": code,
            "path": path,
            "message": "A family member is invalid.",
            "details": {"member_index": 0},
        },
        strict=True,
    )

    assert issue.code == code

    body = ComparisonError.model_validate(
        {
            "schema_version": 1,
            "error": {"code": "validation_failed", "issues": [issue.model_dump()]},
        },
        strict=True,
    )

    assert body.error.issues is not None


def test_conf_14_the_issue_code_literal_matches_the_shared_family_schema(
    family_root: Path,
):
    """The literal set and the shared schema enum must not drift apart."""

    schema = read(family_root, "schemas/error.schema.json")
    shared = set(schema["definitions"]["issue_code"]["enum"])

    assert set(get_args(IssueCode)) == shared
