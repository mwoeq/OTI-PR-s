#!/usr/bin/env bash
# Бенчмарк Bronze-слоя: один и тот же sf10 (customer + orders + lineitem) пишется
# в разных форматах/кодеках, затем на каждой копии гоняется запрос варианта (TPC-H Q3).
#
# Для каждой конфигурации:
#   1) CTAS трёх таблиц в схему bronze.bench_<формат>_<кодек>  -> время записи
#   2) размер данных = sum(file_size_in_bytes) из $files        -> МБ, число файлов
#   3) "холодный" Q3: restart trino + minio + сброс page cache VM Docker
#   4) три "тёплых" Q3 подряд
#   5) время каждого запроса берём из system.runtime.queries (чистое время исполнения),
#      параллельно пишем wall-clock bash (включает старт CLI ~1 с)
#   6) схему удаляем, чтобы не занимать диск
# Результат: results/benchmark.csv
set -euo pipefail
cd "$(dirname "$0")/.."

SF=${SF:-sf10}
CONFIGS=${CONFIGS:-"PARQUET:ZSTD PARQUET:GZIP PARQUET:SNAPPY PARQUET:NONE ORC:ZSTD ORC:GZIP"}
OUT=${OUT:-results/benchmark.csv}
mkdir -p results
[ -f "$OUT" ] || echo "format,codec,table,rows,files,bytes,write_exec_ms,write_wall_s" > "$OUT"
QOUT=${QOUT:-results/benchmark_q3.csv}
[ -f "$QOUT" ] || echo "format,codec,run,exec_ms,wall_s" > "$QOUT"

trino() { MSYS_NO_PATHCONV=1 docker exec -i trino trino --output-format CSV "$@"; }

wait_trino() {
  until MSYS_NO_PATHCONV=1 docker exec trino trino --execute "SELECT 1" >/dev/null 2>&1; do sleep 2; done
}

now() { date +%s.%N; }

for cfg in $CONFIGS; do
  FMT=${cfg%%:*}; CODEC=${cfg##*:}
  S="bench_$(echo "$FMT" | tr A-Z a-z)_$(echo "$CODEC" | tr A-Z a-z)"
  echo "=== $FMT / $CODEC -> bronze.$S"
  trino --execute "CREATE SCHEMA IF NOT EXISTS bronze.$S" >/dev/null

  for spec in "customer:" "orders:, partitioning = ARRAY['year(orderdate)']" "lineitem:, partitioning = ARRAY['year(shipdate)']"; do
    T=${spec%%:*}; PART=${spec#*:}
    TAG="bench-write-$S-$T"
    t0=$(now)
    trino --execute "SET SESSION bronze.compression_codec = '$CODEC';
      CREATE TABLE bronze.$S.$T WITH (format = '$FMT'$PART)
      AS SELECT /* $TAG */ x.*, current_timestamp AS _loaded_at, 'tpch.$SF' AS _source FROM tpch.$SF.$T x" >/dev/null
    wall=$(awk -v a="$(now)" -v b="$t0" 'BEGIN{printf "%.2f", a-b}')
    read -r rows files bytes < <(trino --execute "SELECT sum(record_count), count(*), sum(file_size_in_bytes) FROM bronze.$S.\"$T\$files\"" | tr -d '"' | tr ',' ' ')
    exec_ms=$(trino --execute "SELECT date_diff('millisecond', started, \"end\") FROM system.runtime.queries WHERE query LIKE '%/* $TAG */%' AND query NOT LIKE '%runtime.queries%' AND state='FINISHED' ORDER BY created DESC LIMIT 1" | tr -d '"')
    echo "$FMT,$CODEC,$T,$rows,$files,$bytes,$exec_ms,$wall" | tee -a "$OUT"
  done

  Q3="SELECT /* TAG */ l.orderkey, sum(l.extendedprice * (1 - l.discount)) AS revenue, o.orderdate, o.shippriority
      FROM bronze.$S.customer c
      JOIN bronze.$S.orders   o ON c.custkey = o.custkey
      JOIN bronze.$S.lineitem l ON l.orderkey = o.orderkey
      WHERE c.mktsegment = 'BUILDING' AND o.orderdate < DATE '1995-03-15' AND l.shipdate > DATE '1995-03-15'
      GROUP BY l.orderkey, o.orderdate, o.shippriority ORDER BY revenue DESC LIMIT 10"

  # холодный старт: перезапуск движка и хранилища + сброс page cache ядра VM Docker
  docker restart trino lh-minio >/dev/null
  docker run --rm --privileged alpine:3.20 sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
  wait_trino

  for run in cold warm1 warm2 warm3; do
    TAG="bench-q3-$S-$run"
    t0=$(now)
    trino --execute "${Q3/TAG/$TAG}" >/dev/null
    wall=$(awk -v a="$(now)" -v b="$t0" 'BEGIN{printf "%.2f", a-b}')
    stats=$(trino --execute "SELECT date_diff('millisecond', started, \"end\") FROM system.runtime.queries WHERE query LIKE '%/* $TAG */%' AND query NOT LIKE '%runtime.queries%' AND state='FINISHED' ORDER BY created DESC LIMIT 1" | tr -d '"')
    echo "$FMT,$CODEC,$run,$stats,$wall" | tee -a "$QOUT"
  done

  if [ "${KEEP:-0}" != "1" ]; then
    for T in customer orders lineitem; do trino --execute "DROP TABLE bronze.$S.$T" >/dev/null; done
    trino --execute "DROP SCHEMA bronze.$S" >/dev/null
  fi
done
echo "готово: $OUT, $QOUT"
