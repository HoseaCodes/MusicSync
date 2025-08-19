#!/usr/bin/env bash
# Auto-pair, trust, and connect a BT speaker; retry + set default sink

MAC="41:42:42:39:FA:61"
TRIES=10           # connection attempts
SLEEP_BETWEEN=5    # seconds between attempts

log(){ echo "[bt-autoconnect] $*"; logger -t bt-autoconnect "$*"; }

set -u

# --- helpers ---------------------------------------------------------------
bt() { /usr/bin/bluetoothctl "$@"; }

is_connected(){ bt info "$MAC" 2>/dev/null | grep -q "Connected: yes"; }
is_paired(){    bt info "$MAC" 2>/dev/null | grep -q "Paired: yes"; }
is_trusted(){   bt info "$MAC" 2>/dev/null | grep -q "Trusted: yes"; }

# --- wait for BT service ---------------------------------------------------
log "Waiting for bluetooth.service…"
for _ in $(seq 1 20); do
  systemctl is-active --quiet bluetooth.service && { log "bluetooth.service is active."; break; }
  sleep 1
done

# --- power on & agent ------------------------------------------------------
rfkill unblock bluetooth 2>/dev/null || true
bt power on   >/dev/null 2>&1 || true
bt agent on   >/dev/null 2>&1 || true
bt default-agent >/dev/null 2>&1 || true

# --- ensure paired & trusted ----------------------------------------------
if ! is_paired; then
  log "Device not paired; attempting pair…"
  # many speakers need to be in pairing mode the first time
  bt pair "$MAC" >/dev/null 2>&1 || log "Pair attempt returned non‑zero (may still succeed if already paired)."
fi

if ! is_trusted; then
  log "Marking device as trusted…"
  bt trust "$MAC" >/dev/null 2>&1 || true
fi

# --- connect with retries --------------------------------------------------
connected=0
for attempt in $(seq 1 "$TRIES"); do
  log "Attempt $attempt/$TRIES: connecting to $MAC…"
  bt connect "$MAC" >/dev/null 2>&1 || true
  if is_connected; then
    log "Connected to $MAC."
    connected=1
    break
  fi
  sleep "$SLEEP_BETWEEN"
done

if [ "$connected" -ne 1 ]; then
  log "Failed to connect after $TRIES attempts."
  exit 1
fi

# --- audio sink (best effort) ----------------------------------------------
sleep 3
if command -v pactl >/dev/null 2>&1; then
  if pactl list cards short | grep -q "bluez_card"; then
    CARD=$(pactl list cards short | awk '/bluez_card/ {print $1; exit}')
    pactl set-card-profile "$CARD" a2dp-sink >/dev/null 2>&1 || true
  fi
  SINK=$(pactl list short sinks | awk '/bluez/ {print $1; exit}')
  if [ -n "$SINK" ]; then
    pactl set-default-sink "$SINK" || true
    log "Default sink set to $SINK."
  else
    log "No bluez sink found yet; audio may route after a moment."
  fi
else
  log "pactl not found; skipping default sink selection."
fi

log "Done."
exit 0