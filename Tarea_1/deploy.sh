#!/usr/bin/env bash
#
# deploy.sh — Despliegue de la infraestructura Nostr sobre Docker.
#
#   - Crea una red Docker dedicada
#   - Descarga las imágenes del relay y del cliente web
#   - Levanta ambos contenedores en esa red, publicando sus puertos al host
#   - Monta config.toml dentro del relay (descripción personalizada)
#   - Espera a que cada servicio responda antes de declarar el éxito
#
# Uso: ./deploy.sh
#
set -euo pipefail

# --------------------------- Parámetros ------------------------------------
NETWORK_NAME="${NETWORK_NAME:-nostr-net}"

RELAY_IMAGE="${RELAY_IMAGE:-scsibug/nostr-rs-relay:latest}"
CLIENT_IMAGE="${CLIENT_IMAGE:-bracr10/coracle:latest}"

RELAY_NAME="${RELAY_NAME:-nostr-relay}"
CLIENT_NAME="${CLIENT_NAME:-nostr-client}"

RELAY_HOST_PORT="${RELAY_HOST_PORT:-8080}"   # puerto en la máquina anfitriona
RELAY_CONTAINER_PORT=8080                    # el relay siempre expone 8080
CLIENT_HOST_PORT="${CLIENT_HOST_PORT:-3000}" # puerto en la máquina anfitriona
CLIENT_CONTAINER_PORT="${CLIENT_CONTAINER_PORT:-}"  # vacío = autodetectar

WAIT_TIMEOUT="${WAIT_TIMEOUT:-45}"           # segundos de espera por servicio

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.toml"
CONTAINER_CONFIG_PATH="/usr/src/app/config.toml"

# --------------------------- Utilidades ------------------------------------
log()  { printf '\033[1;34m[+]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[✓]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[✗]\033[0m %s\n' "$*" >&2; exit 1; }

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -Fxq "$1"
}

# Espera a que un puerto HTTP del host responda algo (no importa el código).
wait_http() {
  local url="$1" label="$2" i=0
  log "Esperando a que ${label} responda en ${url} ..."
  while [ "$i" -lt "$WAIT_TIMEOUT" ]; do
    if curl -fsS --max-time 2 -o /dev/null "$url" 2>/dev/null; then
      ok "${label} está respondiendo."
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  warn "${label} no respondió en ${WAIT_TIMEOUT}s. Revisá: docker logs ${label}"
  return 1
}

# --------------------------- Chequeos previos ------------------------------
command -v docker >/dev/null 2>&1 || die "Docker no está instalado o no está en el PATH."
docker info >/dev/null 2>&1 || die "El demonio de Docker no está corriendo (o falta permiso: usá sudo o el grupo 'docker')."
command -v curl  >/dev/null 2>&1 || warn "curl no está instalado: se omitirán las verificaciones HTTP."

[ -f "$CONFIG_FILE" ] || die "No se encontró config.toml en ${SCRIPT_DIR}."

# Se valida SOLO la línea 'description' (los comentarios se ignoran).
DESCRIPTION_LINE="$(grep -E '^[[:space:]]*description[[:space:]]*=' "$CONFIG_FILE" | head -n1)"

[ -n "$DESCRIPTION_LINE" ] || die "config.toml no tiene una línea 'description'."

case "$DESCRIPTION_LINE" in
  *TU_USUARIO_GITHUB*)
    die "Editá config.toml y reemplazá TU_USUARIO_GITHUB por tu usuario real de GitHub antes de desplegar." ;;
esac

printf '%s\n' "$DESCRIPTION_LINE" \
  | grep -Eq '^[[:space:]]*description[[:space:]]*=[[:space:]]*"Relay local de practica para Docker - .+"' \
  || die "La línea 'description' no tiene el formato exigido: Relay local de practica para Docker - USUARIO"

log "Descripción a publicar: ${DESCRIPTION_LINE#*= }"

for c in "$RELAY_NAME" "$CLIENT_NAME"; do
  if container_exists "$c"; then
    die "El contenedor '${c}' ya existe. Ejecutá ./cleanup.sh antes de volver a desplegar."
  fi
done

# --------------------------- Plataforma ------------------------------------
# La imagen del cliente solo está publicada para linux/amd64.
# En hosts ARM64 (Apple Silicon, etc.) se fuerza esa plataforma y Docker la emula.
CLIENT_PLATFORM="${CLIENT_PLATFORM:-}"
if [ -z "$CLIENT_PLATFORM" ]; then
  HOST_ARCH="$(docker version --format '{{.Server.Arch}}' 2>/dev/null || uname -m)"
  case "$HOST_ARCH" in
    arm64|aarch64) CLIENT_PLATFORM="linux/amd64" ;;
  esac
fi

PLATFORM_ARGS=()
if [ -n "$CLIENT_PLATFORM" ]; then
  PLATFORM_ARGS=(--platform "$CLIENT_PLATFORM")
  warn "Host ARM64 detectado: el cliente correrá emulado como ${CLIENT_PLATFORM} (puede tardar más en levantar)."
fi

# --------------------------- 1. Red ----------------------------------------
if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  ok "La red '${NETWORK_NAME}' ya existe, se reutiliza."
else
  log "Creando la red '${NETWORK_NAME}' ..."
  docker network create "$NETWORK_NAME" >/dev/null
  ok "Red '${NETWORK_NAME}' creada."
fi

# --------------------------- 2. Imágenes -----------------------------------
log "Descargando ${RELAY_IMAGE} ..."
docker pull "$RELAY_IMAGE" >/dev/null

log "Descargando ${CLIENT_IMAGE} ${CLIENT_PLATFORM:+(plataforma ${CLIENT_PLATFORM})} ..."
docker pull ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"} "$CLIENT_IMAGE" >/dev/null
ok "Imágenes disponibles localmente."

# Puerto interno del cliente: se lee de la propia imagen en vez de asumirlo.
if [ -z "$CLIENT_CONTAINER_PORT" ]; then
  CLIENT_CONTAINER_PORT="$(
    docker image inspect "$CLIENT_IMAGE" \
      --format '{{range $p, $_ := .Config.ExposedPorts}}{{$p}} {{end}}' 2>/dev/null \
    | tr ' ' '\n' | grep -m1 '/tcp' | cut -d/ -f1 || true
  )"
  CLIENT_CONTAINER_PORT="${CLIENT_CONTAINER_PORT:-80}"
fi
log "Puerto interno del cliente: ${CLIENT_CONTAINER_PORT}/tcp"

# --------------------------- 3. Relay --------------------------------------
log "Levantando el relay '${RELAY_NAME}' ..."
docker run -d \
  --name "$RELAY_NAME" \
  --network "$NETWORK_NAME" \
  -p "${RELAY_HOST_PORT}:${RELAY_CONTAINER_PORT}" \
  --mount type=bind,src="${CONFIG_FILE}",dst="${CONTAINER_CONFIG_PATH}",readonly \
  --restart unless-stopped \
  "$RELAY_IMAGE" >/dev/null
ok "Relay iniciado en http://localhost:${RELAY_HOST_PORT} (ws://localhost:${RELAY_HOST_PORT})"

sleep 3   # pausa: el contenedor recién creado todavía no atiende conexiones
if command -v curl >/dev/null 2>&1; then
  wait_http "http://localhost:${RELAY_HOST_PORT}" "$RELAY_NAME" || true
fi

# --------------------------- 4. Cliente web --------------------------------
log "Levantando el cliente web '${CLIENT_NAME}' ..."
docker run -d \
  ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"} \
  --name "$CLIENT_NAME" \
  --network "$NETWORK_NAME" \
  -p "${CLIENT_HOST_PORT}:${CLIENT_CONTAINER_PORT}" \
  --restart unless-stopped \
  "$CLIENT_IMAGE" >/dev/null
ok "Cliente iniciado en http://localhost:${CLIENT_HOST_PORT}"

sleep 3
if command -v curl >/dev/null 2>&1; then
  wait_http "http://localhost:${CLIENT_HOST_PORT}" "$CLIENT_NAME" || true
fi

# --------------------------- 5. Verificación -------------------------------
echo
log "Estado de los contenedores:"
docker ps --filter "network=${NETWORK_NAME}" \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

if command -v curl >/dev/null 2>&1; then
  echo
  log "Documento NIP-11 del relay (debe mostrar la descripción configurada):"
  curl -fsS -H 'Accept: application/nostr+json' "http://localhost:${RELAY_HOST_PORT}" \
    || warn "No se pudo leer el NIP-11 del relay."
  echo
fi

cat <<EOF

------------------------------------------------------------------
Despliegue completo.

  Cliente web : http://localhost:${CLIENT_HOST_PORT}
  Relay       : ws://localhost:${RELAY_HOST_PORT}
  Red Docker  : ${NETWORK_NAME}

Para la evidencia: abrí el cliente, entrá a "Relays", agregá / buscá
ws://localhost:${RELAY_HOST_PORT} y tocá "Info". Ahí tiene que verse la
descripción definida en config.toml.

Para desmontar todo: ./cleanup.sh
------------------------------------------------------------------
EOF