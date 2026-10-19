import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from evaluation_compute import api
from evaluation_compute.contracts.family import FamilyIdentity, HolmRequest, identity_key
from evaluation_compute.holm import adjust_holm, holm_issues

client = TestClient(api.app)
PATH = "/v1/families/holm"


def identity(name: str, budget: int = 4) -> dict[str, object]:
    return {
        "tier": name,
        "budget": budget,
        "alternative": "hybrid_planner",
        "reference": "cvss",
        "outcome": "mission_impact",
    }


def request_body(raw_p_values: list[float], **overrides: object) -> dict[str, object]:
    body: dict[str, object] = {
        "schema_version": 1,
        "family_id": "reference-family",
        "method": "holm",
        "alpha": 0.05,
        "expected_comparisons": [identity(f"tier-{index}") for index in range(len(raw_p_values))],
        "raw_results": [
            {"identity": identity(f"tier-{index}"), "raw_p_value": raw}
            for index, raw in enumerate(raw_p_values)
        ],
    }
    body.update(overrides)
    return body


def test_fam_01_valid_request_keeps_declared_order():
    """FAM-01: WHEN the family is valid, the response SHALL keep declared order."""

    request = HolmRequest.model_validate(request_body([0.01, 0.04, 0.03, 0.005]), strict=True)

    response = adjust_holm(request)

    assert response.family_size == 4
    assert [row.identity.tier for row in response.results] == [
        "tier-0",
        "tier-1",
        "tier-2",
        "tier-3",
    ]


def test_fam_02_reference_vector_matches_hand_calculation():
    """FAM-02: WHEN raw p-values are known, the adjustment SHALL match Holm's method."""

    request = HolmRequest.model_validate(request_body([0.01, 0.04, 0.03, 0.005]), strict=True)

    response = adjust_holm(request)

    assert [row.raw_p_value for row in response.results] == [0.01, 0.04, 0.03, 0.005]
    assert [row.adjusted_p_value for row in response.results] == [0.03, 0.06, 0.06, 0.02]
    assert [row.reject_null for row in response.results] == [True, False, False, True]


def test_fam_03_ties_use_declared_order_as_the_tie_break():
    """FAM-03: WHEN raw p-values tie, the adjustment SHALL break ties by position."""

    response = adjust_holm(HolmRequest.model_validate(request_body([0.02, 0.02, 0.5]), strict=True))

    assert [row.adjusted_p_value for row in response.results] == [0.06, 0.06, 0.5]


def test_fam_04_adjusted_p_values_never_exceed_one():
    """FAM-04: WHEN the product exceeds one, the adjustment SHALL clamp to one."""

    response = adjust_holm(HolmRequest.model_validate(request_body([0.9, 0.95]), strict=True))

    assert [row.adjusted_p_value for row in response.results] == [1.0, 1.0]
    assert [row.reject_null for row in response.results] == [False, False]


def test_fam_05_adjustment_is_monotone_in_raw_p_value():
    """FAM-05: WHEN raw p-values increase, adjusted p-values SHALL not decrease."""

    response = adjust_holm(
        HolmRequest.model_validate(request_body([0.001, 0.2, 0.04, 0.03]), strict=True)
    )

    ordered = sorted(response.results, key=lambda row: row.raw_p_value)
    adjusted = [row.adjusted_p_value for row in ordered]

    assert adjusted == sorted(adjusted)


def test_fam_06_supplied_order_does_not_change_the_result():
    """FAM-06: WHEN raw results are permuted, the adjustment SHALL be identical."""

    body = request_body([0.01, 0.04, 0.03, 0.005])
    permuted = dict(body)
    permuted["raw_results"] = list(reversed(body["raw_results"]))

    first = adjust_holm(HolmRequest.model_validate(body, strict=True))
    second = adjust_holm(HolmRequest.model_validate(permuted, strict=True))

    assert first == second


def test_fam_15_decimal_boundary_keeps_the_decision():
    """FAM-15: WHEN the exact product meets alpha, every member SHALL reject.

    Three raw p-values of 0.1 and alpha of 0.3 give an exact product of 0.3.
    Binary floating point represents that product as 0.30000000000000004, so a
    double-based rule would report no rejection.
    """

    body = request_body([0.1, 0.1, 0.1], alpha=0.3)

    response = adjust_holm(HolmRequest.model_validate(body, strict=True))

    assert [row.adjusted_p_value for row in response.results] == [0.3, 0.3, 0.3]
    assert [row.reject_null for row in response.results] == [True, True, True]


def test_fam_16_boundary_decision_survives_double_comparison():
    """FAM-16: WHEN a reader compares the emitted number, the decision SHALL match.

    The emitted value is a binary float. A reader that applies ``value <= alpha``
    to the emitted number and to alpha must reach the same decision.
    """

    cases = [
        ([0.1, 0.1, 0.1], 0.3),
        ([0.1, 0.2, 0.3], 0.9),
        ([0.2, 0.2], 0.4),
        ([0.7, 0.9], 0.7),
        ([0.05, 0.04, 0.03, 0.02, 0.01], 0.25),
    ]

    for raws, alpha in cases:
        response = adjust_holm(
            HolmRequest.model_validate(request_body(raws, alpha=alpha), strict=True)
        )

        for row in response.results:
            assert (row.adjusted_p_value <= response.alpha) == row.reject_null, (raws, alpha)


def test_fam_17_cap_and_monotonicity_stay_exact_at_boundaries():
    """FAM-17: WHEN the product passes one, the cap SHALL not change the decision."""

    body = request_body([0.5, 0.5, 0.5], alpha=0.05)

    response = adjust_holm(HolmRequest.model_validate(body, strict=True))

    assert [row.adjusted_p_value for row in response.results] == [1.0, 1.0, 1.0]
    assert [row.reject_null for row in response.results] == [False, False, False]

    mixed = adjust_holm(
        HolmRequest.model_validate(request_body([0.1, 0.1, 0.9], alpha=0.3), strict=True)
    )

    assert [row.adjusted_p_value for row in mixed.results] == [0.3, 0.3, 0.9]
    assert [row.reject_null for row in mixed.results] == [True, True, False]

    capped = adjust_holm(
        HolmRequest.model_validate(request_body([0.4, 0.5, 0.6], alpha=0.9), strict=True)
    )

    assert [row.adjusted_p_value for row in capped.results] == [1.0, 1.0, 1.0]
    assert [row.reject_null for row in capped.results] == [False, False, False]


def test_fam_07_unknown_field_is_rejected():
    """FAM-07: WHEN a request has an unknown field, the contract SHALL reject it."""

    body = request_body([0.01], unexpected="value")

    with pytest.raises(ValidationError):
        HolmRequest.model_validate(body, strict=True)


def test_fam_08_string_alpha_is_not_coerced():
    """FAM-08: WHEN alpha is a string, the contract SHALL reject it."""

    with pytest.raises(ValidationError):
        HolmRequest.model_validate(request_body([0.01], alpha="0.05"), strict=True)


@pytest.mark.parametrize("raw_p_value", [-0.01, 1.01, "0.5", True])
def test_fam_09_out_of_range_raw_p_value_is_rejected(raw_p_value):
    """FAM-09: WHEN a raw p-value is outside [0, 1], the contract SHALL reject it."""

    body = request_body([0.01])
    body["raw_results"] = [{"identity": identity("tier-0"), "raw_p_value": raw_p_value}]

    with pytest.raises(ValidationError):
        HolmRequest.model_validate(body, strict=True)


def test_fam_10_duplicate_expected_identity_is_reported():
    """FAM-10: WHEN a declared identity repeats, validation SHALL report it."""

    body = request_body([0.01, 0.02])
    body["expected_comparisons"] = [identity("tier-0"), identity("tier-0")]

    issues = holm_issues(HolmRequest.model_validate(body, strict=True))

    assert "duplicate_expected_identity" in [issue.code for issue in issues]


def test_fam_11_missing_comparison_is_reported():
    """FAM-11: WHEN a declared identity has no raw p-value, validation SHALL report it."""

    body = request_body([0.01, 0.02])
    body["raw_results"] = [{"identity": identity("tier-0"), "raw_p_value": 0.01}]

    issues = holm_issues(HolmRequest.model_validate(body, strict=True))

    assert [issue.code for issue in issues] == ["missing_comparison"]
    assert issues[0].path == ["expected_comparisons", 1]


def test_fam_12_unexpected_comparison_is_reported():
    """FAM-12: WHEN an undeclared identity supplies a p-value, validation SHALL report it."""

    body = request_body([0.01])
    body["raw_results"] = [{"identity": identity("tier-9"), "raw_p_value": 0.01}]

    issues = holm_issues(HolmRequest.model_validate(body, strict=True))

    assert [issue.code for issue in issues] == ["missing_comparison", "unexpected_comparison"]


def test_fam_13_identity_key_ignores_field_order():
    """FAM-13: WHEN identity fields are reordered, the typed key SHALL stay equal."""

    first = FamilyIdentity.model_validate(identity("tier-0"), strict=True)
    reordered = FamilyIdentity.model_validate(
        {
            "outcome": "mission_impact",
            "reference": "cvss",
            "alternative": "hybrid_planner",
            "budget": 4,
            "tier": "tier-0",
        },
        strict=True,
    )

    assert identity_key(first) == identity_key(reordered)


def test_fam_14_identity_key_separates_different_budgets():
    """FAM-14: WHEN two identities differ in one field, their keys SHALL differ."""

    first = FamilyIdentity.model_validate(identity("core", budget=4), strict=True)
    second = FamilyIdentity.model_validate(identity("core", budget=6), strict=True)

    assert identity_key(first) != identity_key(second)


@pytest.mark.parametrize(
    ("body_change", "status", "code"),
    [
        ({"unexpected": "value"}, 422, "validation_failed"),
        ({"alpha": 1.0}, 422, "validation_failed"),
        ({"method": "bonferroni"}, 422, "validation_failed"),
        ({"schema_version": 2}, 422, "validation_failed"),
    ],
)
def test_api_fam_01_invalid_request_is_typed_422(body_change, status, code):
    """API-FAM-01: WHEN the family request is invalid, the API SHALL return a typed 422."""

    response = client.post(PATH, json={**request_body([0.01]), **body_change})

    assert response.status_code == status
    assert response.json()["error"]["code"] == code


def test_api_fam_02_valid_request_returns_rows_in_declared_order():
    """API-FAM-02: WHEN the family is valid, the API SHALL return one row per member."""

    response = client.post(PATH, json=request_body([0.01, 0.04, 0.03, 0.005]))

    assert response.status_code == 200
    body = response.json()
    assert body["method"] == "holm"
    assert body["family_size"] == 4
    assert [row["identity"]["tier"] for row in body["results"]] == [
        "tier-0",
        "tier-1",
        "tier-2",
        "tier-3",
    ]
    assert [row["adjusted_p_value"] for row in body["results"]] == [0.03, 0.06, 0.06, 0.02]


def test_api_fam_03_missing_comparison_is_typed_422():
    """API-FAM-03: WHEN a comparison is missing, the API SHALL return a typed issue."""

    body = request_body([0.01, 0.02])
    body["raw_results"] = [{"identity": identity("tier-0"), "raw_p_value": 0.01}]

    response = client.post(PATH, json=body)

    assert response.status_code == 422
    assert [issue["code"] for issue in response.json()["error"]["issues"]] == ["missing_comparison"]


def test_api_fam_04_response_repeats_request_metadata():
    """API-FAM-04: WHEN the correction succeeds, the response SHALL echo family metadata."""

    response = client.post(
        PATH,
        json=request_body([0.01], family_id="echoed-family", alpha=0.01),
    )

    body = response.json()
    assert body["family_id"] == "echoed-family"
    assert body["alpha"] == 0.01
    assert body["schema_version"] == 1
    assert body["results"][0]["reject_null"] is True


def test_api_fam_05_content_type_is_enforced():
    """API-FAM-05: WHEN the content type is not JSON, the API SHALL return 415."""

    response = client.post(PATH, content=b"{}", headers={"content-type": "text/plain"})

    assert response.status_code == 415
    assert response.json()["error"]["code"] == "unsupported_media_type"


def test_api_fam_06_invalid_json_is_typed_400():
    """API-FAM-06: WHEN the body is not JSON, the API SHALL return a typed 400."""

    response = client.post(PATH, content=b"{", headers={"content-type": "application/json"})

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_json"


def test_api_fam_07_decimal_boundary_over_http():
    """API-FAM-07: WHEN the exact product meets alpha, the API SHALL reject.

    This is the HTTP regression for the reviewed defect. The response must
    carry 0.3 and a true decision for all three members.
    """

    response = client.post(PATH, json=request_body([0.1, 0.1, 0.1], alpha=0.3))

    assert response.status_code == 200
    results = response.json()["results"]
    assert [row["adjusted_p_value"] for row in results] == [0.3, 0.3, 0.3]
    assert [row["reject_null"] for row in results] == [True, True, True]
    assert "0.30000000000000004" not in response.text
