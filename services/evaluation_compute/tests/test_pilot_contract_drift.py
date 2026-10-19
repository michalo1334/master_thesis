import json
from pathlib import Path

from evaluation_compute.contracts.errors import ErrorCode
from evaluation_compute.contracts.pilot import PilotIssueCode

# Targeted drift checks for definitions that must agree because they share one
# meaning. These tests are not a generic schema framework. Intentional
# differences stay explicit and documented.

SCHEMAS = (
    Path(__file__).resolve().parents[3]
    / "contracts"
    / "evaluation"
    / "pilot"
    / "v1"
    / "schemas"
)

CONTRACTS = ("snapshot", "request", "candidate_request", "candidate_response", "result")


def schema(name: str) -> dict:
    return json.loads((SCHEMAS / f"{name}.schema.json").read_text())


def test_shared_identifier_and_identity_definitions_agree():
    base = schema("snapshot")["definitions"]

    for definition in ("uuid", "identifier", "identity"):
        for contract in CONTRACTS:
            assert schema(contract)["definitions"][definition] == base[definition], (
                contract,
                definition,
            )


def test_snapshot_and_candidate_request_evidence_definitions_agree():
    snapshot = schema("snapshot")["definitions"]
    candidate_request = schema("candidate_request")["definitions"]

    for definition in ("evidence", "alternative_side", "reference_side", "plan"):
        assert candidate_request[definition] == snapshot[definition], definition


def test_candidate_request_and_candidate_response_definitions_agree():
    request = schema("candidate_request")["definitions"]
    response = schema("candidate_response")["definitions"]

    assert response["candidate"] == request["candidate"]
    assert response["identity"] == request["identity"]


def test_request_and_result_shared_setting_definitions_agree():
    request = schema("request")["definitions"]
    result = schema("result")["definitions"]

    for definition in ("pilot_sampling", "precision", "selection"):
        assert result[definition] == request[definition], definition


def test_candidate_grid_keeps_only_the_documented_unique_items_difference():
    request = schema("request")["definitions"]["candidate_grid"]
    result = schema("result")["definitions"]["candidate_grid"]

    for field in ("plan_count_candidates", "attacks_per_plan_candidates"):
        request_items = request["properties"][field]
        result_items = result["properties"][field]

        assert request_items.get("uniqueItems") is None
        assert result_items["uniqueItems"] is True

        without_unique = {key: value for key, value in result_items.items() if key != "uniqueItems"}
        assert without_unique == request_items


def test_python_pilot_issue_codes_match_the_error_schema():
    schema_codes = schema("error")["definitions"]["issue_code"]["enum"]

    assert set(PilotIssueCode.__args__) == set(schema_codes)
    assert len(PilotIssueCode.__args__) == len(set(PilotIssueCode.__args__))


def test_python_error_codes_match_the_error_schema():
    schema_codes = schema("error")["definitions"]["error_code"]["enum"]

    assert set(ErrorCode.__args__) == set(schema_codes)
