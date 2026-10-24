#!/usr/bin/env bash
# Every check, web and data, in their containers. Run before committing.
#   ./check.sh          lint and test everything
#   ./check.sh --fix    fix what the linters can, then check
# The web checks run in the `ui` dev container (docker compose up -d ui).
set -euo pipefail
cd "$(dirname "$0")"

fix=false
[[ "${1:-}" == "--fix" ]] && fix=true

if ! docker compose ps --status running --services | grep -qx ui; then
  echo "The ui container isn't running; start it with: docker compose up -d ui" >&2
  exit 1
fi
data() { docker compose --profile tools run --rm -T --entrypoint uv data run "$@"; }

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

if $fix; then
  step "web: fix"
  docker compose exec -T ui pnpm lint:fix
  step "data: fix"
  data ruff check --fix forkcast_data tests
fi

step "web: lint (eslint, template-lint, stylelint, prettier, types)"
docker compose exec -T ui pnpm lint
step "web: tests (Ember: unit, rendering, acceptance)"
docker compose exec -T ui pnpm test
step "data: lint (ruff)"
data ruff check forkcast_data tests
step "data: tests"
data pytest -q

printf '\n\033[1;32mAll checks passed.\033[0m\n'
