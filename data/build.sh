#!/usr/bin/env bash
# Forkcast data pipeline; see README.md in this folder.
#   ./build.sh all [--fresh]
#   ./build.sh download <source...> [--fresh]
#   ./build.sh build <output...> [--fresh]
#   ./build.sh status
set -euo pipefail
cd "$(dirname "$0")"
exec uv run python -m forkcast_data "${@:-all}"
