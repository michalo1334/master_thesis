import math

import numpy as np

from .contracts.errors import ComparisonIssue
from .contracts.evidence import Evidence
from .contracts.request import ComparisonRequest
from .contracts.result import (
    Assessment,
    ComparisonStatistics,
    ConfidenceInterval,
    Estimate,
    TestResult,
)
from .statistics import corrected_crossed_bootstrap


def evidence_issues(request: ComparisonRequest) -> list[ComparisonIssue]:
    return evidence_issues_for(request.evidence)


def evidence_issues_for(evidence: Evidence) -> list[ComparisonIssue]:
    """Return the accepted Stage 2 evidence issues for one evidence matrix."""

    issues: list[ComparisonIssue] = []

    if evidence.alternative.strategy == "cvss":
        issues.append(
            ComparisonIssue(
                code="unsupported_alternative_strategy",
                path=["evidence", "alternative", "strategy"],
                message="The alternative strategy must not be cvss.",
                details={},
            )
        )

    seen_attacks: set[int] = set()
    for seed in evidence.attack_seeds:
        if seed in seen_attacks:
            issues.append(
                ComparisonIssue(
                    code="duplicate_attack_seed",
                    path=["evidence", "attack_seeds"],
                    message="Attack seeds must be unique.",
                    details={},
                )
            )
            break
        seen_attacks.add(seed)

    expected = len(evidence.attack_seeds)
    for side_name, side in (
        ("alternative", evidence.alternative),
        ("reference", evidence.reference),
    ):
        first_index_by_id: dict[str, int] = {}
        for index, plan in enumerate(side.plans):
            if plan.id in first_index_by_id:
                issues.append(
                    ComparisonIssue(
                        code="duplicate_plan_id",
                        path=["evidence", side_name, "plans", index, "id"],
                        message="Plan IDs must be unique within each comparison side.",
                        details={"first_index": first_index_by_id[plan.id]},
                    )
                )
            else:
                first_index_by_id[plan.id] = index

            actual = len(plan.mission_impacts)
            if actual != expected:
                issues.append(
                    ComparisonIssue(
                        code="attack_column_count_mismatch",
                        path=["evidence", side_name, "plans", index, "mission_impacts"],
                        message=(
                            f"Expected {expected} mission-impact values but received {actual}."
                        ),
                        details={"expected": expected, "actual": actual},
                    )
                )

            for impact_index, impact in enumerate(plan.mission_impacts):
                if not math.isfinite(float(impact)):
                    issues.append(
                        ComparisonIssue(
                            code="non_finite_mission_impact",
                            path=[
                                "evidence",
                                side_name,
                                "plans",
                                index,
                                "mission_impacts",
                                impact_index,
                            ],
                            message="Mission-impact values must be finite.",
                            details={},
                        )
                    )

    return sorted(issues, key=lambda issue: (_path_key(issue.path), issue.code))[:50]


def compare(request: ComparisonRequest) -> ComparisonStatistics:
    alternative_plans = sorted(request.evidence.alternative.plans, key=lambda plan: plan.id)
    reference_plans = sorted(request.evidence.reference.plans, key=lambda plan: plan.id)
    alternative = np.asarray([plan.mission_impacts for plan in alternative_plans], dtype=np.float64)
    reference = np.asarray([plan.mission_impacts for plan in reference_plans], dtype=np.float64)

    result = corrected_crossed_bootstrap(
        alternative,
        reference,
        replicates=request.resampling.replicates,
        confidence_level=float(request.interval.confidence_level),
        seed=request.resampling.seed,
    )
    warnings = ["zero_width_interval"] if result.zero_width_interval else []

    return ComparisonStatistics(
        schema_version=1,
        method="corrected_crossed_bootstrap_v1",
        estimate=Estimate(contrast="alternative_minus_reference", value=result.estimate),
        interval=ConfidenceInterval(
            confidence_level=request.interval.confidence_level,
            lower=result.lower,
            upper=result.upper,
        ),
        test=TestResult(
            method="centered_crossed_bootstrap",
            alternative=request.test.alternative,
            raw_p_value=result.raw_p_value,
        ),
        assessment=Assessment(
            status="informative" if result.informative else "non_informative",
            warnings=warnings,
        ),
    )


def _path_key(path: list[str | int]) -> tuple[tuple[int, str | int], ...]:
    return tuple((0, part) if isinstance(part, str) else (1, part) for part in path)
