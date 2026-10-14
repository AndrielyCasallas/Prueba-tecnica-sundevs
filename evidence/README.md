# Evidencia de funcionamiento

Esta carpeta debe contener la prueba de que el flujo funciona:

1. Request con `X-Cache: MISS` (primera llamada)
2. Mismo request con `X-Cache: HIT` (segunda llamada)
3. Objeto guardado en S3 (`aws s3 ls`)

## Opción A — script automático

Desde `terraform/` ya aplicado, ejecuta:

```bash
cd evidence
./capturar-evidencia.sh
```

Genera estos archivos en la carpeta:

- `01-miss.txt` — headers + body de la 1ª llamada (debe mostrar `x-cache: MISS`)
- `02-hit.txt` — headers + body de la 2ª llamada (debe mostrar `x-cache: HIT`)
- `03-s3-ls.txt` — listado del bucket mostrando el objeto `results/<fecha>/<id>.json`

Añade también capturas de pantalla (`.png`) de la consola si quieres reforzar la evidencia.

## Opción B — manual

```bash
API_URL=$(cd ../terraform && terraform output -raw process_url)
BUCKET=$(cd ../terraform && terraform output -raw s3_bucket_name)

curl -s -i -X POST "$API_URL" -H 'Content-Type: application/json' -d '{"message":"demo"}' | tee 01-miss.txt
curl -s -i -X POST "$API_URL" -H 'Content-Type: application/json' -d '{"message":"demo"}' | tee 02-hit.txt
aws s3 ls "s3://$BUCKET/results/" --recursive | tee 03-s3-ls.txt
```

> Las dos llamadas deben hacerse dentro de la ventana de TTL (60s) para que la segunda sea HIT.
