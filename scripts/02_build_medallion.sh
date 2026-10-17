#!/usr/bin/env bash
# Строит медальон bronze -> silver -> gold, проверяет Gold против эталонного Q3 и снимает статистику слоёв.
set -euo pipefail
cd "$(dirname "$0")/.."
run() { echo ">>> $1"; MSYS_NO_PATHCONV=1 docker exec -i trino trino --output-format ALIGNED < "$1" 2>/dev/null; }
time run sql/10_bronze.sql
time run sql/20_silver.sql
time run sql/30_gold.sql
run sql/40_validate.sql | tee results/validate.txt
run sql/50_layer_stats.sql | tee results/layer_stats.txt
