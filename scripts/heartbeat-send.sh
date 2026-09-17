#!/usr/bin/env bash
set -uo pipefail
# Heim→netcup Heartbeat (Dead-Man-Switch). Läuft als systemd-Timer auf host (+node1).
# Bleibt der Push aus, alarmiert Gatus auf netcup über den home-unabhängigen ntfy-Kanal.
# Config: /etc/default/netcup-heartbeat  (STATUS_BASE, HEARTBEAT_TOKEN, HB_HOST)
CFG="${CFG:-/etc/default/netcup-heartbeat}"
[ -r "$CFG" ] && . "$CFG"
STATUS_BASE="${STATUS_BASE:-https://status.djouhri.de}"
HB_HOST="${HB_HOST:-$(hostname -s)}"
KEY="heim_${HB_HOST}"
# Schreibtest VOR dem Push (2026-08-07, project_jarvis_nvme_freeze_2026-08-07):
# Beim NVMe-I/O-Fehler-Sturm lief dieser Heartbeat munter weiter - ausgehende
# Netzverbindungen funktionierten, waehrend der Host nichts mehr schreiben konnte
# (sshd nahm an ohne Banner, journald tot). Der Dead-Man-Switch schwieg dadurch
# 2h19 lang. Ein Heartbeat darf nur raus, wenn die Platte Schreiben noch annimmt.
# timeout faengt zusaetzlich den Deadlock-Fall (Schreiben haengt statt zu fehlen).
#
# HOME-Fallback (2026-08-11): systemd setzt fuer System-Services KEIN HOME. Unter
# 'set -u' brach das Script hier ab, BEVOR der Push rausging - der node1-Sender war
# dadurch seit 2026-08-08 tot (1030 Fehlschlaege). Auf host fiel es nicht auf, weil
# der Sender dort per cron laeuft und cron HOME aus /etc/passwd setzt. Der Probe-Pfad
# muss auf einer echten Platte liegen: /tmp ist auf node1 tmpfs (RAM) und wuerde den
# I/O-Test wertlos machen, /var/tmp liegt auf der Root-Platte.
HB_PROBE="${HB_PROBE:-${HOME:-/var/tmp}/.cache/netcup-heartbeat-probe}"
mkdir -p "$(dirname "$HB_PROBE")" 2>/dev/null
if ! timeout 10 bash -c 'echo alive > "$0" && sync -f "$0"' "$HB_PROBE" 2>/dev/null; then
  echo "heartbeat UNTERDRUECKT: Schreibtest auf $HB_PROBE fehlgeschlagen (I/O-Fehler oder Deadlock) -> Gatus alarmiert"
  exit 0
fi

# WICHTIG: Gatus v5 nimmt den External-Push NUR per POST an (GET → 405). Ohne -X POST
# schlägt jeder Heartbeat still fehl und der Dead-Man-Switch ist wirkungslos.
if curl -sf -m 10 -X POST -H "Authorization: Bearer ${HEARTBEAT_TOKEN:-}" \
     "${STATUS_BASE}/api/v1/endpoints/${KEY}/external?success=true" >/dev/null 2>&1; then
  echo "heartbeat ok (${KEY})"
else
  # Bewusst exit 0: das Ausbleiben erkennt GATUS (Dead-Man-Switch). Ein harter Fehler
  # hier würde nur den host-systemd-timer-watcher unnötig triggern.
  echo "heartbeat push FAILED (${KEY}) → ${STATUS_BASE} (Gatus erkennt das Ausbleiben)"
fi
