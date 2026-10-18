import os

import uvicorn

from .logging_config import configure_logging


def main() -> None:
    log_level = os.environ["EVALUATION_LOG_LEVEL"]
    host = os.environ["EVALUATION_BIND_HOST"]
    port = int(os.environ["EVALUATION_PORT"])
    workers = int(os.environ["EVALUATION_WORKERS"])
    shutdown_seconds = int(os.environ["EVALUATION_SHUTDOWN_TIMEOUT_SECONDS"])
    if not host or not 1 <= port <= 65535 or workers <= 0 or shutdown_seconds <= 0:
        raise ValueError("invalid evaluation startup settings")
    configure_logging(log_level)
    uvicorn.run(
        "evaluation_compute.api:app",
        host=host,
        port=port,
        workers=workers,
        log_level=log_level,
        log_config=None,
        timeout_graceful_shutdown=shutdown_seconds,
    )


if __name__ == "__main__":
    main()
