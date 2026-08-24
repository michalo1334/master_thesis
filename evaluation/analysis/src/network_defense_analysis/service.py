from __future__ import annotations

import asyncio
import logging
import os
import re
import shutil
import tempfile
import time
import uuid
from pathlib import Path

from starlette.applications import Starlette
from starlette.background import BackgroundTask
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import FileResponse, JSONResponse, Response
from starlette.routing import Route

from .archive import MAX_COMPRESSED_STDIN, write_result_zip
from . import AnalysisError, analyze

logger = logging.getLogger("uvicorn.error")
MAX_REQUEST_BYTES = MAX_COMPRESSED_STDIN
MAX_RESPONSE_BYTES = 50 * 1024 * 1024
CORRELATION_ID_PATTERN = re.compile(r"[A-Za-z0-9._:-]{1,128}")


def _positive_env(name: str, default: int) -> int:
    value = os.environ.get(name, str(default))
    try:
        parsed = int(value)
    except ValueError as exc:
        raise ValueError(f"{name} must be a positive integer") from exc
    if parsed <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return parsed


def settings() -> tuple[int, int, int, int]:
    return (
        _positive_env("NETWORK_DEFENSE_ANALYSIS_PORT", 8080),
        _positive_env("NETWORK_DEFENSE_ANALYSIS_MAX_REQUEST_BYTES", MAX_REQUEST_BYTES),
        _positive_env("NETWORK_DEFENSE_ANALYSIS_MAX_RESPONSE_BYTES", MAX_RESPONSE_BYTES),
        _positive_env("NETWORK_DEFENSE_ANALYSIS_CONCURRENCY", 1),
    )


def _problem(status: int, title: str, detail: str) -> JSONResponse:
    return JSONResponse(
        {"type": "about:blank", "title": title, "status": status, "detail": detail},
        status_code=status,
        media_type="application/problem+json",
    )


def _correlation_id(request: Request) -> str:
    value = request.headers.get("x-correlation-id", "")
    return value if CORRELATION_ID_PATTERN.fullmatch(value) else str(uuid.uuid4())


async def healthz(request: Request) -> Response:
    return JSONResponse({"status": "ok"})


async def analyze_route(request: Request) -> Response:
    service = request.app.state.service
    correlation_id = request.state.correlation_id
    started = time.monotonic()
    mode = request.url.path.rsplit("/", 1)[-1]
    status = 500
    request_dir = output_dir = None
    acquired = False
    try:
        if request.headers.get("content-type", "").split(";", 1)[0].lower() != "application/zip":
            status = 415
            return _problem(status, "Unsupported content type", "content type must be application/zip")
        content_length = request.headers.get("content-length")
        if content_length is not None:
            try:
                if int(content_length) < 0:
                    raise ValueError
                if int(content_length) > service.limit:
                    status = 413
                    return _problem(status, "Request too large", "request exceeds the compressed ZIP limit")
            except ValueError:
                status = 422
                return _problem(status, "Invalid request", "content length must be a non-negative integer")
        if service.active >= service.concurrency:
            status = 429
            return _problem(status, "Service busy", "no analysis slot is available")
        service.active += 1
        acquired = True
        request_dir = Path(tempfile.mkdtemp(prefix="analysis-request-"))
        input_path = request_dir / "input.zip"
        received = 0
        with input_path.open("wb") as target:
            async for chunk in request.stream():
                received += len(chunk)
                if received > service.limit:
                    status = 413
                    return _problem(status, "Request too large", "request exceeds the compressed ZIP limit")
                target.write(chunk)
        output_dir = Path(tempfile.mkdtemp(prefix="analysis-output-"))
        await asyncio.to_thread(analyze, input_path, output_dir, mode)
        result_path = request_dir / "result.zip"
        with result_path.open("wb") as stream:
            write_result_zip(output_dir, stream)
        if result_path.stat().st_size > service.response_limit:
            status = 500
            return _problem(status, "Analysis failed", "analysis result exceeds the configured limit")
        status = 200
        cleanup = BackgroundTask(_cleanup, request_dir, output_dir, service)
        return FileResponse(result_path, media_type="application/zip", filename=f"{mode}-result.zip", headers={"X-Correlation-ID": correlation_id}, background=cleanup)
    except AnalysisError:
        status = 422
        return _problem(status, "Invalid analysis input", "the ZIP does not satisfy the analysis contract")
    except asyncio.CancelledError:
        raise
    except (OSError, ValueError):
        status = 500
        return _problem(status, "Analysis failed", "internal analysis failure")
    except Exception:
        status = 500
        logger.exception("analysis failed")
        return _problem(status, "Analysis failed", "internal analysis failure")
    finally:
        if acquired and status != 200:
            service.active -= 1
        if status != 200:
            _remove(request_dir, output_dir)
        logger.info("mode=%s correlation_id=%s status=%s elapsed_ms=%.1f", mode, correlation_id, status, (time.monotonic() - started) * 1000)


def _remove(request_dir: Path | None, output_dir: Path | None) -> None:
    for path in (request_dir, output_dir):
        if path:
            shutil.rmtree(path, ignore_errors=True)


def _cleanup(request_dir: Path, output_dir: Path, service) -> None:
    _remove(request_dir, output_dir)
    service.active -= 1


class Service:
    def __init__(self, limit: int, response_limit: int, concurrency: int):
        self.limit = limit
        self.response_limit = response_limit
        self.concurrency = concurrency
        self.active = 0


async def correlation_header(request: Request, call_next):
    correlation_id = _correlation_id(request)
    request.state.correlation_id = correlation_id
    response = await call_next(request)
    response.headers["X-Correlation-ID"] = correlation_id
    return response


def create_app() -> Starlette:
    _, limit, response_limit, concurrency = settings()
    app = Starlette(
        routes=[
            Route("/healthz", healthz),
            Route("/v1/analyze", analyze_route, methods=["POST"], name="analyze"),
            Route("/v1/pilot", analyze_route, methods=["POST"], name="pilot"),
        ],
        middleware=[Middleware(BaseHTTPMiddleware, dispatch=correlation_header)],
    )

    app.state.service = Service(limit, response_limit, concurrency)
    # TODO: authentication is required before non-local exposure.
    return app


def main() -> None:
    import uvicorn

    port, _, _, _ = settings()
    uvicorn.run("network_defense_analysis.service:create_app", factory=True, host="0.0.0.0", port=port, workers=1)


app = create_app()

__all__ = ["app", "create_app", "main"]
