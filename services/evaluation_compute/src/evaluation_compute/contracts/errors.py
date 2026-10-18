from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .types import JsonFiniteNumber, StrictSchemaVersion

ErrorCode = Literal[
    "validation_failed",
    "invalid_json",
    "request_too_large",
    "unsupported_media_type",
    "invalid_response_contract",
    "compute_unavailable",
    "compute_failed",
    "workflow_failed",
]

IssueCode = Literal[
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
    "invalid_response_contract",
    "compute_unavailable",
    "compute_failed",
    "workflow_failed",
]


SafeString = Annotated[str, Field(max_length=256)]
SafeScalar = SafeString | bool | None | JsonFiniteNumber
SafeList = Annotated[list[SafeScalar], Field(max_length=20)]
DetailKey = Annotated[str, Field(max_length=64)]
PathSegment = Annotated[str, Field(max_length=256)] | int
DiagnosticPathSegment = Annotated[str, Field(max_length=256)] | int
DiagnosticPath = (
    Annotated[str, Field(max_length=256)]
    | Annotated[list[DiagnosticPathSegment], Field(max_length=32)]
)


class ComparisonIssue(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    code: IssueCode
    path: Annotated[list[PathSegment], Field(max_length=32)]
    message: str = Field(min_length=1, max_length=256)
    details: Annotated[dict[DetailKey, SafeScalar | SafeList], Field(max_length=16)]

    @field_validator("message")
    @classmethod
    def message_has_bounded_utf8_size(cls, value: str) -> str:
        if len(value.encode("utf-8")) > 256:
            raise ValueError("issue messages must not exceed 256 UTF-8 bytes")
        return value


class SchemaDiagnostic(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    message: str = Field(max_length=256)
    path: DiagnosticPath
    causes: list["SchemaDiagnostic"] = Field(default_factory=list, max_length=50)

    @field_validator("message")
    @classmethod
    def bounded_message(cls, value: str) -> str:
        if len(value.encode("utf-8")) > 256:
            raise ValueError("diagnostic messages must not exceed 256 UTF-8 bytes")
        return value

    @field_validator("path")
    @classmethod
    def bounded_path_strings(cls, value: DiagnosticPath) -> DiagnosticPath:
        strings = (
            [value] if isinstance(value, str) else [item for item in value if isinstance(item, str)]
        )
        if any(len(item.encode("utf-8")) > 256 for item in strings):
            raise ValueError("diagnostic paths must not exceed 256 UTF-8 bytes per string")
        return value


class ErrorBody(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    code: ErrorCode
    issues: list[ComparisonIssue] | None = Field(default=None, min_length=1, max_length=50)
    schema_errors: list[SchemaDiagnostic] | None = Field(default=None, min_length=1, max_length=50)

    @model_validator(mode="after")
    def one_bounded_error_form(self) -> "ErrorBody":
        if (self.issues is None) == (self.schema_errors is None):
            raise ValueError("exactly one error form is required")
        if self.schema_errors is not None:
            if self.code != "validation_failed":
                raise ValueError("schema diagnostics require validation_failed")
            if _diagnostic_count(self.schema_errors) > 50:
                raise ValueError("schema diagnostics must contain at most 50 total entries")
        return self


def _diagnostic_count(diagnostics: list[SchemaDiagnostic]) -> int:
    return sum(1 + _diagnostic_count(diagnostic.causes) for diagnostic in diagnostics)


class ComparisonError(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schema_version: StrictSchemaVersion
    error: ErrorBody
