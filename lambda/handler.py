"""
Lambda de procesamiento con caché Redis y persistencia en S3.

Flujo:
    API Gateway (POST /process) -> esta Lambda -> Redis
        - cache HIT : devuelve el valor cacheado           (X-Cache: HIT)
        - cache MISS: procesa, guarda en S3, escribe Redis  (X-Cache: MISS)

La clave de caché se deriva del body del request (hash SHA-256), de modo que
dos requests idénticos consecutivos producen MISS y luego HIT.

Variables de entorno (inyectadas por Terraform):
    REDIS_HOST          host del nodo ElastiCache
    REDIS_PORT          puerto (6379)
    S3_BUCKET           bucket de resultados
    CACHE_TTL_SECONDS   TTL de las keys en Redis (60)
"""

import datetime
import hashlib
import json
import logging
import os
import uuid

import boto3
import redis

# -------------------------------------------------------------------
# Configuración y clientes (se crean una vez por contenedor, no por request)
# -------------------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

REDIS_HOST = os.environ["REDIS_HOST"]
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
S3_BUCKET = os.environ["S3_BUCKET"]
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "60"))

s3_client = boto3.client("s3")

# socket_timeout evita que la Lambda se cuelgue si Redis no responde.
redis_client = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    socket_connect_timeout=3,
    socket_timeout=3,
    decode_responses=True,
)


# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
def _response(status_code: int, body: dict, cache_state: str | None = None) -> dict:
    """Construye la respuesta en el formato que espera API Gateway (proxy)."""
    headers = {"Content-Type": "application/json"}
    if cache_state is not None:
        headers["X-Cache"] = cache_state  # HIT o MISS

    return {
        "statusCode": status_code,
        "headers": headers,
        "body": json.dumps(body),
    }


def _extract_payload(event: dict) -> str:
    """Obtiene el body crudo del evento de API Gateway (HTTP API v2 o REST)."""
    body = event.get("body")
    if body is None:
        # Permite también disparos directos (test de consola) con el payload en la raíz.
        body = json.dumps(event)
    return body


def _cache_key(payload: str) -> str:
    """Deriva una clave estable a partir del contenido del request."""
    digest = hashlib.sha256(payload.encode("utf-8")).hexdigest()
    return f"process:{digest}"


def _process(payload: str) -> dict:
    """
    Transformación de negocio (libre). Aquí: invertimos el texto y calculamos
    su hash. Es determinista para que el mismo input produzca el mismo output.
    """
    try:
        parsed = json.loads(payload)
    except (json.JSONDecodeError, TypeError):
        parsed = {"raw": payload}

    text = json.dumps(parsed, sort_keys=True)
    return {
        "input": parsed,
        "reversed": text[::-1],
        "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "length": len(text),
    }


# -------------------------------------------------------------------
# Handler
# -------------------------------------------------------------------
def handler(event, context):
    try:
        payload = _extract_payload(event)
        key = _cache_key(payload)

        # 1) Consulta Redis
        cached = redis_client.get(key)
        if cached is not None:
            logger.info("Cache HIT para key=%s", key)
            return _response(200, json.loads(cached), cache_state="HIT")

        logger.info("Cache MISS para key=%s", key)

        # 2) MISS: procesar
        result = _process(payload)
        record_id = str(uuid.uuid4())
        today = datetime.datetime.utcnow().strftime("%Y-%m-%d")
        s3_key = f"results/{today}/{record_id}.json"

        document = {
            "id": record_id,
            "cache_key": key,
            "created_at": datetime.datetime.utcnow().isoformat() + "Z",
            "result": result,
        }

        # 3) Guardar en S3 (tráfico vía VPC Endpoint Gateway)
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(document).encode("utf-8"),
            ContentType="application/json",
        )
        logger.info("Guardado en s3://%s/%s", S3_BUCKET, s3_key)

        # 4) Escribir en Redis con TTL explícito
        document["s3_key"] = s3_key
        redis_client.set(key, json.dumps(document), ex=CACHE_TTL_SECONDS)
        logger.info("Escrito en Redis con TTL=%ss", CACHE_TTL_SECONDS)

        return _response(200, document, cache_state="MISS")

    except Exception as exc:  # noqa: BLE001 - requisito: cualquier excepción -> HTTP 500
        logger.exception("Error procesando el request: %s", exc)
        return _response(
            500,
            {"error": "internal_error", "message": str(exc)},
        )
