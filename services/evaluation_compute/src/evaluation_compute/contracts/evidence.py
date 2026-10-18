from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StrictInt, StringConstraints

from .types import IDENTIFIER_PATTERN, JsonFiniteNumber

Identifier = Annotated[
    str,
    StringConstraints(strict=True, min_length=1, max_length=128, pattern=IDENTIFIER_PATTERN),
]


class PlanEvidence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    id: Identifier
    mission_impacts: Annotated[list[JsonFiniteNumber], Field(min_length=1)]


class AlternativeSide(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    strategy: Identifier
    plans: Annotated[list[PlanEvidence], Field(min_length=5)]


class ReferenceSide(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    strategy: Literal["cvss"]
    plans: Annotated[list[PlanEvidence], Field(min_length=5)]


class Evidence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    outcome: Literal["mission_impact"]
    attack_seeds: Annotated[list[Annotated[StrictInt, Field(ge=0)]], Field(min_length=10)]
    alternative: AlternativeSide
    reference: ReferenceSide
