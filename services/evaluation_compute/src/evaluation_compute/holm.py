import math
from decimal import Decimal

from .contracts.errors import ComparisonIssue
from .contracts.family import (
    HolmAdjustedMember,
    HolmRequest,
    HolmResponse,
    identity_key,
)

CAP = Decimal(1)


def holm_issues(request: HolmRequest) -> list[ComparisonIssue]:
    """Check the complete declared family before any calculation."""

    issues: list[ComparisonIssue] = []
    expected_keys = [identity_key(identity) for identity in request.expected_comparisons]
    raw_keys = [identity_key(member.identity) for member in request.raw_results]
    expected_set = set(expected_keys)
    raw_set = set(raw_keys)

    if len(expected_set) != len(expected_keys):
        issues.append(
            ComparisonIssue(
                code="duplicate_expected_identity",
                path=["expected_comparisons"],
                message="Expected comparison identities must be unique.",
                details={},
            )
        )

    if len(raw_set) != len(raw_keys):
        issues.append(
            ComparisonIssue(
                code="duplicate_comparison_identity",
                path=["raw_results"],
                message="Supplied comparison identities must be unique.",
                details={},
            )
        )

    for index, key in enumerate(expected_keys):
        if key not in raw_set:
            issues.append(
                ComparisonIssue(
                    code="missing_comparison",
                    path=["expected_comparisons", index],
                    message="Every expected identity must supply exactly one raw p-value.",
                    details={},
                )
            )

    for index, key in enumerate(raw_keys):
        if key not in expected_set:
            issues.append(
                ComparisonIssue(
                    code="unexpected_comparison",
                    path=["raw_results", index, "identity"],
                    message="Every supplied raw p-value must belong to a declared identity.",
                    details={},
                )
            )

    return sorted(issues, key=lambda issue: (_path_key(issue.path), issue.code))[:50]


def adjust_holm(request: HolmRequest) -> HolmResponse:
    """Apply one Holm correction to the complete declared family.

    The function is pure. It sorts by raw p-value, breaks ties by declared
    family position, applies the cumulative Holm adjustment, and returns rows
    in declared family order.

    The arithmetic uses decimal numbers, not binary floating point. The rule
    ``adjusted <= alpha`` must hold for values that a binary double cannot
    represent, for example three raw p-values of 0.1 and alpha of 0.3.
    """

    family_size = len(request.expected_comparisons)
    members_by_key = {identity_key(member.identity): member for member in request.raw_results}
    alpha = Decimal(str(request.alpha))

    ordered = [
        (position, identity, members_by_key[identity_key(identity)])
        for position, identity in enumerate(request.expected_comparisons)
    ]

    exact = {position: Decimal(str(member.raw_p_value)) for position, _, member in ordered}
    ranked = sorted(ordered, key=lambda row: (exact[row[0]], row[0]))

    adjusted_by_position: dict[int, Decimal] = {}
    running = Decimal(0)
    for rank, (position, _identity, _member) in enumerate(ranked, start=1):
        candidate = Decimal(family_size - rank + 1) * exact[position]
        running = max(running, candidate)
        adjusted_by_position[position] = min(CAP, running)

    results = []
    for position, identity, member in ordered:
        value = adjusted_by_position[position]
        reject_null = value <= alpha

        results.append(
            HolmAdjustedMember(
                identity=identity,
                raw_p_value=member.raw_p_value,
                adjusted_p_value=_wire_number(value, alpha, reject_null),
                reject_null=reject_null,
            )
        )

    return HolmResponse(
        schema_version=1,
        family_id=request.family_id,
        method=request.method,
        alpha=request.alpha,
        family_size=family_size,
        results=results,
    )


def _wire_number(value: Decimal, alpha: Decimal, reject_null: bool) -> float:
    """Return a JSON number that carries the same decision as the exact value.

    The wire type is a binary float. Rounding can move the value across the
    alpha boundary. A reader that compares the emitted number against alpha
    must reach the same decision, so shift one unit in the last place when
    needed.
    """

    number = float(value)
    if (number <= float(alpha)) == reject_null:
        return number

    return math.nextafter(number, -math.inf if reject_null else math.inf)


def _path_key(path: list[str | int]) -> tuple[tuple[int, str | int], ...]:
    return tuple((0, part) if isinstance(part, str) else (1, part) for part in path)
