#!/usr/bin/env bash
set -uo pipefail
# Unabhängige Off-Site-Backup-Verifikation von netcup aus.
# restic check (+2% Daten-Stichprobe) des EIGENEN Repos → beweist Lesbarkeit/Integrität
# der Hetzner-Kopie von einem 3. Ort, unabhängig vom Heim.
# Phase B: weitere Host-Repos, sobald deren restic-Passwörter hier escrowed sind.
ENV_FILE="${ENV_FILE:-/opt/netcup-sentinel/.env}"
[ -r "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
RESTIC_ENV="${RESTIC_ENV:-/etc/default/restic-backup}"
[ -r "$RESTIC_ENV" ] && { set -a; . "$RESTIC_ENV"; set +a; }
log(){ printf '[backup-verify %s] %s\n' "$(date -Iseconds)" "$*"; }
notify(){ [ -n "${NTFY_URL:-}" ] && [ -n "${NTFY_TOPIC:-}" ] || return 0
  curl -s -m 10 -H "Title: $1" -H "Priority: ${3:-4}" ${NTFY_TOKEN:+-H "Authorization: Bearer $NTFY_TOKEN"} \
    -d "$2" "${NTFY_URL%/}/${NTFY_TOPIC}" >/dev/null 2>&1 || true; }

command -v restic >/dev/null 2>&1 || { log "restic nicht installiert"; exit 0; }
[ -n "${RESTIC_REPOSITORY:-}" ] || { log "RESTIC_REPOSITORY nicht gesetzt"; exit 2; }
log "restic check ${RESTIC_REPOSITORY}"
if restic check --read-data-subset=2% > /tmp/backup-verify.out 2>&1; then
  log "OK, Off-Site-Repo lesbar & integer ($(tail -1 /tmp/backup-verify.out))"
  exit 0
fi

# Ab hier ist die Prüfung fehlgeschlagen. Zwei grundverschiedene Fälle, die früher
# denselben Alarmtext bekamen und beide mit exit 0 endeten (2026-09-05 korrigiert):
#
#   Lock        -> es wurde GAR NICHT geprüft. Über die Integrität ist damit nichts
#                  gesagt. Der alte Text "Off-Site-Integrität prüfen" schickte in die
#                  falsche Richtung. Aufgetreten am 23.08. und 30.08.: ein stale Lock vom
#                  22.08. blockierte beide Läufe, der letzte echte Nachweis war der 16.08.
#   Integrität  -> es wurde geprüft und etwas ist kaputt. Das ist der Ernstfall.
#
# In BEIDEN Fällen jetzt exit 1: sonst meldet systemd "Finished successfully", und der
# systemd-timer-watcher auf host sieht als zweiter, unabhängiger Melder nichts.
if grep -qiE "repository is already locked|unable to create lock" /tmp/backup-verify.out; then
  seit="$(grep -oiE "lock was created at [^(]*" /tmp/backup-verify.out | head -1)"
  log "BLOCKIERT: restic check kam nicht an das Repo, ${seit:-Lock-Zeitpunkt unbekannt}"
  tail -5 /tmp/backup-verify.out
  notify "Sentinel: Backup-Verify BLOCKIERT (Lock)" \
    "restic check ($(hostname -s), ${RESTIC_REPOSITORY}) konnte nicht laufen: ${seit:-Lock}. Es ist NICHT geprüft worden, das sagt nichts über die Integrität. Stale Lock lösen: restic unlock" 4
  exit 1
fi

log "FEHLER:"; tail -5 /tmp/backup-verify.out
notify "⚠️ Sentinel: Backup-Verify FEHLGESCHLAGEN" "restic check ($(hostname -s), ${RESTIC_REPOSITORY}) meldet Fehler, Off-Site-Integrität prüfen!" 5
exit 1
