from pydantic import ValidationError

from .contracts.errors import ComparisonError, ComparisonIssue, ErrorBody, SchemaDiagnostic
from .contracts.pilot import PilotError, PilotErrorBody, PilotIssue


def error_response(code: str, issue: ComparisonIssue) -> ComparisonError:
    return ComparisonError(schema_version=1, error=ErrorBody(code=code, issues=[issue]))


def pydantic_error(error: ValidationError) -> ComparisonError:
    return ComparisonError(
        schema_version=1,
        error=ErrorBody(code="validation_failed", schema_errors=_diagnostics(error)),
    )


def validation_error(issues: list[ComparisonIssue]) -> ComparisonError:
    return ComparisonError(
        schema_version=1, error=ErrorBody(code="validation_failed", issues=issues[:50])
    )


def pilot_error_response(code: str, issue: PilotIssue) -> PilotError:
    return PilotError(schema_version=1, error=PilotErrorBody(code=code, issues=[issue]))


def pilot_pydantic_error(error: ValidationError) -> PilotError:
    return PilotError(
        schema_version=1,
        error=PilotErrorBody(code="validation_failed", schema_errors=_diagnostics(error)),
    )


def pilot_validation_error(issues: list[PilotIssue]) -> PilotError:
    return PilotError(
        schema_version=1, error=PilotErrorBody(code="validation_failed", issues=issues[:50])
    )


def _diagnostics(error: ValidationError) -> list[SchemaDiagnostic]:
    mapped = [_diagnostic(item) for item in error.errors(include_url=False, include_context=False)]
    unique = {(repr(diagnostic.path), diagnostic.message): diagnostic for diagnostic in mapped}
    return sorted(unique.values(), key=lambda item: (repr(item.path), item.message))[:50]


def _diagnostic(item: dict) -> SchemaDiagnostic:
    path = list(item.get("loc", ()))
    if path and path[-1] in {"int", "float"}:
        path.pop()

    safe_path = [part if isinstance(part, int) else _bounded(str(part)) for part in path[:32]]
    return SchemaDiagnostic(
        message=_bounded(str(item.get("msg", "Schema validation failed."))),
        path=safe_path,
        causes=[],
    )


def _bounded(value: str) -> str:
    encoded = value.encode("utf-8")[:256]
    while encoded:
        try:
            return encoded.decode("utf-8")
        except UnicodeDecodeError:
            encoded = encoded[:-1]
    return "Schema validation failed."
