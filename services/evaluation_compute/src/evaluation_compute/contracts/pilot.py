from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    StrictInt,
    field_validator,
    model_validator,
)

from .errors import ErrorCode, SafeList, SafeScalar, SchemaDiagnostic
from .evidence import Evidence, Identifier
from .family import FamilyIdentity
from .types import JsonFiniteNumber, StrictSchemaVersion

# Precision Pilot wire contracts.
#
# They are separate from the comparison and family contracts: one contract
# never guesses which shape it received. Unknown fields are forbidden, numeric
# values are strict, and every scientific value is declared by the caller.

PilotIssueCode = Literal[
    "invalid_json",
    "request_too_large",
    "unsupported_media_type",
    "required_field_missing",
    "unknown_field",
    "invalid_type",
    "unsupported_schema_version",
    "unsupported_outcome",
    "unsupported_alternative_strategy",
    "unsupported_reference",
    "unsupported_test_alternative",
    "invalid_identifier",
    "invalid_analysis_setting",
    "insufficient_plan_count",
    "insufficient_attack_count",
    "duplicate_plan_id",
    "duplicate_attack_seed",
    "attack_column_count_mismatch",
    "non_finite_mission_impact",
    "duplicate_expected_identity",
    "duplicate_comparison_identity",
    "missing_comparison",
    "unexpected_comparison",
    "identity_mismatch",
    "incomplete_family",
    "invalid_comparison_request",
    "invalid_correction",
    "family_result_invalid",
    "changed_family_member",
    "invalid_response_contract",
    "compute_unavailable",
    "compute_failed",
    "workflow_failed",
    "missing_identity",
    "duplicate_comparison",
    "non_consecutive_position",
    "snapshot_not_found",
    "snapshot_phase_mismatch",
    "changed_snapshot",
    "duplicate_candidate_id",
    "duplicate_candidate_size",
    "candidate_exceeds_plan_rows",
    "candidate_exceeds_attack_columns",
    "incomplete_pilot",
    "duplicate_candidate_result",
    "unexpected_candidate_result",
    "changed_candidate_result",
    "invalid_candidate_result",
    "configuration_invalid",
    "no_passing_candidate",
]

PilotPathSegment = Annotated[str, Field(max_length=256)] | int
PilotDetailKey = Annotated[str, Field(max_length=64)]


class PilotIssue(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    code: PilotIssueCode
    path: Annotated[list[PilotPathSegment], Field(max_length=32)]
    message: str = Field(min_length=1, max_length=256)
    details: Annotated[dict[PilotDetailKey, SafeScalar | SafeList], Field(max_length=16)]

    @field_validator("message")
    @classmethod
    def message_has_bounded_utf8_size(cls, value: str) -> str:
        if len(value.encode("utf-8")) > 256:
            raise ValueError("issue messages must not exceed 256 UTF-8 bytes")
        return value


class PilotErrorBody(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    code: ErrorCode
    issues: list[PilotIssue] | None = Field(default=None, min_length=1, max_length=50)
    schema_errors: list[SchemaDiagnostic] | None = Field(default=None, min_length=1, max_length=50)

    @model_validator(mode="after")
    def one_bounded_error_form(self) -> "PilotErrorBody":
        if (self.issues is None) == (self.schema_errors is None):
            raise ValueError("exactly one error form is required")
        if self.schema_errors is not None:
            if self.code != "validation_failed":
                raise ValueError("schema diagnostics require validation_failed")
            if _diagnostic_count(self.schema_errors) > 50:
                raise ValueError("schema diagnostics must contain at most 50 total entries")
        return self


class PilotError(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schema_version: StrictSchemaVersion
    error: PilotErrorBody


def _diagnostic_count(diagnostics: list[SchemaDiagnostic]) -> int:
    return sum(1 + _diagnostic_count(diagnostic.causes) for diagnostic in diagnostics)


class Candidate(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    id: Identifier
    plan_count: Annotated[StrictInt, Field(ge=5)]
    attacks_per_plan: Annotated[StrictInt, Field(ge=10)]


class CandidateComparisonRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schema_version: StrictSchemaVersion
    method: Literal["precision_pilot_candidate_v1"]
    pilot_id: Identifier
    study_revision_id: UUID
    family_id: Identifier
    snapshot_id: UUID
    candidate_position: Annotated[StrictInt, Field(ge=0)]
    comparison_position: Annotated[StrictInt, Field(ge=0)]
    identity: FamilyIdentity
    candidate: Candidate
    evidence: Evidence
    outer_subsamples: Annotated[StrictInt, Field(gt=0)]
    stream_seed: Annotated[StrictInt, Field(ge=0)]
    guard_quantile: Annotated[JsonFiniteNumber, Field(gt=0, lt=1)]
    target_half_width: Annotated[JsonFiniteNumber, Field(gt=0)]
    confidence_level: Annotated[JsonFiniteNumber, Field(gt=0, lt=1)]
    bootstrap_replicates: Annotated[StrictInt, Field(gt=0)]


class CandidateComparisonResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schema_version: StrictSchemaVersion
    method: Literal["precision_pilot_candidate_v1"]
    pilot_id: Identifier
    study_revision_id: UUID
    family_id: Identifier
    snapshot_id: UUID
    candidate_position: Annotated[StrictInt, Field(ge=0)]
    comparison_position: Annotated[StrictInt, Field(ge=0)]
    identity: FamilyIdentity
    candidate: Candidate
    outer_subsamples: Annotated[StrictInt, Field(gt=0)]
    stream_seed: Annotated[StrictInt, Field(ge=0)]
    guard_quantile: Annotated[JsonFiniteNumber, Field(gt=0, lt=1)]
    target_half_width: Annotated[JsonFiniteNumber, Field(gt=0)]
    confidence_level: Annotated[JsonFiniteNumber, Field(gt=0, lt=1)]
    bootstrap_replicates: Annotated[StrictInt, Field(gt=0)]
    guarded_half_width: Annotated[JsonFiniteNumber, Field(ge=0)]
    informative: StrictBool
    passes: StrictBool
