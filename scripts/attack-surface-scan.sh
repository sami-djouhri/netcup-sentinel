#!/usr/bin/env bash
set -uo pipefail
# Externer Angriffsflächen-Scan der Heim-Public-IP von netcup aus (Angreifer-Perspektive
#, das kann kein internes Tool). Alarm via ntfy bei NEU offenen Ports ggü. Baseline.
# Erwartung: nur 51820/udp (WireGuard) offen; alles andere via Cloudflare Tunnel = kein Port.
#
# ★ STILLGELEGT am 2026-09-05, sentinel-scan.timer ist disabled.
# Der Scan lief seit dem 22.07. in 30 von 30 Läufen als no-op, weil HOME_PUBLIC_HOST nie
# gesetzt war: die Heim-Adresse ist eine dynamische DSL-Adresse, und Caddy führt kein
# Access-Log, aus dem sich die Absenderadresse der Heartbeats ableiten liesse. Ein Timer,
# der nie etwas tut, aber in jeder Übersicht als aktiver Wächter erscheint, ist
# irreführender als gar kein Timer.
# Wiederbeleben: erst einen Weg schaffen, die aktuelle Heim-Adresse hierher zu melden
# (z. B. ausgehender Push von host), dann HOME_PUBLIC_HOST setzen und den Timer enablen.
ENV_FILE="${ENV_FILE:-/opt/netcup-sentinel/.env}"
[ -r "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
BASELINE="${BASELINE:-/opt/netcup-sentinel/scan-baseline.txt}"
HOST="${HOME_PUBLIC_HOST:-}"
log(){ printf '[attack-scan %s] %s\n' "$(date -Iseconds)" "$*"; }
notify(){ [ -n "${NTFY_URL:-}" ] && [ -n "${NTFY_TOPIC:-}" ] || return 0
  curl -s -m 10 -H "Title: $1" -H "Priority: ${3:-4}" ${NTFY_TOKEN:+-H "Authorization: Bearer $NTFY_TOKEN"} \
    -d "$2" "${NTFY_URL%/}/${NTFY_TOPIC}" >/dev/null 2>&1 || true; }

if [ -z "$HOST" ] || [ "$HOST" = "CHANGE-ME" ]; then
  log "HOME_PUBLIC_HOST nicht gesetzt (DDNS-Name/IP des Heims) → no-op. In .env setzen."; exit 0; fi
command -v nmap >/dev/null 2>&1 || { log "nmap nicht installiert (apt-get install -y nmap)"; exit 0; }

CUR=$(nmap -Pn -T4 --top-ports 1000 "$HOST" 2>/dev/null | awk '/^[0-9]+\/tcp/ && /open/ {print $1}' | sort)
if [ ! -f "$BASELINE" ]; then
  printf '%s\n' "$CUR" > "$BASELINE"
  log "Baseline erstellt: $(echo "$CUR" | tr '\n' ' ')"
  notify "Sentinel: Scan-Baseline erstellt" "Offene TCP-Ports auf ${HOST}: $(echo "$CUR" | tr '\n' ' ')" 3
  exit 0
fi
NEW=$(comm -13 "$BASELINE" <(printf '%s\n' "$CUR"))
if [ -n "$NEW" ]; then
  log "NEU offene Ports: $(echo "$NEW" | tr '\n' ' ')"
  notify "⚠️ Sentinel: NEUE offene Ports am Heim!" "Neu erreichbar auf ${HOST}: $(echo "$NEW" | tr '\n' ' '), versehentliche Exposition prüfen!" 5
else
  log "keine neuen Ports ggü. Baseline (ok)"
fi
