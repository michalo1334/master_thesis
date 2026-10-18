import copy
import json
import math

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from evaluation_compute.api import app
from evaluation_compute.contracts.errors import ComparisonError
from evaluation_compute.contracts.request import ComparisonRequest
from evaluation_compute.contracts.result import ComparisonStatistics
from evaluation_compute.error_mapping import pydantic_error
from evaluation_compute.service import evidence_issues

CLIENT = TestClient(app, raise_server_exceptions=False)


@pytest.mark.parametrize(
    "fixture_name", ["crossed-small.request.json", "integer-number.request.json"]
)
def test_contract_01_valid_shared_requests(contracts_root, fixture_name):
    payload = json.loads((contracts_root / "valid" / fixture_name).read_text())
    assert ComparisonRequest.model_validate(payload, strict=True).schema_version == 1


def test_contract_02_valid_statistics(contracts_root):
    payload = json.loads((contracts_root / "valid" / "informative.statistics.json").read_text())
    assert (
        ComparisonStatistics.model_validate(payload, strict=True).assessment.status == "informative"
    )


@pytest.mark.parametrize("name", ["validation.error.json", "schema-validation.error.json"])
def test_contract_02b_valid_error_forms(contracts_root, name):
    payload = (contracts_root / "valid" / name).read_bytes()
    assert ComparisonError.model_validate_json(payload, strict=True).schema_version == 1


def test_contract_03_shared_invalid_examples(contracts_root):
    for request_path in sorted((contracts_root / "invalid").glob("*.request.json")):
        payload = json.loads(request_path.read_text())
        expected = json.loads(
            request_path.with_name(request_path.name.replace(".request", ".expected")).read_text()
        )
        try:
            request = ComparisonRequest.model_validate(payload, strict=True)
        except ValidationError as exc:
            actual = pydantic_error(exc)
            assert actual.error.code == "validation_failed"
            assert actual.error.issues is None
            assert actual.error.schema_errors
        else:
            issues = evidence_issues(request)
            assert [
                issue.model_dump(include={"code", "path", "details"}) for issue in issues
            ] == expected["issues"], request_path.name

        response = CLIENT.post(
            "/v1/comparisons/corrected-crossed-bootstrap",
            content=request_path.read_bytes(),
            headers={"content-type": "application/json"},
        )
        assert response.status_code == expected["http_status"], request_path.name


def test_contract_04_non_finite_python_values_are_rejected(valid_request):
    payload = copy.deepcopy(valid_request)
    payload["evidence"]["alternative"]["plans"][0]["mission_impacts"][0] = math.nan
    with pytest.raises(ValidationError):
        ComparisonRequest.model_validate(payload, strict=True)


def test_contract_05_boolean_number_is_rejected(valid_request):
    payload = copy.deepcopy(valid_request)
    payload["evidence"]["alternative"]["plans"][0]["mission_impacts"][0] = True
    with pytest.raises(ValidationError):
        ComparisonRequest.model_validate(payload, strict=True)


@pytest.mark.parametrize(
    ("model", "fixture_suffix"),
    [
        (ComparisonStatistics, ".statistics.json"),
        (ComparisonError, ".error.json"),
    ],
)
def test_contract_06_shared_invalid_response_examples(contracts_root, model, fixture_suffix):
    """CONTRACT-06: WHEN a shared response is invalid, Python SHALL reject it."""
    paths = sorted((contracts_root / "invalid").glob(f"*{fixture_suffix}"))
    required_names = {
        ".statistics.json": {
            "duplicate-warning.statistics.json",
            "missing-assessment.statistics.json",
            "schema-version-float.statistics.json",
        },
        ".error.json": {
            "detail-key-limit.error.json",
            "detail-list-limit.error.json",
            "message-max-length.error.json",
            "missing-version.error.json",
            "schema-version-float.error.json",
            "utf8-message-bytes.error.json",
        },
    }
    assert required_names[fixture_suffix] <= {path.name for path in paths}
    for path in paths:
        with pytest.raises(ValidationError):
            model.model_validate_json(path.read_bytes(), strict=True)


@pytest.mark.parametrize(
    ("model", "document"),
    [
        (ComparisonRequest, '{"schema_version":1.0}'),
        (ComparisonStatistics, '{"schema_version":1.0}'),
        (ComparisonError, '{"schema_version":1.0}'),
    ],
)
def test_contract_07_schema_version_requires_an_integer_json_token(model, document):
    """CONTRACT-07: WHEN version 1.0 is supplied, each native model SHALL reject it."""
    with pytest.raises(ValidationError):
        model.model_validate_json(document, strict=True)


@pytest.mark.parametrize(
    "path",
    [
        ("estimate", "value"),
        ("interval", "confidence_level"),
        ("interval", "lower"),
        ("interval", "upper"),
        ("test", "raw_p_value"),
    ],
)
def test_contract_08_statistics_numbers_must_be_finite(contracts_root, path):
    """CONTRACT-08: WHEN a response number is non-finite, Python SHALL reject it."""
    payload = json.loads((contracts_root / "valid" / "informative.statistics.json").read_text())
    payload[path[0]][path[1]] = math.inf
    with pytest.raises(ValidationError):
        ComparisonStatistics.model_validate(payload, strict=True)


def test_contract_09_error_message_uses_utf8_bytes(contracts_root):
    """CONTRACT-09: WHEN a message exceeds 256 UTF-8 bytes, Python SHALL reject it."""
    payload = json.loads((contracts_root / "valid" / "validation.error.json").read_text())
    payload["error"]["issues"][0]["message"] = "é" * 129
    with pytest.raises(ValidationError):
        ComparisonError.model_validate(payload, strict=True)


def test_contract_10_error_details_are_bounded(contracts_root):
    """CONTRACT-10: WHEN details exceed a key or list limit, Python SHALL reject them."""
    base = json.loads((contracts_root / "valid" / "validation.error.json").read_text())
    too_many_keys = copy.deepcopy(base)
    too_many_keys["error"]["issues"][0]["details"] = {f"key_{index}": index for index in range(17)}
    too_long_list = copy.deepcopy(base)
    too_long_list["error"]["issues"][0]["details"] = {"values": list(range(21))}
    too_many_message_bytes = copy.deepcopy(base)
    too_many_message_bytes["error"]["issues"][0]["message"] = "é" * 129

    for payload in [too_many_keys, too_long_list, too_many_message_bytes]:
        with pytest.raises(ValidationError):
            ComparisonError.model_validate(payload, strict=True)


def test_contract_11_schema_diagnostics_are_safe_and_bounded(valid_request):
    """SCHEMA-11: WHEN validation fails, diagnostics SHALL omit submitted values."""
    private_value = "private-value-that-must-not-leak"
    payload = copy.deepcopy(valid_request)
    payload["unknown"] = private_value

    with pytest.raises(ValidationError) as captured:
        ComparisonRequest.model_validate(payload, strict=True)

    error = pydantic_error(captured.value)
    serialized = error.model_dump_json(exclude_none=True)
    assert error.error.issues is None
    assert error.error.schema_errors
    assert private_value not in serialized
    assert sum(1 + len(item.causes) for item in error.error.schema_errors) <= 50


def test_contract_12_error_forms_are_exclusive(contracts_root):
    """SCHEMA-12: WHEN both public error forms are present, Python SHALL reject them."""
    payload = json.loads((contracts_root / "valid" / "validation.error.json").read_text())
    payload["error"]["schema_errors"] = [
        {"message": "Invalid value.", "path": ["value"], "causes": []}
    ]
    with pytest.raises(ValidationError):
        ComparisonError.model_validate(payload, strict=True)
