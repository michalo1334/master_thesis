import logging
import os
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from .contracts.errors import ComparisonIssue
from .contracts.request import ComparisonRequest
from .contracts.result import ComparisonStatistics
from .error_mapping import error_response, pydantic_error, validation_error
from .logging_config import configure_logging
from .service import compare, evidence_issues

configure_logging(os.environ["EVALUATION_LOG_LEVEL"])
LOGGER = logging.getLogger("evaluation_compute")
METHOD = "corrected_crossed_bootstrap_v1"
REQUEST_LIMIT = int(os.environ["EVALUATION_REQUEST_LIMIT_BYTES"])
if REQUEST_LIMIT <= 0:
    raise ValueError("EVALUATION_REQUEST_LIMIT_BYTES must be positive")


class TransientComputeError(Exception):
    """Signal that the service cannot calculate the comparison at present."""


app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "alive"}


@app.get("/ready")
def ready() -> dict[str, str]:
    return {"status": "ready"}


@app.post(
    "/v1/comparisons/corrected-crossed-bootstrap",
    response_model=ComparisonStatistics,
)
async def comparison(request: Request) -> ComparisonStatistics | JSONResponse:
    started = time.monotonic()
    request.state.started = started
    content_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if content_type != "application/json":
        return _error(
            415,
            error_response(
                "unsupported_media_type",
                ComparisonIssue(
                    code="unsupported_media_type",
                    path=[],
                    message="Content-Type must be application/json.",
                    details={"accepted": "application/json"},
                ),
            ),
            started,
        )

    content_length = request.headers.get("content-length")
    if content_length is not None:
        if not content_length.isdigit():
            return _invalid_json(started)
        if int(content_length) > REQUEST_LIMIT:
            return _too_large(started)

    body = bytearray()
    async for chunk in request.stream():
        if len(chunk) > REQUEST_LIMIT - len(body):
            return _too_large(started)
        body.extend(chunk)

    try:
        parsed = ComparisonRequest.model_validate_json(bytes(body), strict=True)
    except ValidationError as exc:
        # JSON syntax errors have a dedicated transport-level code.
        if any(item["type"] == "json_invalid" for item in exc.errors()):
            return _invalid_json(started)
        return _error(422, pydantic_error(exc), started)

    issues = evidence_issues(parsed)
    if issues:
        return _error(422, validation_error(issues), started)

    result = compare(parsed)
    LOGGER.info(
        "comparison completed",
        extra={
            "method": result.method,
            "duration_ms": round((time.monotonic() - started) * 1000, 3),
            "response_status": 200,
        },
    )
    return result


@app.exception_handler(TransientComputeError)
async def transient_compute_error(
    request: Request, _exception: TransientComputeError
) -> JSONResponse:
    LOGGER.warning(
        "comparison temporarily unavailable",
        extra=_log_fields(request, 503, "compute_unavailable"),
    )
    return JSONResponse(
        status_code=503,
        content=error_response(
            "compute_unavailable",
            ComparisonIssue(
                code="compute_unavailable",
                path=[],
                message="The compute service is unavailable.",
                details={},
            ),
        ).model_dump(mode="json", exclude_none=True),
    )


@app.exception_handler(Exception)
async def unexpected_error(request: Request, exception: Exception) -> JSONResponse:
    LOGGER.exception(
        "comparison calculation failed",
        exc_info=exception,
        extra=_log_fields(request, 500, "compute_failed"),
    )
    return JSONResponse(
        status_code=500,
        content=error_response(
            "compute_failed",
            ComparisonIssue(
                code="compute_failed",
                path=[],
                message="The comparison calculation failed.",
                details={},
            ),
        ).model_dump(mode="json", exclude_none=True),
    )


def _invalid_json(started: float) -> JSONResponse:
    return _error(
        400,
        error_response(
            "invalid_json",
            ComparisonIssue(
                code="invalid_json",
                path=[],
                message="The request body is not valid JSON.",
                details={},
            ),
        ),
        started,
    )


def _too_large(started: float) -> JSONResponse:
    return _error(
        413,
        error_response(
            "request_too_large",
            ComparisonIssue(
                code="request_too_large",
                path=[],
                message="The request body exceeds the byte limit.",
                details={"limit_bytes": REQUEST_LIMIT},
            ),
        ),
        started,
    )


def _error(status: int, error: object, started: float) -> JSONResponse:
    content = error.model_dump(mode="json", exclude_none=True)  # type: ignore[attr-defined]
    error_body = content["error"]
    validation_codes = (
        [issue["code"] for issue in error_body["issues"]]
        if "issues" in error_body
        else ["schema_validation_failed"]
    )
    LOGGER.info(
        "comparison request rejected",
        extra={
            "method": METHOD,
            "duration_ms": round((time.monotonic() - started) * 1000, 3),
            "response_status": status,
            "validation_codes": validation_codes,
        },
    )
    return JSONResponse(status_code=status, content=content)


def _log_fields(request: Request, status: int, code: str) -> dict[str, object]:
    started = getattr(request.state, "started", time.monotonic())
    return {
        "method": METHOD,
        "duration_ms": round((time.monotonic() - started) * 1000, 3),
        "response_status": status,
        "validation_codes": [code],
    }
