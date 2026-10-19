import logging
import os
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from .contracts.errors import ComparisonIssue
from .contracts.family import HolmRequest, HolmResponse
from .contracts.request import ComparisonRequest
from .contracts.result import ComparisonStatistics
from .error_mapping import error_response, pydantic_error, validation_error
from .holm import adjust_holm, holm_issues
from .logging_config import configure_logging
from .service import compare, evidence_issues

configure_logging(os.environ["EVALUATION_LOG_LEVEL"])
LOGGER = logging.getLogger("evaluation_compute")
METHOD = "corrected_crossed_bootstrap_v1"
HOLM_METHOD = "holm"
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
    started = _begin(request, METHOD)

    body = await _read_body(request)
    if isinstance(body, JSONResponse):
        return body

    try:
        parsed = ComparisonRequest.model_validate_json(body, strict=True)
    except ValidationError as exc:
        # JSON syntax errors have a dedicated transport-level code.
        if any(item["type"] == "json_invalid" for item in exc.errors()):
            return _invalid_json(request)
        return _error(request, 422, pydantic_error(exc))

    issues = evidence_issues(parsed)
    if issues:
        return _error(request, 422, validation_error(issues))

    result = compare(parsed)
    LOGGER.info(
        "comparison completed",
        extra={
            "method": result.method,
            "duration_ms": _duration_ms(started),
            "response_status": 200,
        },
    )
    return result


@app.post("/v1/families/holm", response_model=HolmResponse)
async def holm(request: Request) -> HolmResponse | JSONResponse:
    started = _begin(request, HOLM_METHOD)

    body = await _read_body(request)
    if isinstance(body, JSONResponse):
        return body

    try:
        parsed = HolmRequest.model_validate_json(body, strict=True)
    except ValidationError as exc:
        if any(item["type"] == "json_invalid" for item in exc.errors()):
            return _invalid_json(request)
        return _error(request, 422, pydantic_error(exc))

    issues = holm_issues(parsed)
    if issues:
        return _error(request, 422, validation_error(issues))

    result = adjust_holm(parsed)
    LOGGER.info(
        "family correction completed",
        extra={
            "method": result.method,
            "family_size": result.family_size,
            "duration_ms": _duration_ms(started),
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
        "calculation failed",
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
                message="The calculation failed.",
                details={},
            ),
        ).model_dump(mode="json", exclude_none=True),
    )


def _begin(request: Request, method: str) -> float:
    started = time.monotonic()
    request.state.started = started
    request.state.method = method
    return started


async def _read_body(request: Request) -> bytes | JSONResponse:
    """Enforce the content type and the byte limit for one JSON body."""

    content_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if content_type != "application/json":
        return _error(
            request,
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
        )

    content_length = request.headers.get("content-length")
    if content_length is not None:
        if not content_length.isdigit():
            return _invalid_json(request)
        if int(content_length) > REQUEST_LIMIT:
            return _too_large(request)

    body = bytearray()
    async for chunk in request.stream():
        if len(chunk) > REQUEST_LIMIT - len(body):
            return _too_large(request)
        body.extend(chunk)

    return bytes(body)


def _invalid_json(request: Request) -> JSONResponse:
    return _error(
        request,
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
    )


def _too_large(request: Request) -> JSONResponse:
    return _error(
        request,
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
    )


def _error(request: Request, status: int, error: object) -> JSONResponse:
    content = error.model_dump(mode="json", exclude_none=True)  # type: ignore[attr-defined]
    error_body = content["error"]
    validation_codes = (
        [issue["code"] for issue in error_body["issues"]]
        if "issues" in error_body
        else ["schema_validation_failed"]
    )
    LOGGER.info(
        "request rejected",
        extra={
            **_log_fields(request, status, validation_codes[0]),
            "validation_codes": validation_codes,
        },
    )
    return JSONResponse(status_code=status, content=content)


def _log_fields(request: Request, status: int, code: str) -> dict[str, object]:
    started = getattr(request.state, "started", time.monotonic())
    return {
        "method": getattr(request.state, "method", METHOD),
        "duration_ms": _duration_ms(started),
        "response_status": status,
        "validation_codes": [code],
    }


def _duration_ms(started: float) -> float:
    return round((time.monotonic() - started) * 1000, 3)
