import json
import logging

from evaluation_compute.logging_config import JsonFormatter, configure_logging


def test_logging_01_formatter_preserves_only_safe_structured_fields():
    record = logging.LogRecord(
        name="evaluation_compute",
        level=logging.INFO,
        pathname=__file__,
        lineno=10,
        msg="comparison completed",
        args=(),
        exc_info=None,
    )
    record.method = "corrected_crossed_bootstrap_v1"
    record.duration_ms = 12.5
    record.response_status = 200
    record.validation_codes = []
    record.evidence = {"mission_impacts": [999]}

    payload = json.loads(JsonFormatter().format(record))

    assert payload["message"] == "comparison completed"
    assert payload["method"] == "corrected_crossed_bootstrap_v1"
    assert payload["duration_ms"] == 12.5
    assert payload["response_status"] == 200
    assert payload["validation_codes"] == []
    assert "evidence" not in payload
    assert "mission_impacts" not in json.dumps(payload)


def test_logging_02_application_and_uvicorn_use_json_stream_handlers():
    configure_logging("warning")

    for logger_name in ("evaluation_compute", "uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(logger_name)
        assert logger.handlers
        assert all(isinstance(handler.formatter, JsonFormatter) for handler in logger.handlers)
        assert logger.propagate is False
