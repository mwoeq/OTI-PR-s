#!/usr/bin/env bash
# Часть 2: schema evolution и восстановление из снапшота (time travel) на Silver.
# Таблица: silver.lakehouse.fct_order_lines. Лог выполнения -> results/schema_evolution_time_travel.log
set -euo pipefail
cd "$(dirname "$0")/.."
LOG=results/schema_evolution_time_travel.log
T=silver.lakehouse.fct_order_lines
SNAP='silver.lakehouse."fct_order_lines$snapshots"'
FILES='silver.lakehouse."fct_order_lines$files"'
HIST='silver.lakehouse."fct_order_lines$history"'

q()  { MSYS_NO_PATHCONV=1 docker exec -i trino trino --output-format ALIGNED --execute "$1" 2>/dev/null; }
q1() { MSYS_NO_PATHCONV=1 docker exec -i trino trino --output-format CSV --execute "$1" 2>/dev/null | tr -d '"'; }
step() { printf '\n### %s\n' "$1"; printf -- '-- SQL: %s\n' "$2"; q "$2"; }

{
echo "=== SCHEMA EVOLUTION ==="
step "0. Исходная схема и файлы" "DESCRIBE $T"
step "0. Снапшоты до изменений"  "SELECT snapshot_id, committed_at, operation FROM $SNAP ORDER BY committed_at"
S0=$(q1 "SELECT snapshot_id FROM $SNAP ORDER BY committed_at DESC LIMIT 1")
F0=$(q1 "SELECT count(*) FROM $FILES")
echo "snapshot S0 = $S0, файлов данных = $F0"

step "1. ADD COLUMN gross_revenue (выручка без скидки)" \
     "ALTER TABLE $T ADD COLUMN gross_revenue decimal(18,4)"
step "1a. Старые строки получили NULL, файлы НЕ переписаны" \
     "SELECT count(*) AS rows, count(gross_revenue) AS filled, (SELECT count(*) FROM $FILES) AS data_files FROM $T"

step "2. Заполняем новую колонку (UPDATE = новый снапшот)" \
     "UPDATE $T SET gross_revenue = extendedprice"
step "2a. Проверка" "SELECT count(gross_revenue) AS filled, sum(gross_revenue) - sum(net_revenue) AS discount_total FROM $T"

step "3. RENAME COLUMN ship_lag_days -> days_to_ship" \
     "ALTER TABLE $T RENAME COLUMN ship_lag_days TO days_to_ship"
step "3a. Новая схема" "DESCRIBE $T"
step "3b. Чтение старого снапшота S0 — там ещё старая схема (без gross_revenue)" \
     "SELECT * FROM $T FOR VERSION AS OF $S0 ORDER BY orderkey, linenumber LIMIT 3"
step "3c. Текущая версия" "SELECT orderkey, linenumber, days_to_ship, net_revenue, gross_revenue FROM $T ORDER BY orderkey, linenumber LIMIT 3"

echo
echo "=== TIME TRAVEL: ошибочное удаление и восстановление ==="
GOOD=$(q1 "SELECT snapshot_id FROM $SNAP ORDER BY committed_at DESC LIMIT 1")
TS=$(q1 "SELECT CAST(committed_at AS varchar) FROM $SNAP WHERE snapshot_id = $GOOD")
echo "последний хороший снапшот GOOD = $GOOD ($TS)"
step "4. Сколько строк до аварии" "SELECT count(*) AS rows, sum(net_revenue) AS revenue FROM $T"

step "5. 'Авария': случайно удалили все заказы 1995 года" \
     "DELETE FROM $T WHERE orderdate >= DATE '1995-01-01'"
step "5a. После удаления" "SELECT count(*) AS rows, sum(net_revenue) AS revenue FROM $T"

step "6. Time travel: данные на момент GOOD по id снапшота" \
     "SELECT count(*) AS rows, sum(net_revenue) AS revenue FROM $T FOR VERSION AS OF $GOOD"
step "6a. То же по времени коммита" \
     "SELECT count(*) AS rows FROM $T FOR TIMESTAMP AS OF TIMESTAMP '$TS'"

step "7. Восстановление: откат указателя таблицы на снапшот GOOD (данные не копируются)" \
     "ALTER TABLE $T EXECUTE rollback_to_snapshot($GOOD)"
step "7a. После отката" "SELECT count(*) AS rows, sum(net_revenue) AS revenue FROM $T"
step "8. История снапшотов" \
     "SELECT h.made_current_at, h.snapshot_id, h.is_current_ancestor, s.operation FROM $HIST h JOIN $SNAP s ON h.snapshot_id = s.snapshot_id ORDER BY h.made_current_at"
} | tee "$LOG"
