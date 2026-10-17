-- Строки / файлы / размер данных (МБ) каждой таблицы медальона — по системной таблице Iceberg $files
SELECT 'bronze' AS layer, 'customer' AS tbl, sum(record_count) AS rows, count(*) AS files, round(sum(file_size_in_bytes)/1048576.0, 2) AS mb FROM bronze.lakehouse."customer$files"
UNION ALL SELECT 'bronze', 'orders',          sum(record_count), count(*), round(sum(file_size_in_bytes)/1048576.0, 2) FROM bronze.lakehouse."orders$files"
UNION ALL SELECT 'bronze', 'lineitem',        sum(record_count), count(*), round(sum(file_size_in_bytes)/1048576.0, 2) FROM bronze.lakehouse."lineitem$files"
UNION ALL SELECT 'silver', 'dim_customer',    sum(record_count), count(*), round(sum(file_size_in_bytes)/1048576.0, 2) FROM silver.lakehouse."dim_customer$files"
UNION ALL SELECT 'silver', 'fct_order_lines', sum(record_count), count(*), round(sum(file_size_in_bytes)/1048576.0, 2) FROM silver.lakehouse."fct_order_lines$files"
UNION ALL SELECT 'gold',   'q3_shipping_priority', sum(record_count), count(*), round(sum(file_size_in_bytes)/1048576.0, 4) FROM gold.lakehouse."q3_shipping_priority$files";
