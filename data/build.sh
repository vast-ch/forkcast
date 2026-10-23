#!/usr/bin/env bash
# Usage: ./build.sh [all|climate|routes|basemap|manifest|download]
#   download refreshes the official EuroVelo GPX tracks in eurovelo/ (not part of `all`).
set -euo pipefail
cd "$(dirname "$0")"
CRU_VERSION="4.10"
CRU_DIR="https://crudata.uea.ac.uk/cru/data/hrg/cru_ts_${CRU_VERSION}/cruts.2604091129.v${CRU_VERSION}"

climate() {
  mkdir -p cache/cru
  for v in tmx tmn pre wet; do
    for p in 2011.2020 2021.2025; do
      f="cru_ts${CRU_VERSION}.${p}.${v}.dat.nc.gz"
      [ -s "cache/cru/$f" ] || curl -sSf -o "cache/cru/$f" "$CRU_DIR/$v/$f"
    done
  done
  uv run python -m wheelther_data.climate cache/cru --from 2011 --to 2025
}
routes() { uv run python -m wheelther_data.routes; }
download() { uv run python -m wheelther_data.eurovelo download; }
basemap() { uv run python -m wheelther_data.basemap; }
manifest() { uv run python -m wheelther_data.manifest; }

case "${1:-all}" in
  all) basemap; routes; climate; manifest ;;
  climate|routes|basemap|manifest|download) "$1" ;;
  *) echo "Usage: $0 [all|climate|routes|basemap|manifest|download]" >&2; exit 1 ;;
esac
