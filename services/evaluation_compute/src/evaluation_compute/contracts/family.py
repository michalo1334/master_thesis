from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt

from .evidence import Identifier
from .types import JsonFiniteNumber, StrictSchemaVersion

# Family and Holm wire contracts.
#
# They are separate from the comparison contracts: one contract never guesses
# which shape it received. Unknown fields are forbidden and numeric values are
# strict.


class FamilyIdentity(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    tier: Identifier
    budget: Annotated[StrictInt, Field(gt=0)]
    alternative: Identifier
    reference: Identifier
    outcome: Identifier


class HolmMember(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    identity: FamilyIdentity
    raw_p_value: Annotated[JsonFiniteNumber, Field(ge=0, le=1)]


class HolmRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schema_version: StrictSchemaVersion
    family_id: Identifier
    method: Literal["holm"]
    alpha: Annotated[JsonFiniteNumber, Field(gt=0, lt=1)]
    expected_comparisons: Annotated[list[FamilyIdentity], Field(min_length=1)]
    raw_results: Annotated[list[HolmMember], Field(min_length=1)]


class HolmAdjustedMember(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    identity: FamilyIdentity
    raw_p_value: Annotated[JsonFiniteNumber, Field(ge=0, le=1)]
    adjusted_p_value: Annotated[JsonFiniteNumber, Field(ge=0, le=1)]
    reject_null: StrictBool


class HolmResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schema_version: StrictSchemaVersion
    family_id: Identifier
    method: Literal["holm"]
    alpha: Annotated[JsonFiniteNumber, Field(gt=0, lt=1)]
    family_size: Annotated[StrictInt, Field(gt=0)]
    results: Annotated[list[HolmAdjustedMember], Field(min_length=1)]


def identity_key(identity: FamilyIdentity) -> tuple[str, int, str, str, str]:
    """Typed identity key. JSON object-field order never affects equality."""

    return (
        identity.tier,
        identity.budget,
        identity.alternative,
        identity.reference,
        identity.outcome,
    )
