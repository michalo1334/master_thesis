"""Deterministic study-analysis stub for the browser end-to-end run.

This module is a test-only double for the two study HTTP routes. It lets a
browser driver exercise the complete dashboard workflow without the real
statistics provider, which needs evaluation runs that satisfy the frozen study
seed schedule. It adds no statistics and no production code path.

Control the response with a JSON file (``--control``, default
``control.json`` beside the archives). One request reads the file again, so a
driver can switch scenarios without restarting the stub::

    {"pilot": "eligible", "analyze": "final"}

``pilot`` is one of ``eligible``, ``insufficient``, ``non_informative``, or
``error``. ``analyze`` is ``final`` or ``error``. ``pilot_delay_seconds`` and
``analyze_delay_seconds`` hold the response open so a driver can observe a
running task. It serves the matching ``.zip`` file from ``--archives`` and
prints one JSON line per request to stderr for evidence (read it with
``docker logs``).

Only the local browser run uses this double. The real service and its tests
stay unchanged.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PILOT_FILES = {
    "eligible": "pilot_eligible.zip",
    "insufficient": "pilot_insufficient.zip",
    "non_informative": "pilot_non_informative.zip",
}
ANALYZE_FILES = {"final": "final.zip"}

ROUTES = {"/v1/study/pilot": "pilot", "/v1/study/analyze": "analyze"}


def echo_tier_context(archive: bytes, bundle: bytes) -> bytes:
    """Rewrite result context from the exact bundle the service received.

    The application binds a parsed result to its locked input bundle by
    comparing ``tier_context`` with the bundle archive digests. The production
    export is deterministic for the same locked inputs. This test double
    therefore copies the received bundle context into result metadata and, for
    Final results, ``tier_context.json``. It then refreshes every checksum.
    """
    try:
        with zipfile.ZipFile(io.BytesIO(bundle)) as bundle_zip:
            spec = json.loads(bundle_zip.read("study.json"))
        context = [
            {
                "label": tier["label"],
                "archive": tier["archive"],
                "archive_sha256": tier["sha256"],
            }
            for tier in spec["tiers"]
        ]

        with zipfile.ZipFile(io.BytesIO(archive)) as archive_zip:
            names = archive_zip.namelist()
            files = {name: archive_zip.read(name) for name in names}

        metadata = json.loads(files["study_metadata.json"])
        metadata["tier_context"] = context
        files["study_metadata.json"] = json.dumps(metadata, sort_keys=True, indent=2).encode() + b"\n"
        if "tier_context.json" in files:
            files["tier_context.json"] = json.dumps(context, sort_keys=True, indent=2).encode() + b"\n"

        payload = sorted(name for name in files if name != "checksums.txt")
        files["checksums.txt"] = "".join(
            f"{name}  {hashlib.sha256(files[name]).hexdigest()}\n" for name in payload
        ).encode()

        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as patched:
            for name in sorted(files):
                member = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                member.compress_type = zipfile.ZIP_DEFLATED
                member.create_system = 3
                member.external_attr = 0o600 << 16
                patched.writestr(member, files[name])
        return buffer.getvalue()
    except (KeyError, OSError, ValueError, zipfile.BadZipFile):
        return archive


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    archives: Path
    control: Path

    def do_POST(self) -> None:  # noqa: N802 (stdlib handler name)
        route = ROUTES.get(self.path)
        if route is None:
            self._send(404, b"unknown route", "text/plain")
            return

        length = int(self.headers.get("Content-Length", "0"))
        bundle = self.rfile.read(length)
        scenario = self._scenario()
        choice = scenario.get(route, "error")

        delay = self._delay_seconds(scenario.get(f"{route}_delay_seconds", 0))
        if delay > 0:
            time.sleep(delay)

        if choice == "error":
            self._log(route, choice, len(bundle), b"")
            self._send(503, b"stub analysis unavailable", "text/plain")
            return

        name = (PILOT_FILES if route == "pilot" else ANALYZE_FILES).get(choice)
        path = self.archives / name if name else None
        if path is None or not path.is_file():
            self._log(route, choice, len(bundle), b"")
            self._send(500, b"stub fixture missing", "text/plain")
            return

        body = echo_tier_context(path.read_bytes(), bundle)
        self._log(route, choice, len(bundle), body)
        self._send(200, body, "application/zip")

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        if self.path == "/healthz":
            self._send(200, b"ok", "text/plain")
            return
        self._send(404, b"unknown route", "text/plain")

    def _scenario(self) -> dict:
        try:
            return json.loads(self.control.read_text())
        except (OSError, ValueError):
            return {"pilot": "eligible", "analyze": "final"}

    @staticmethod
    def _delay_seconds(value: object) -> float:
        try:
            return max(0.0, float(value))
        except (TypeError, ValueError):
            return 0.0

    def _log(self, route: str, choice: str, size: int, body: bytes) -> None:
        line = json.dumps(
            {
                "time": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "route": route,
                "choice": choice,
                "bundle_bytes": size,
                "archive_sha256": hashlib.sha256(body).hexdigest(),
            }
        )
        print(line, file=sys.stderr, flush=True)

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args) -> None:  # keep stdout quiet
        return


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="study_stub_server")
    parser.add_argument("--archives", required=True)
    parser.add_argument("--control", default=None)
    parser.add_argument("--port", type=int, default=8080)
    arguments = parser.parse_args(argv)

    archives = Path(arguments.archives)
    Handler.archives = archives
    Handler.control = Path(arguments.control or archives / "control.json")

    server = ThreadingHTTPServer(("0.0.0.0", arguments.port), Handler)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
