# Manual de despliegue en AWS — paso a paso

Guía completa para desplegar el servicio serverless (VPC + API Gateway + Lambda + Redis + S3) en una cuenta AWS real, probar el flujo cache MISS → HIT, capturar la evidencia y borrar todo al final.

> **Tiempo total:** ~20–30 min (el `apply` tarda ~8–12 min por ElastiCache).
> **Costo:** unos pocos centavos/dólares mientras el stack está arriba (lo que más cuesta es el NAT Gateway y el nodo Redis). Si haces `terraform destroy` al terminar, el gasto es mínimo.

---

## Paso 0 — Qué necesitas antes de empezar

| Requisito | Cómo comprobarlo | Si no lo tienes |
|---|---|---|
| Cuenta de AWS | — | Crea una en https://aws.amazon.com |
| Terraform >= 1.5 | `terraform version` | `brew install terraform` |
| AWS CLI v2 | `aws --version` | `brew install awscli` |
| Python 3 + pip | `python3 --version` y `pip3 --version` | `brew install python` |
| `curl` | `curl --version` | ya viene en macOS |

Ejecuta esto para verificar todo de golpe:

```bash
terraform version && aws --version && python3 --version && pip3 --version && curl --version | head -1
```

Si algún comando falla, instálalo con `brew install ...` antes de seguir.

---

## Paso 1 — Crear credenciales en AWS

Necesitas una **Access Key** de un usuario IAM con permisos para crear la infraestructura.

1. Entra a la consola de AWS → busca **IAM**.
2. **Users** → **Create user** (ej. `terraform-sre`).
3. En permisos, para una cuenta de laboratorio, adjunta la policy **AdministratorAccess**
   (en producción se usaría algo más restringido).
4. Abre el usuario → pestaña **Security credentials** → **Create access key** →
   elige **Command Line Interface (CLI)**.
5. Guarda el **Access key ID** y el **Secret access key** (el secret solo se muestra una vez).

> Si tu organización usa SSO / IAM Identity Center, sáltate esto y usa `aws sso login` según te hayan indicado.

---

## Paso 2 — Configurar la AWS CLI en tu Mac

```bash
aws configure
```

Te preguntará 4 cosas:

```
AWS Access Key ID     : (pega tu Access key ID)
AWS Secret Access Key : (pega tu Secret access key)
Default region name   : us-east-1
Default output format  : json
```

Comprueba que las credenciales funcionan:

```bash
aws sts get-caller-identity
```

Debe devolver tu `Account`, `UserId` y `Arn`. Si ves un error de credenciales, repite el paso 1–2.

---

## Paso 3 — Ir a la carpeta del proyecto

```bash
cd /Users/sergiosanchez/Documents/Antigravity/TestSRE/solucion/terraform
```

(Opcional) Si quieres cambiar la región, el nombre del proyecto o los límites de throttling,
copia el archivo de ejemplo y edítalo. Si no, se usan los valores por defecto y funciona igual:

```bash
cp terraform.tfvars.example terraform.tfvars
# edita terraform.tfvars solo si quieres cambiar algo
```

---

## Paso 4 — Inicializar Terraform

Descarga los providers (AWS, archive, random):

```bash
terraform init
```

Debe terminar con `Terraform has been successfully initialized!`.

---

## Paso 5 — Revisar el plan (opcional pero recomendado)

Ver qué va a crear **sin crear nada todavía**:

```bash
terraform plan
```

Verás algo como `Plan: 27 to add, 0 to change, 0 to destroy.` Revisa que no haya errores en rojo.

---

## Paso 6 — Desplegar el stack

Un solo comando crea TODO (VPC, subnets, NAT, VPC Endpoint, Redis, Lambda, API Gateway, S3, IAM):

```bash
terraform apply
```

Cuando te pregunte, escribe `yes` y Enter.

> Durante el `apply` también se empaqueta la Lambda automáticamente (instala `redis-py`
> y arma el zip). No tienes que hacer nada manual.

Esto tarda **~8–12 minutos**, sobre todo por la creación de ElastiCache Redis. Al terminar verás los **outputs**, por ejemplo:

```
api_endpoint         = "https://abc123.execute-api.us-east-1.amazonaws.com"
process_url          = "https://abc123.execute-api.us-east-1.amazonaws.com/process"
s3_bucket_name       = "sre-data-processor-dev-results-a1b2c3d4"
redis_endpoint       = "sre-data-processor-dev-redis.xxxx.cache.amazonaws.com"
lambda_function_name = "sre-data-processor-dev-processor"
...
```

---

## Paso 7 — Probar el flujo end-to-end (MISS → HIT)

Guarda la URL en una variable y haz dos llamadas idénticas:

```bash
API_URL=$(terraform output -raw process_url)

echo "== 1a llamada (esperado: X-Cache: MISS) =="
curl -i -X POST "$API_URL" -H 'Content-Type: application/json' -d '{"message":"hola sre"}'

echo
echo "== 2a llamada idéntica (esperado: X-Cache: HIT) =="
curl -i -X POST "$API_URL" -H 'Content-Type: application/json' -d '{"message":"hola sre"}'
```

Lo que debes ver:

- 1ª respuesta → cabecera `x-cache: MISS` y un body con `s3_key`.
- 2ª respuesta → cabecera `x-cache: HIT` con el mismo contenido (sale de la caché).

> Las dos llamadas deben hacerse dentro de los **60 segundos** del TTL. Si esperas más, la clave expira en Redis y volverás a ver MISS.

Verifica que el objeto quedó guardado en S3:

```bash
BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 ls "s3://$BUCKET/results/" --recursive
```

Debe listar algo como `results/2026-10-13/<uuid>.json`.

---

## Paso 8 — Capturar la evidencia (para el entregable)

Hay un script que hace las dos llamadas y el `s3 ls`, y guarda la salida en archivos:

```bash
cd ../evidence
./capturar-evidencia.sh
```

Genera:

- `01-miss.txt` → prueba del MISS
- `02-hit.txt`  → prueba del HIT
- `03-s3-ls.txt` → objeto en S3

Añade también capturas de pantalla de la consola de AWS si quieres reforzar la evidencia.

---

## Paso 9 — Ver los logs en CloudWatch (opcional)

Para ver qué hizo la Lambda:

```bash
cd ../terraform
LOG_GROUP=$(terraform output -raw lambda_log_group)
aws logs tail "$LOG_GROUP" --since 10m --format short
```

Verás líneas como `Cache MISS para key=...`, `Guardado en s3://...`, `Cache HIT para key=...`.

---

## Paso 10 — Borrar todo (¡IMPORTANTE para no seguir pagando!)

Cuando termines de probar y de capturar la evidencia:

```bash
cd /Users/sergiosanchez/Documents/Antigravity/TestSRE/solucion/terraform
terraform destroy
```

Escribe `yes`. Esto elimina **todos** los recursos creados. Como todo es Infraestructura como Código, no quedan recursos "fantasma" creados a mano.

Comprueba que no quedó nada relevante (opcional):

```bash
aws elasticache describe-cache-clusters --query 'CacheClusters[].CacheClusterId'
aws lambda list-functions --query 'Functions[].FunctionName'
```

---

## Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `Error: configuring Terraform AWS Provider` / `no valid credential sources` | AWS CLI no configurado | Repite Paso 2 (`aws configure`) y `aws sts get-caller-identity` |
| `UnauthorizedOperation` / `AccessDenied` al aplicar | El usuario IAM no tiene permisos suficientes | Usa un usuario con `AdministratorAccess` (Paso 1) |
| El `apply` se cuelga en ElastiCache | Es normal, tarda varios minutos | Espera; puede llegar a ~12 min |
| `pip: command not found` durante el apply | No hay pip disponible | `brew install python` y reintenta |
| Siempre veo `MISS`, nunca `HIT` | Pasaron más de 60s entre llamadas, o Redis no responde | Haz las 2 llamadas seguidas; revisa logs (Paso 9) |
| 500 Internal Server Error | La Lambda no conecta a Redis/S3 | Revisa CloudWatch (Paso 9); confirma que el `apply` terminó sin errores |
| Error de `AddressLimitExceeded` al crear el EIP del NAT | Llegaste al límite de Elastic IPs | Libera EIPs sin usar en la consola EC2, o pide aumento de límite |

---

## Resumen ultra-corto (si ya tienes todo configurado)

```bash
cd /Users/sergiosanchez/Documents/Antigravity/TestSRE/solucion/terraform
terraform init
terraform apply                                   # yes
API_URL=$(terraform output -raw process_url)
curl -i -X POST "$API_URL" -H 'Content-Type: application/json' -d '{"message":"hola"}'   # MISS
curl -i -X POST "$API_URL" -H 'Content-Type: application/json' -d '{"message":"hola"}'   # HIT
cd ../evidence && ./capturar-evidencia.sh
cd ../terraform && terraform destroy              # yes  (al terminar)
```
