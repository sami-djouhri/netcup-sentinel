# netcup-sentinel

A small watchdog that observes a home network from outside it. It runs on a cheap
external VPS. When the power drops at home, or the uplink dies, or the server
itself hangs, this keeps running and keeps reporting.

## Why

Health checks that live on the monitored machine go down with it. What you get
then is silence, and silence is hard to tell apart from everything being fine.
Four questions need someone standing outside the house:

- Are my public endpoints actually reachable from the internet?
- Did a port unexpectedly open on my home's public IP?
- Is my off-site backup repository still intact?
- Is the home still alive at all?

## Components

- **Gatus** monitors the public endpoints and serves a status page. It also
  receives a dead-man's-switch heartbeat: the home pushes every few minutes, and
  silence past a threshold raises an alert. Notifications go out over ntfy, never
  mail, and only after repeated failures. The channel is deliberately independent
  of the home network, so the alarm survives the outage it is reporting.
- **attack-surface-scan** (`scripts/attack-surface-scan.sh`) runs an `nmap`
  against the home's public IP from the outside, which is roughly the view an
  attacker gets. It diffs against a baseline and pushes an ntfy alert when a port
  is open that was not open before. **Its timer is off.** Thirty runs in a row
  had found nothing, and not because the attack surface was clean: the home
  connection is handed a new address regularly, so by the time the scan ran there
  was no fixed target left to aim at. A check that cannot fail is worse than no
  check, because it reads as a green light. The script stays in the repository,
  since the idea is sound the moment there is a stable address to point it at.
- **backup-verify** (`scripts/backup-verify.sh`) runs `restic check` against the
  off-site backup repository from a third location and alerts on integrity
  errors. Also a systemd timer.
- **heartbeat-send** (`scripts/heartbeat-send.sh`) is the one piece that runs at
  home. It pings the sentinel on an interval. When the pings stop, the dead-man
  switch fires.

## Stack

Gatus handles uptime and the heartbeat, Caddy terminates TLS on the status page
and renews the certificate itself. The scanners are POSIX shell on systemd
timers. Alerting is ntfy; the backup target that `backup-verify` checks is a
restic repository. Deployment is an rsync to the VPS.

One detail that cost two weeks of false confidence: every Gatus condition here
starts with `[CONNECTED] == true`. On a DNS or connection failure Gatus sets the
status to `0`, and a condition that only checks an upper bound (`[STATUS] < 400`)
is then satisfied by an endpoint that never answered at all. Four hostnames that
no longer existed reported green that way.

## Config

Host-specific values live in an `.env` on the VPS (target address, ntfy channel,
tokens), so no secrets or addresses are committed here. Each script documents the
variables it needs in its header comments.

MIT licensed.

## About this snapshot

This is an extract from a private repository. A script produces it: non-public
files are dropped, internal addresses and paths are rewritten to placeholders,
and nothing is pushed unless two separate secret scanners come back clean.

You see a single commit because the development history stays private. The stack
itself is watching my own network right now.
