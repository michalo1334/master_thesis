from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StrictInt

from .types import JsonFiniteNumber


class ResamplingSpec(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    seed: Annotated[StrictInt, Field(ge=0)]
    replicates: Annotated[StrictInt, Field(gt=0)]


class IntervalSpec(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    confidence_level: Annotated[JsonFiniteNumber, Field(gt=0, lt=1)]


class TestSpec(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    alternative: Literal["two_sided"]
