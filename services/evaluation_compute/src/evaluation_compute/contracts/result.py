from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .types import JsonFiniteNumber, StrictSchemaVersion


class Estimate(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    contrast: Literal["alternative_minus_reference"]
    value: JsonFiniteNumber


class ConfidenceInterval(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    confidence_level: Annotated[JsonFiniteNumber, Field(gt=0, lt=1)]
    lower: JsonFiniteNumber
    upper: JsonFiniteNumber


class TestResult(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    method: Literal["centered_crossed_bootstrap"]
    alternative: Literal["two_sided"]
    raw_p_value: Annotated[JsonFiniteNumber, Field(ge=0, le=1)]


class Assessment(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    status: Literal["informative", "non_informative"]
    warnings: list[Literal["zero_width_interval"]]

    @field_validator("warnings")
    @classmethod
    def warnings_are_unique(cls, value: list[str]) -> list[str]:
        if len(value) != len(set(value)):
            raise ValueError("assessment warnings must be unique")
        return value


class ComparisonStatistics(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schema_version: StrictSchemaVersion
    method: Literal["corrected_crossed_bootstrap_v1"]
    estimate: Estimate
    interval: ConfidenceInterval
    test: TestResult
    assessment: Assessment
