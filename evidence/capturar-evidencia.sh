#!/usr/bin/env bash
#
# Captura la evidencia del flujo cache MISS -> HIT -> objeto en S3.
# Requiere que `terraform apply` ya se haya ejecutado en ../terraform.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$HERE/../terraform"

echo "==> Leyendo outputs de Terraform..."
API_URL="$(cd "$TF_DIR" && terraform output -raw process_url)"
BUCKET="$(cd "$TF_DIR" && terraform output -raw s3_bucket_name)"

PAYLOAD='{"message":"evidencia-sre","n":42}'

echo "==> URL:    $API_URL"
echo "==> Bucket: $BUCKET"
echo

echo "==> 1ª llamada (se espera X-Cache: MISS)"
curl -s -i -X POST "$API_URL" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" | tee "$HERE/01-miss.txt"
echo; echo

echo "==> 2ª llamada idéntica (se espera X-Cache: HIT)"
curl -s -i -X POST "$API_URL" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" | tee "$HERE/02-hit.txt"
echo; echo

echo "==> Objeto(s) en S3"
aws s3 ls "s3://$BUCKET/results/" --recursive | tee "$HERE/03-s3-ls.txt"
echo

echo "==> Resumen X-Cache:"
grep -i -h 'x-cache' "$HERE/01-miss.txt" "$HERE/02-hit.txt" || true

echo
echo "Listo. Evidencia en: $HERE/{01-miss,02-hit,03-s3-ls}.txt"
