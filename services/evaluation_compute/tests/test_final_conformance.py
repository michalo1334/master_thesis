"""Conformance tests for the checked-in Final examples.

The generator writes the Final fixtures from a running service. Elixir treats
those files as the expected wire values. These tests hold Python to the same
files, so a change in either runtime cannot pass unnoticed.

The tests use the existing comparison and Holm code. They do not add an
endpoint, a model, or a dependency.
"""

import json
from pathlib import Path
from typing import Any

import pytest

from evaluation_compute.contracts.family import HolmRequest
from evaluation_compute.contracts.request import ComparisonRequest
from evaluation_compute.holm import adjust_holm, holm_issues
from evaluation_compute.service import compare, evidence_issues

FINAL_ROOT = Path(__file__).resolve().parents[3] / "contracts" / "evaluation" / "final" / "v1"
MEMBER_BYTE_CAP = 1_048_576


def read(relative_path: str) -> Any:
    return json.loads((FINAL_ROOT / relative_path).read_text())


def member_positions(kind: str) -> list[int]:
    return sorted(int(path.stem) for path in (FINAL_ROOT / "valid" / kind).glob("*.json"))


def identity_key(identity: dict) -> tuple[str, int, str, str, str]:
    return (
        identity["tier"],
        identity["budget"],
        identity["alternative"],
        identity["reference"],
        identity["outcome"],
    )


def test_final_01_one_member_request_and_one_response_exist_for_every_declaration():
    request = read("valid/final-small.request.json")
    declared = len(request["expected_comparisons"])

    assert member_positions("member-requests") == list(range(declared))
    assert member_positions("member-responses") == list(range(declared))


def test_final_02_each_member_request_follows_the_declared_evidence_and_seeds():
    snapshot = read("valid/final-small.snapshot.json")["payload"]["comparisons"]
    request = read("valid/final-small.request.json")

    for position in range(len(request["expected_comparisons"])):
        member_request = read(f"valid/member-requests/{position}.json")

        assert member_request["evidence"] == snapshot[position]["evidence"]
        assert member_request["resampling"] == {
            "seed": request["comparison_seeds"][position],
            "replicates": request["analysis"]["bootstrap_replicates"],
        }
        assert member_request["interval"] == {
            "confidence_level": request["analysis"]["confidence_level"]
        }
        assert member_request["test"] == {"alternative": request["analysis"]["test_alternative"]}


def test_final_03_each_checked_in_member_response_is_reproducible():
    """Every member statistic must follow from the checked-in member request."""

    for position in member_positions("member-requests"):
        member_request = read(f"valid/member-requests/{position}.json")
        checked_in = read(f"valid/member-responses/{position}.json")

        parsed = ComparisonRequest.model_validate(member_request, strict=True)

        assert evidence_issues(parsed) == []
        assert compare(parsed).model_dump(mode="json") == checked_in


def test_final_04_the_checked_in_correction_request_follows_the_member_responses():
    request = read("valid/final-small.request.json")
    correction = read("valid/final-small.correction-request.json")

    raw = [
        read(f"valid/member-responses/{position}.json")["test"]["raw_p_value"]
        for position in member_positions("member-responses")
    ]

    assert correction["expected_comparisons"] == request["expected_comparisons"]
    assert len(correction["raw_results"]) == len(request["expected_comparisons"])
    assert [row["identity"] for row in correction["raw_results"]] == request["expected_comparisons"]
    assert [row["raw_p_value"] for row in correction["raw_results"]] == raw
    assert correction["family_id"] == request["family_id"]
    assert correction["method"] == request["method"]
    assert correction["alpha"] == request["analysis"]["alpha"]


def test_final_05_the_checked_in_correction_response_is_reproducible():
    correction_request = read("valid/final-small.correction-request.json")
    checked_in = read("valid/final-small.correction-response.json")

    request = HolmRequest.model_validate(correction_request, strict=True)

    assert holm_issues(request) == []
    assert adjust_holm(request).model_dump(mode="json") == checked_in


def test_final_06_the_declared_order_is_the_correction_order():
    request = read("valid/final-small.request.json")
    response = read("valid/final-small.correction-response.json")

    declared = [identity_key(identity) for identity in request["expected_comparisons"]]
    stored = [identity_key(row["identity"]) for row in response["results"]]

    assert stored == declared


@pytest.mark.parametrize("position", member_positions("member-requests"))
def test_final_07_a_member_request_fits_the_service_byte_cap(position: int):
    """The generated request must stay under the member byte cap.

    The Elixir side enforces the same cap before a run starts. A fixture that
    exceeded it could only pass a test that never sends the request.
    """

    body = (FINAL_ROOT / "valid" / "member-requests" / f"{position}.json").read_bytes()

    assert len(body) <= MEMBER_BYTE_CAP
