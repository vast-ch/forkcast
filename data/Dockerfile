# Builds the app's data files into /data/out (mounted from ./data/out by compose).
#   climate:   CRU TS 4.10 monthly grids -> out/climate.json (downloads ~215 MB once into cache/)
#   routes:    EuroVelo routes from the official GPX tracks + the BRouter demo route -> out/routes/
#   basemap:   Natural Earth country outlines -> out/countries.json
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim
WORKDIR /data
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project
COPY wheelther_data/ wheelther_data/
COPY build.sh ./
ENTRYPOINT ["./build.sh"]
CMD ["all"]
