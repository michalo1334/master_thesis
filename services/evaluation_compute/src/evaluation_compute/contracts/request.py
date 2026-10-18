from pydantic import BaseModel, ConfigDict

from .evidence import Evidence
from .specs import IntervalSpec, ResamplingSpec, TestSpec
from .types import StrictSchemaVersion


class ComparisonRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    schema_version: StrictSchemaVersion
    evidence: Evidence
    resampling: ResamplingSpec
    interval: IntervalSpec
    test: TestSpec
