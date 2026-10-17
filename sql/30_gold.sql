-- =====================================================================
-- GOLD: витрина-ответ на TPC-H Q3 «Shipping Priority» — топ-10 заказов по выручке
-- Формат PARQUET, кодек SNAPPY (10 строк — важна совместимость с BI, а не степень сжатия).
-- =====================================================================
SET SESSION gold.compression_codec = 'SNAPPY';

CREATE SCHEMA IF NOT EXISTS gold.lakehouse;

DROP TABLE IF EXISTS gold.lakehouse.q3_shipping_priority;
CREATE TABLE gold.lakehouse.q3_shipping_priority
WITH (format = 'PARQUET')
AS
SELECT row_number() OVER (ORDER BY revenue DESC) AS revenue_rank,
       orderkey, revenue, orderdate, shippriority
FROM (
  SELECT orderkey,
         CAST(sum(net_revenue) AS decimal(18,4)) AS revenue,
         orderdate,
         shippriority
  FROM silver.lakehouse.fct_order_lines
  GROUP BY orderkey, orderdate, shippriority
  ORDER BY revenue DESC
  LIMIT 10
);
