-- Проверка корректности: Gold должен совпасть с эталонным Q3, посчитанным напрямую по генератору tpch.sf10.
-- Обе разности должны быть пустыми (0 строк).
WITH ref AS (
  SELECT l.orderkey,
         CAST(sum(l.extendedprice * (1 - l.discount)) AS decimal(18,4)) AS revenue,
         o.orderdate, o.shippriority
  FROM tpch.sf10.customer c
  JOIN tpch.sf10.orders   o ON c.custkey = o.custkey
  JOIN tpch.sf10.lineitem l ON l.orderkey = o.orderkey
  WHERE c.mktsegment = 'BUILDING'
    AND o.orderdate < DATE '1995-03-15'
    AND l.shipdate  > DATE '1995-03-15'
  GROUP BY l.orderkey, o.orderdate, o.shippriority
  ORDER BY revenue DESC
  LIMIT 10
),
gold AS (
  SELECT orderkey, revenue, orderdate, shippriority FROM gold.lakehouse.q3_shipping_priority
)
SELECT 'ref_minus_gold' AS diff, count(*) AS rows FROM (SELECT * FROM ref EXCEPT SELECT * FROM gold)
UNION ALL
SELECT 'gold_minus_ref', count(*) FROM (SELECT * FROM gold EXCEPT SELECT * FROM ref);
