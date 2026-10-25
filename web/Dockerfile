### Stage 1: base installation (also the dev container)
FROM node:24.4-bookworm-slim AS base
WORKDIR /app
SHELL ["/bin/bash", "-c"]
ENV SHELL=bash
ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"
RUN corepack enable && \
  corepack prepare pnpm@10.13.1 --activate && \
  pnpm setup && \
  pnpm config set store-dir "$PNPM_HOME/store" --global
COPY web/package.json web/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

### Stage 1b: dev container (base plus a browser for the Ember tests)
FROM base AS dev
RUN apt-get update && \
  apt-get install -y --no-install-recommends chromium && \
  rm -rf /var/lib/apt/lists/*
# Chrome's sandbox can't run as root in a container.
ENV CHROME_NO_SANDBOX=1
EXPOSE 4200
CMD ["pnpm", "start"]

### Stage 2: build
FROM base AS build
COPY web/ .
# Data built by the `data` image (see data/Dockerfile). The app imports it as
# assets, so every file gets a content-hashed name and can be cached for a year.
COPY data/out/ data-out/
# The changelog page renders the repository's changelog.
COPY CHANGELOG.md ./
RUN pnpm run build

### Stage 3: prod
FROM nginx:stable-alpine AS prod
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
COPY web/security-headers.conf /etc/nginx/snippets/forkcast-headers.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
