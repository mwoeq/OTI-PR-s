#!/usr/bin/env bash
# Часть 2.2: Apache Spark читает Bronze напрямую через REST-каталог Lakekeeper и S3 (Silo),
# без участия Trino. Trino на время прогона останавливаем — и чтобы освободить RAM VM Docker (8 ГБ),
# и чтобы показать, что данные lakehouse не привязаны к одному движку.
# Лог -> results/spark_bronze.log
set -euo pipefail
cd "$(dirname "$0")/.."

docker stop trino >/dev/null && echo "trino остановлен"

SQL="
SHOW NAMESPACES IN bronze;
SHOW TABLES IN bronze.lakehouse;
DESCRIBE TABLE bronze.lakehouse.lineitem;
SELECT 'customer' t, count(*) FROM bronze.lakehouse.customer
UNION ALL SELECT 'orders', count(*) FROM bronze.lakehouse.orders
UNION ALL SELECT 'lineitem', count(*) FROM bronze.lakehouse.lineitem;
SELECT snapshot_id, committed_at, operation, summary['added-records'] AS added_records
FROM bronze.lakehouse.lineitem.snapshots;
SELECT partition, record_count, file_count FROM bronze.lakehouse.lineitem.partitions ORDER BY partition;
SELECT l.orderkey, sum(l.extendedprice * (1 - l.discount)) AS revenue, o.orderdate, o.shippriority
FROM bronze.lakehouse.customer c
JOIN bronze.lakehouse.orders   o ON c.custkey = o.custkey
JOIN bronze.lakehouse.lineitem l ON l.orderkey = o.orderkey
WHERE c.mktsegment = 'BUILDING' AND o.orderdate < DATE '1995-03-15' AND l.shipdate > DATE '1995-03-15'
GROUP BY l.orderkey, o.orderdate, o.shippriority
ORDER BY revenue DESC LIMIT 10;
"

MSYS_NO_PATHCONV=1 docker run --rm --name lh-spark \
  --network lakehouse-p1_default \
  -v "$(pwd)/spark/conf:/opt/spark/conf" \
  -v "$(pwd)/spark/jars:/opt/spark/iceberg-jars" \
  apache/spark:3.5.3 \
  /opt/spark/bin/spark-sql -e "$SQL" 2>&1 \
  | grep -v -e ' WARN ' -e 'NativeCodeLoader' -e '^Setting default log level' -e '^To adjust logging' -e '^\s*$' \
  | tee results/spark_bronze.log

docker start trino >/dev/null && echo "trino запущен снова"
