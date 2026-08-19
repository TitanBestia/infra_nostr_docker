#!/usr/bin/env bash
#
# cleanup.sh — Deja el entorno en su estado inicial.
#
#   - Detiene y elimina los contenedores del relay y del cliente
#   - Elimina la red Docker creada por deploy.sh
#   - Lista contenedores, redes y volúmenes para comprobar que no quedó nada
#
# Uso: ./cleanup.sh
#
set -uo pipefail   # sin -e: la limpieza debe seguir aunque algo ya no exista

NETWORK_NAME="${NETWORK_NAME:-nostr-net}"
RELAY_NAME="${RELAY_NAME:-nostr-relay}"
CLIENT_NAME="${CLIENT_NAME:-nostr-client}"

log()  { printf '\033[1;34m[+]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[✓]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || { echo "Docker no está instalado." >&2; exit 1; }

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -Fxq "$1"
}

# --------------------------- Contenedores ----------------------------------
for c in "$CLIENT_NAME" "$RELAY_NAME"; do
  if container_exists "$c"; then
    log "Deteniendo '${c}' ..."
    docker stop "$c" >/dev/null 2>&1
    log "Eliminando '${c}' ..."
    docker rm -f "$c" >/dev/null 2>&1
    ok "'${c}' eliminado."
  else
    warn "El contenedor '${c}' no existe, nada que hacer."
  fi
done

# --------------------------- Red -------------------------------------------
if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  log "Eliminando la red '${NETWORK_NAME}' ..."
  if docker network rm "$NETWORK_NAME" >/dev/null 2>&1; then
    ok "Red '${NETWORK_NAME}' eliminada."
  else
    warn "No se pudo eliminar la red: puede tener contenedores todavía conectados."
  fi
else
  warn "La red '${NETWORK_NAME}' no existe, nada que hacer."
fi

# --------------------------- Comprobación ----------------------------------
echo
log "Contenedores existentes:"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
echo
log "Redes existentes:"
docker network ls
echo
log "Volúmenes existentes:"
docker volume ls
echo
ok "Entorno limpio."
