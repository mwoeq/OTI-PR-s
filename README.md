# Практическая №1 — локальный Lakehouse, медальон для TPC-H Q3

**Автор:** Бубнов Дмитрий Павлович, группа БИВТ-24-6
**Вариант:** 1 — TPC-H Q3 «Shipping Priority», масштаб `sf10`

Стек: **Silo (S3, форк MinIO) → PostgreSQL → Lakekeeper (Iceberg REST Catalog) → Trino**, плюс **Apache Spark** как второй движок поверх Bronze.

📄 **Отчёт с решениями, замерами и выводами — [отчет.md](отчет.md).**

## Структура репозитория

```
docker-compose.yml          весь стек одной командой
catalog/                    каталоги Trino: bronze / silver / gold (Iceberg) + tpch (генератор)
trino/config.properties     конфиг Trino (поднят лимит памяти запроса)
sql/
  10_bronze.sql             Bronze: сырые customer / orders / lineitem из tpch.sf10
  20_silver.sql             Silver: dim_customer + fct_order_lines (очистка, обогащение, джойн)
  30_gold.sql               Gold: витрина q3_shipping_priority (топ-10)
  40_validate.sql           сверка Gold с эталонным Q3 по генератору
  50_layer_stats.sql        строки / файлы / размер каждой таблицы ($files)
scripts/
  00_download_spark_jars.sh jar'ы Iceberg для Spark
  01_init_catalog.sh        Terms of Use + 3 warehouse в Lakekeeper
  02_build_medallion.sh     bronze -> silver -> gold + проверка + статистика
  05_benchmark.sh           бенчмарк Bronze: 6 комбинаций формат × кодек, запись + Q3 cold/warm
  06_schema_evolution_time_travel.sh   schema evolution и откат на снапшот на Silver
  07_spark_bronze.sh        Spark читает Bronze через Lakekeeper (без Trino)
spark/conf/spark-defaults.conf        подключение Spark к REST-каталогу и S3
results/                    сырые результаты всех прогонов (csv / логи)
```

## Как воспроизвести

Нужен Docker Desktop (≥ 8 ГБ RAM для VM) и ~25 ГБ свободного места (для бенчмарка). Команды — в Git Bash / WSL / Linux / macOS.

```bash
docker compose up -d                      # Silo, Postgres, Lakekeeper (+migrate), Trino, создание бакетов
bash scripts/01_init_catalog.sh           # warehouse bronze / silver / gold
bash scripts/02_build_medallion.sh        # строим медальон (~5 мин на sf10)
bash scripts/05_benchmark.sh              # бенчмарк (~45 мин), результаты в results/benchmark*.csv
bash scripts/06_schema_evolution_time_travel.sh
bash scripts/00_download_spark_jars.sh && bash scripts/07_spark_bronze.sh
```

UI: Silo — http://localhost:9001 (`minioadmin` / `minioadmin`), Lakekeeper — http://localhost:8181/ui/, Trino — http://localhost:8080 (пользователь `trino`). DBeaver: `jdbc:trino://localhost:8080`.

Остановить: `docker compose stop`. Удалить всё вместе с данными: `docker compose down -v`.
