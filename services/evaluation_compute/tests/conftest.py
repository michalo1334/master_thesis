import json
import os
from pathlib import Path

import pytest

os.environ.update(
    {
        "EVALUATION_BIND_HOST": "127.0.0.1",
        "EVALUATION_LOG_LEVEL": "info",
        "EVALUATION_PILOT_MAX_BOOTSTRAP_REPLICATES": "1024",
        "EVALUATION_PILOT_MAX_COMBINED_BOOTSTRAP_WORK": "131072",
        "EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES": "128",
        "EVALUATION_PORT": "8080",
        "EVALUATION_REQUEST_LIMIT_BYTES": "1048576",
        "EVALUATION_SHUTDOWN_TIMEOUT_SECONDS": "10",
        "EVALUATION_WORKERS": "1",
    }
)


@pytest.fixture(scope="session")
def contracts_root() -> Path:
    return Path(__file__).resolve().parents[3] / "contracts" / "evaluation" / "comparison" / "v1"


@pytest.fixture(scope="session")
def valid_request(contracts_root: Path) -> dict:
    return json.loads((contracts_root / "valid" / "crossed-small.request.json").read_text())
