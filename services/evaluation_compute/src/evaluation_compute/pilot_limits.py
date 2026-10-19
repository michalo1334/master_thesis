import os
from collections.abc import Mapping

from pydantic import BaseModel, ConfigDict, Field

from .contracts.pilot import CandidateComparisonRequest, PilotIssue

# Deployment resource caps for the independently callable Pilot endpoint.
#
# The caps are deployment configuration, not scientific settings. The Stage 2
# and Stage 3 routes never read them, so the service starts and serves those
# routes when the Pilot caps are absent. A Pilot request fails safely with one
# bounded configuration error in that case.

MAX_LIMIT_DIGITS = 15
"""Longest accepted cap text. Fifteen digits stay exact in a JSON number."""

MAX_LIMIT_VALUE = 999_999_999_999_999
"""Largest accepted cap. It stays exact in every JSON number reader."""


class PilotLimits(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    max_outer_subsamples: int = Field(gt=0, le=MAX_LIMIT_VALUE)
    max_bootstrap_replicates: int = Field(gt=0, le=MAX_LIMIT_VALUE)
    max_combined_bootstrap_work: int = Field(gt=0, le=MAX_LIMIT_VALUE)


class PilotLimitsUnavailable(Exception):
    """The Pilot compute limits are missing or malformed."""


_ENVIRONMENT = {
    "max_outer_subsamples": "EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES",
    "max_bootstrap_replicates": "EVALUATION_PILOT_MAX_BOOTSTRAP_REPLICATES",
    "max_combined_bootstrap_work": "EVALUATION_PILOT_MAX_COMBINED_BOOTSTRAP_WORK",
}


def load_pilot_limits(environ: Mapping[str, str] | None = None) -> PilotLimits:
    """Read all three required Pilot caps from the process environment."""

    source = os.environ if environ is None else environ
    values = {}

    for field, name in _ENVIRONMENT.items():
        raw = source.get(name)
        if raw is None:
            raise PilotLimitsUnavailable(f"{name} is required for Pilot requests.")
        values[field] = _positive_integer(raw, name)

    return PilotLimits(**values)


def resource_issues(
    request: CandidateComparisonRequest, limits: PilotLimits
) -> list[PilotIssue]:
    """Return bounded resource issues before any stream or array allocation.

    A diagnostic never repeats a request value and never builds the product of
    two request values. It carries constant text, a field path, and the safe
    configured cap only, so an arbitrarily large request integer cannot reach
    a bounded JSON number.
    """

    issues: list[PilotIssue] = []

    if request.outer_subsamples > limits.max_outer_subsamples:
        issues.append(
            _issue(
                ["outer_subsamples"],
                "The outer subsample count exceeds the deployment cap.",
                {"limit": limits.max_outer_subsamples},
            )
        )

    if request.bootstrap_replicates > limits.max_bootstrap_replicates:
        issues.append(
            _issue(
                ["bootstrap_replicates"],
                "The bootstrap replicate count exceeds the deployment cap.",
                {"limit": limits.max_bootstrap_replicates},
            )
        )

    # Integer division decides the product comparison without building the
    # product. For positive integers, `outer * replicates > cap` is exactly
    # `outer > cap // replicates`.
    combined_cap = limits.max_combined_bootstrap_work // request.bootstrap_replicates
    if request.outer_subsamples > combined_cap:
        issues.append(
            _issue(
                ["outer_subsamples", "bootstrap_replicates"],
                "The combined bootstrap work exceeds the deployment cap.",
                {"limit": limits.max_combined_bootstrap_work},
            )
        )

    return issues


def _issue(path: list[str | int], message: str, details: dict[str, int]) -> PilotIssue:
    return PilotIssue(
        code="invalid_analysis_setting",
        path=path,
        message=message,
        details=details,
    )


def _positive_integer(raw: str, name: str) -> int:
    if not raw.isdecimal() or len(raw) > MAX_LIMIT_DIGITS:
        raise PilotLimitsUnavailable(f"{name} must be a positive decimal integer.")

    value = int(raw)
    if value <= 0 or value > MAX_LIMIT_VALUE:
        raise PilotLimitsUnavailable(f"{name} must be a positive decimal integer.")

    return value
