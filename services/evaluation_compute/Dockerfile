FROM ghcr.io/astral-sh/uv:0.9.5 AS uv
FROM python:3.12.12-slim-bookworm

COPY --from=uv /uv /usr/local/bin/uv
WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY src ./src
RUN uv sync --frozen --no-dev

USER nobody
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=6 \
  CMD ["python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ['EVALUATION_PORT'] + '/ready', timeout=2)"]

CMD ["python", "-m", "evaluation_compute.run"]
