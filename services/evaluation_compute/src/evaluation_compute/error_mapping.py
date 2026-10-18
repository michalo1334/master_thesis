from pydantic import ValidationError

from .contracts.errors import ComparisonError, ComparisonIssue, ErrorBody, SchemaDiagnostic


def error_response(code: str, issue: ComparisonIssue) -> ComparisonError:
    return ComparisonError(schema_version=1, error=ErrorBody(code=code, issues=[issue]))


def pydantic_error(error: ValidationError) -> ComparisonError:
    mapped = [_diagnostic(item) for item in error.errors(include_url=False, include_context=False)]
    unique = {(repr(diagnostic.path), diagnostic.message): diagnostic for diagnostic in mapped}
    diagnostics = sorted(unique.values(), key=lambda item: (repr(item.path), item.message))[:50]
    return ComparisonError(
        schema_version=1,
        error=ErrorBody(code="validation_failed", schema_errors=diagnostics),
    )


def validation_error(issues: list[ComparisonIssue]) -> ComparisonError:
    return ComparisonError(
        schema_version=1, error=ErrorBody(code="validation_failed", issues=issues[:50])
    )


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
