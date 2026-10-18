import pytest

from evaluation_compute import run

VALID_ENV = {
    "EVALUATION_BIND_HOST": "127.0.0.1",
    "EVALUATION_LOG_LEVEL": "info",
    "EVALUATION_PORT": "8080",
    "EVALUATION_SHUTDOWN_TIMEOUT_SECONDS": "10",
    "EVALUATION_WORKERS": "1",
}


def _set_valid_env(monkeypatch):
    for name, value in VALID_ENV.items():
        monkeypatch.setenv(name, value)


def test_start_01_missing_launcher_setting_fails(monkeypatch):
    """START-01: WHEN a required setting is absent, the launcher SHALL fail."""
    _set_valid_env(monkeypatch)
    monkeypatch.delenv("EVALUATION_PORT")

    with pytest.raises(KeyError):
        run.main()


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("EVALUATION_PORT", "not-an-integer"),
        ("EVALUATION_PORT", "0"),
        ("EVALUATION_PORT", "65536"),
        ("EVALUATION_WORKERS", "0"),
        ("EVALUATION_SHUTDOWN_TIMEOUT_SECONDS", "0"),
    ],
)
def test_start_02_invalid_numeric_setting_fails(monkeypatch, name, value):
    """START-02: WHEN a numeric setting is invalid, the launcher SHALL reject it."""
    _set_valid_env(monkeypatch)
    monkeypatch.setenv(name, value)

    with pytest.raises((ValueError, TypeError)):
        run.main()


def test_start_03_empty_host_or_invalid_log_level_fails(monkeypatch):
    """START-03: WHEN host or log level is invalid, startup SHALL fail."""
    _set_valid_env(monkeypatch)
    monkeypatch.setenv("EVALUATION_BIND_HOST", "")
    with pytest.raises(ValueError):
        run.main()

    _set_valid_env(monkeypatch)
    monkeypatch.setenv("EVALUATION_LOG_LEVEL", "unsupported")
    with pytest.raises(ValueError):
        run.main()


def test_start_04_valid_settings_reach_uvicorn(monkeypatch):
    """START-04: WHEN settings are valid, the launcher SHALL pass them unchanged."""
    _set_valid_env(monkeypatch)
    captured = {}

    monkeypatch.setattr(run, "configure_logging", lambda level: captured.update(level=level))
    monkeypatch.setattr(
        run.uvicorn, "run", lambda app, **options: captured.update(app=app, **options)
    )

    run.main()

    assert captured == {
        "app": "evaluation_compute.api:app",
        "host": "127.0.0.1",
        "level": "info",
        "log_config": None,
        "log_level": "info",
        "port": 8080,
        "timeout_graceful_shutdown": 10,
        "workers": 1,
    }
