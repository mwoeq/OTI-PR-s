-- =====================================================================
-- SILVER: очищенные и обогащённые данные
--  1) dim_customer   — справочник клиентов: дедупликация, нормализация строк
--  2) fct_order_lines — факт "строки заказов" сегмента BUILDING в окне Q3:
--     джойн lineitem ⋈ orders ⋈ dim_customer, проверки качества, расчёт выручки
-- Формат PARQUET, кодек ZSTD. Без партиций: таблицы маленькие (см. отчёт).
-- =====================================================================
SET SESSION silver.compression_codec = 'ZSTD';

CREATE SCHEMA IF NOT EXISTS silver.lakehouse;

-- 1. Клиенты: оставляем последнюю загруженную версию каждого custkey,
--    сегмент приводим к UPPER/TRIM (защита от 'building ' и т.п. в сырых данных)
DROP TABLE IF EXISTS silver.lakehouse.dim_customer;
CREATE TABLE silver.lakehouse.dim_customer
WITH (format = 'PARQUET')
AS
SELECT custkey,
       trim(name)                AS name,
       nationkey,
       upper(trim(mktsegment))   AS mktsegment,
       CAST(acctbal AS decimal(12,2)) AS acctbal,
       _loaded_at
FROM (
  SELECT c.*,
         row_number() OVER (PARTITION BY custkey ORDER BY _loaded_at DESC) AS rn
  FROM bronze.lakehouse.customer c
)
WHERE rn = 1;

-- 2. Факт строк заказов для Q3.
--    Очистка: отбрасываем строки с некорректной ценой/скидкой и отгрузкой раньше заказа.
--    Обогащение: net_revenue = extendedprice * (1 - discount) (считаем один раз здесь,
--    а не в каждом отчёте), ship_lag_days — сколько дней от заказа до отгрузки.
DROP TABLE IF EXISTS silver.lakehouse.fct_order_lines;
CREATE TABLE silver.lakehouse.fct_order_lines
WITH (format = 'PARQUET')
AS
SELECT l.orderkey,
       l.linenumber,
       o.custkey,
       c.mktsegment,
       o.orderdate,
       CAST(o.shippriority AS integer)                         AS shippriority,
       l.shipdate,
       date_diff('day', o.orderdate, l.shipdate)               AS ship_lag_days,
       CAST(l.extendedprice AS decimal(15,2))                  AS extendedprice,
       CAST(l.discount      AS decimal(4,2))                   AS discount,
       CAST(l.extendedprice * (1 - l.discount) AS decimal(18,4)) AS net_revenue
FROM bronze.lakehouse.lineitem      l
JOIN bronze.lakehouse.orders        o ON l.orderkey = o.orderkey
JOIN silver.lakehouse.dim_customer  c ON c.custkey  = o.custkey
WHERE c.mktsegment = 'BUILDING'
  AND o.orderdate <  DATE '1995-03-15'
  AND l.shipdate  >  DATE '1995-03-15'
  -- проверки качества
  AND l.extendedprice > 0
  AND l.discount BETWEEN 0 AND 1
  AND l.shipdate >= o.orderdate;
