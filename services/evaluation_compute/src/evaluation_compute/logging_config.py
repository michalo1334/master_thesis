import json
import logging
import logging.config
from datetime import UTC, datetime
from typing import Any

_SAFE_FIELDS = (
    "method",
    "duration_ms",
    "response_status",
    "validation_codes",
)


class JsonFormatter(logging.Formatter):
    """Format application and Uvicorn records as one JSON object per line."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=UTC).isoformat(),
            "level": record.levelname.lower(),
            "logger": record.name,
            "message": record.getMessage(),
        }
        for field in _SAFE_FIELDS:
            if hasattr(record, field):
                payload[field] = getattr(record, field)
        if record.exc_info:
            payload["exception_type"] = record.exc_info[0].__name__
        return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def configure_logging(level: str) -> None:
    configured_level = level.upper()
    logging.config.dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {"json": {"()": JsonFormatter}},
            "handlers": {
                "stderr": {
                    "class": "logging.StreamHandler",
                    "formatter": "json",
                    "stream": "ext://sys.stderr",
                }
            },
            "root": {"handlers": ["stderr"], "level": configured_level},
            "loggers": {
                "evaluation_compute": {
                    "handlers": ["stderr"],
                    "level": configured_level,
                    "propagate": False,
                },
                "uvicorn": {
                    "handlers": ["stderr"],
                    "level": configured_level,
                    "propagate": False,
                },
                "uvicorn.error": {
                    "handlers": ["stderr"],
                    "level": configured_level,
                    "propagate": False,
                },
                "uvicorn.access": {
                    "handlers": ["stderr"],
                    "level": configured_level,
                    "propagate": False,
                },
            },
        }
    )
