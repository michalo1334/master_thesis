import asyncio
import copy
import json

from fastapi.testclient import TestClient

from evaluation_compute import api
from evaluation_compute.api import app

client = TestClient(app, raise_server_exceptions=False)


def test_api_01_health_and_readiness():
    assert client.get("/health").json() == {"status": "alive"}
    assert client.get("/ready").json() == {"status": "ready"}


def test_api_02_valid_comparison_is_deterministic(valid_request):
    first = client.post("/v1/comparisons/corrected-crossed-bootstrap", json=valid_request)
    second = client.post("/v1/comparisons/corrected-crossed-bootstrap", json=valid_request)
    assert first.status_code == 200
    assert first.json() == second.json()
    assert first.json()["estimate"]["contrast"] == "alternative_minus_reference"


def test_api_03_plan_input_order_does_not_change_statistics(valid_request):
    reordered = copy.deepcopy(valid_request)
    reordered["evidence"]["alternative"]["plans"].reverse()
    reordered["evidence"]["reference"]["plans"].reverse()

    original = client.post("/v1/comparisons/corrected-crossed-bootstrap", json=valid_request)
    changed = client.post("/v1/comparisons/corrected-crossed-bootstrap", json=reordered)

    assert original.status_code == changed.status_code == 200
    assert original.json() == changed.json()


def test_api_04_invalid_json():
    response = client.post(
        "/v1/comparisons/corrected-crossed-bootstrap",
        content=b"{",
        headers={"content-type": "application/json"},
    )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_json"


def test_api_05_invalid_evidence(valid_request):
    payload = copy.deepcopy(valid_request)
    payload["evidence"]["alternative"]["plans"][0]["mission_impacts"].pop()
    response = client.post("/v1/comparisons/corrected-crossed-bootstrap", json=payload)
    assert response.status_code == 422
    issue = response.json()["error"]["issues"][0]
    assert issue["code"] == "attack_column_count_mismatch"
    assert issue["path"] == ["evidence", "alternative", "plans", 0, "mission_impacts"]


def test_api_06_content_type_and_size_limits():
    media = client.post(
        "/v1/comparisons/corrected-crossed-bootstrap",
        content=b"{}",
        headers={"content-type": "text/plain"},
    )
    assert media.status_code == 415
    malformed_length = client.post(
        "/v1/comparisons/corrected-crossed-bootstrap",
        content=b"{}",
        headers={"content-type": "application/json", "content-length": "invalid"},
    )
    assert malformed_length.status_code == 400
    assert malformed_length.json()["error"]["code"] == "invalid_json"
    oversized = client.post(
        "/v1/comparisons/corrected-crossed-bootstrap",
        content=b" " * 1_048_577,
        headers={"content-type": "application/json"},
    )
    assert oversized.status_code == 413


def test_api_07_stream_rejects_one_oversized_chunk_before_buffering(monkeypatch):
    """API-06: WHEN one chunk exceeds the remainder, the API SHALL reject it before append."""

    class GuardedBuffer(bytearray):
        def extend(self, chunk):
            if len(self) + len(chunk) > api.REQUEST_LIMIT:
                raise AssertionError("oversized chunk was appended before rejection")
            super().extend(chunk)

    monkeypatch.setattr(api, "REQUEST_LIMIT", 8)
    monkeypatch.setattr(api, "bytearray", GuardedBuffer, raising=False)
    sent = []
    received = False

    async def receive():
        nonlocal received
        if received:
            return {"type": "http.disconnect"}
        received = True
        return {"type": "http.request", "body": b"123456789", "more_body": False}

    async def send(message):
        sent.append(message)

    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "http",
        "path": "/v1/comparisons/corrected-crossed-bootstrap",
        "raw_path": b"/v1/comparisons/corrected-crossed-bootstrap",
        "query_string": b"",
        "headers": [(b"content-type", b"application/json")],
        "client": ("test", 123),
        "server": ("test", 80),
    }

    asyncio.run(app(scope, receive, send))

    start = next(message for message in sent if message["type"] == "http.response.start")
    body = b"".join(
        message.get("body", b"") for message in sent if message["type"] == "http.response.body"
    )
    assert start["status"] == 413
    assert json.loads(body)["error"]["code"] == "request_too_large"


def test_api_08_transient_compute_failure_is_typed_503(monkeypatch, valid_request):
    def unavailable(_request):
        raise api.TransientComputeError("private transient detail")

    monkeypatch.setattr("evaluation_compute.api.compare", unavailable)
    response = client.post("/v1/comparisons/corrected-crossed-bootstrap", json=valid_request)

    assert response.status_code == 503
    assert response.json() == {
        "schema_version": 1,
        "error": {
            "code": "compute_unavailable",
            "issues": [
                {
                    "code": "compute_unavailable",
                    "path": [],
                    "message": "The compute service is unavailable.",
                    "details": {},
                }
            ],
        },
    }
    assert "private transient detail" not in response.text


def test_api_09_unexpected_failure_is_safe(monkeypatch, valid_request):
    def fail(_request):
        raise RuntimeError("private path /secret/should-not-leak")

    monkeypatch.setattr("evaluation_compute.api.compare", fail)
    response = client.post("/v1/comparisons/corrected-crossed-bootstrap", json=valid_request)
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "compute_failed"
    assert "/secret" not in response.text
