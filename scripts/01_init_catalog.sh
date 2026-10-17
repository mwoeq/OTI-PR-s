#!/usr/bin/env bash
# Принимает Terms of Use Lakekeeper и регистрирует 3 warehouse (bronze/silver/gold),
# каждый смотрит в свой бакет Silo. Повторный запуск безопасен (ошибки "уже существует" игнорируются).
set -u
LK=http://localhost:8181

until curl -sf "$LK/health" >/dev/null; do echo "жду Lakekeeper..."; sleep 2; done

curl -s -o /dev/null -w "bootstrap: %{http_code}\n" -X POST "$LK/management/v1/bootstrap" \
  -H "Content-Type: application/json" -d '{"accept-terms-of-use": true}'

for layer in bronze silver gold; do
  curl -s -w "\nwarehouse $layer: %{http_code}\n" -X POST "$LK/management/v1/warehouse" \
    -H "Content-Type: application/json" -d "{
    \"warehouse-name\": \"$layer\",
    \"project-id\": \"00000000-0000-0000-0000-000000000000\",
    \"storage-profile\": {
      \"type\": \"s3\", \"bucket\": \"$layer\", \"key-prefix\": \"\",
      \"endpoint\": \"http://lh-minio:9000\", \"region\": \"us-east-1\",
      \"path-style-access\": true, \"flavor\": \"s3-compat\", \"sts-enabled\": false
    },
    \"storage-credential\": {
      \"type\": \"s3\", \"credential-type\": \"access-key\",
      \"access-key-id\": \"minioadmin\", \"secret-access-key\": \"minioadmin\"
    }
  }"
done
