# The data pipeline (see README.md): downloads into cache/, builds into out/.
#   docker compose --profile tools run --rm data [all|status|download …|build …] [--fresh]
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim
WORKDIR /data
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project
COPY forkcast_data/ forkcast_data/
COPY build.sh ./
ENTRYPOINT ["./build.sh"]
CMD ["all"]
