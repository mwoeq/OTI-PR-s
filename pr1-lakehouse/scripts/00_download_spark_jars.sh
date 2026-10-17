#!/usr/bin/env bash
# Скачивает jar'ы Iceberg для Spark (нужны только для части 2.2, scripts/07_spark_bronze.sh)
set -euo pipefail
cd "$(dirname "$0")/../spark/jars"
M=https://repo1.maven.org/maven2/org/apache/iceberg
curl -fsSL -o iceberg-spark-runtime-3.5_2.12-1.7.1.jar $M/iceberg-spark-runtime-3.5_2.12/1.7.1/iceberg-spark-runtime-3.5_2.12-1.7.1.jar
curl -fsSL -o iceberg-aws-bundle-1.7.1.jar             $M/iceberg-aws-bundle/1.7.1/iceberg-aws-bundle-1.7.1.jar
ls -l
