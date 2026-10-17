-- =====================================================================
-- BRONZE: сырые таблицы TPC-H "как пришли" (все колонки) + технические поля загрузки
-- Масштаб: sf10. Формат PARQUET, кодек ZSTD.
-- Партиционирование: orders по year(orderdate), lineitem по year(shipdate) —
-- ровно те колонки, по которым Q3 фильтрует диапазоны дат (partition pruning).
-- customer маленький (1.5 млн строк) — без партиций, чтобы не плодить мелкие файлы.
-- =====================================================================
SET SESSION bronze.compression_codec = 'ZSTD';

CREATE SCHEMA IF NOT EXISTS bronze.lakehouse;

DROP TABLE IF EXISTS bronze.lakehouse.customer;
CREATE TABLE bronze.lakehouse.customer
WITH (format = 'PARQUET')
AS SELECT c.*,
          current_timestamp AS _loaded_at,
          'tpch.sf10'       AS _source
   FROM tpch.sf10.customer c;

DROP TABLE IF EXISTS bronze.lakehouse.orders;
CREATE TABLE bronze.lakehouse.orders
WITH (format = 'PARQUET', partitioning = ARRAY['year(orderdate)'])
AS SELECT o.*,
          current_timestamp AS _loaded_at,
          'tpch.sf10'       AS _source
   FROM tpch.sf10.orders o;

DROP TABLE IF EXISTS bronze.lakehouse.lineitem;
CREATE TABLE bronze.lakehouse.lineitem
WITH (format = 'PARQUET', partitioning = ARRAY['year(shipdate)'])
AS SELECT l.*,
          current_timestamp AS _loaded_at,
          'tpch.sf10'       AS _source
   FROM tpch.sf10.lineitem l;
