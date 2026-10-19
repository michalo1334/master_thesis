import numpy as np

from .contracts.pilot import CandidateComparisonRequest, CandidateComparisonResponse, PilotIssue
from .pilot_limits import PilotLimits, load_pilot_limits, resource_issues
from .service import evidence_issues_for
from .statistics import corrected_crossed_bootstrap


def pilot_issues(request: CandidateComparisonRequest) -> list[PilotIssue]:
    """Return bounded scientific issues for one candidate comparison."""

    issues = [
        PilotIssue(**issue.model_dump()) for issue in evidence_issues_for(request.evidence)
    ]
    identity = request.identity
    evidence = request.evidence

    for field, declared, actual in (
        ("alternative", identity.alternative, evidence.alternative.strategy),
        ("reference", identity.reference, evidence.reference.strategy),
        ("outcome", identity.outcome, evidence.outcome),
    ):
        if declared != actual:
            issues.append(
                PilotIssue(
                    code="identity_mismatch",
                    path=["identity", field],
                    message="The identity field must agree with the candidate evidence.",
                    details={"declared": declared, "request": actual},
                )
            )

    candidate = request.candidate
    alternative_rows = len(evidence.alternative.plans)
    reference_rows = len(evidence.reference.plans)
    available_plans = min(alternative_rows, reference_rows)
    available_attacks = len(evidence.attack_seeds)

    if candidate.plan_count > available_plans:
        issues.append(
            PilotIssue(
                code="candidate_exceeds_plan_rows",
                path=["candidate", "plan_count"],
                message="The candidate plan count exceeds the available plan rows.",
                details={
                    "candidate": candidate.plan_count,
                    "alternative_rows": alternative_rows,
                    "reference_rows": reference_rows,
                },
            )
        )

    if candidate.attacks_per_plan > available_attacks:
        issues.append(
            PilotIssue(
                code="candidate_exceeds_attack_columns",
                path=["candidate", "attacks_per_plan"],
                message="The candidate attack count exceeds the available attack columns.",
                details={
                    "candidate": candidate.attacks_per_plan,
                    "available": available_attacks,
                },
            )
        )

    return sorted(issues, key=lambda issue: (_path_key(issue.path), issue.code))[:50]


def evaluate_candidate_comparison(
    request: CandidateComparisonRequest,
    limits: PilotLimits | None = None,
) -> CandidateComparisonResponse:
    """Run the accepted outer sampling and inner crossed bootstrap once.

    The outer child stream follows the historical policy: one deterministic
    stream per comparison, candidate plan and attack counts included in the
    seed sequence. Every outer sample spawns one sampling child and one
    bootstrap child. The sampling child selects both plan sides independently
    without replacement and the shared attack columns without replacement.
    The bootstrap child derives the accepted inner interval and null streams.
    """

    if limits is None:
        limits = load_pilot_limits()

    resource = resource_issues(request, limits)
    if resource:
        raise ValueError(resource[0].code)

    issues = pilot_issues(request)
    if issues:
        raise ValueError(issues[0].code)

    evidence = request.evidence
    candidate = request.candidate
    alternative = np.asarray(
        [plan.mission_impacts for plan in evidence.alternative.plans], dtype=np.float64
    )
    reference = np.asarray(
        [plan.mission_impacts for plan in evidence.reference.plans], dtype=np.float64
    )

    alternative_count, attack_count = alternative.shape
    reference_count = reference.shape[0]
    plan_count = candidate.plan_count
    attacks_per_plan = candidate.attacks_per_plan

    sequence = np.random.SeedSequence([request.stream_seed, plan_count, attacks_per_plan])
    half_widths: list[float] = []
    informative = True

    for child in sequence.spawn(request.outer_subsamples):
        sampling_sequence, bootstrap_sequence = child.spawn(2)
        generator = np.random.default_rng(sampling_sequence)

        alternative_rows = generator.choice(alternative_count, size=plan_count, replace=False)
        reference_rows = generator.choice(reference_count, size=plan_count, replace=False)
        attack_columns = generator.choice(attack_count, size=attacks_per_plan, replace=False)

        subsample_alternative = alternative[np.ix_(alternative_rows, attack_columns)]
        subsample_reference = reference[np.ix_(reference_rows, attack_columns)]

        inner_seed = int(bootstrap_sequence.generate_state(1)[0])
        statistics = corrected_crossed_bootstrap(
            subsample_alternative,
            subsample_reference,
            replicates=request.bootstrap_replicates,
            confidence_level=float(request.confidence_level),
            seed=inner_seed,
        )
        half_widths.append(float(statistics.upper - statistics.lower) / 2.0)
        informative = informative and bool(statistics.informative)

    guarded_half_width = float(
        np.quantile(np.asarray(half_widths, dtype=np.float64), float(request.guard_quantile))
    )
    passes = bool(informative and guarded_half_width <= float(request.target_half_width))

    return CandidateComparisonResponse(
        schema_version=1,
        method="precision_pilot_candidate_v1",
        pilot_id=request.pilot_id,
        study_revision_id=request.study_revision_id,
        family_id=request.family_id,
        snapshot_id=request.snapshot_id,
        candidate_position=request.candidate_position,
        comparison_position=request.comparison_position,
        identity=request.identity,
        candidate=request.candidate,
        outer_subsamples=request.outer_subsamples,
        stream_seed=request.stream_seed,
        guard_quantile=request.guard_quantile,
        target_half_width=request.target_half_width,
        confidence_level=request.confidence_level,
        bootstrap_replicates=request.bootstrap_replicates,
        guarded_half_width=guarded_half_width,
        informative=informative,
        passes=passes,
    )


def _path_key(path: list[str | int]) -> tuple[tuple[int, str | int], ...]:
    return tuple((0, part) if isinstance(part, str) else (1, part) for part in path)
