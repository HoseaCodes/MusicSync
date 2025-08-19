#!/usr/bin/env bash
# Auto-pair, trust, connect; wait for PulseAudio; set default sink

MAC="41:42:42:39:FA:61"
TRIES=10          # BT connection attempts
SLEEP_BETWEEN=5   # seconds between BT attempts

log(){ echo "[bt-autoconnect] $*"; logger -t bt-autoconnect "$*"; }
set -u

bt(){ /usr/bin/bluetoothctl "$@"; }
is_connected(){ bt info "$MAC" 2>/dev/null | grep -q "Connected: yes"; }
is_paired(){    bt info "$MAC" 2>/dev/null | grep -q "Paired: yes"; }
is_trusted(){   bt info "$MAC" 2>/dev/null | grep -q "Trusted: yes"; }

# --- wait for bluetoothd ---------------------------------------------------
log "Waiting for bluetooth.service…"
for _ in $(seq 1 20); do
  systemctl is-active --quiet bluetooth.service && { log "bluetooth.service is active."; break; }
  sleep 1
done

# --- power on & agent ------------------------------------------------------
rfkill unblock bluetooth 2>/dev/null || true
bt power on >/dev/null 2>&1 || true
bt agent on >/dev/null 2>&1 || true
bt default-agent >/dev/null 2>&1 || true

# --- ensure paired/trusted -------------------------------------------------
if ! is_paired; then
  log "Not paired; attempting pair… (put speaker in pairing mode if needed)"
  bt pair "$MAC" >/dev/null 2>&1 || true
fi
if ! is_trusted; then
  log "Marking device trusted…"
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

# --- PulseAudio: wait until user PA is ready (retry up to ~30s) -----------
for i in $(seq 1 15); do
  if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    # Prefer A2DP when possible
    if pactl list cards short | grep -q "bluez_card"; then
      CARD=$(pactl list cards short | awk '/bluez_card/ {print $1; exit}')
      pactl set-card-profile "$CARD" a2dp-sink >/dev/null 2>&1 || true
    fi
    SINK=$(pactl list short sinks | awk '/bluez/ {print $1; exit}')
    if [ -n "$SINK" ]; then
      pactl set-default-sink "$SINK" >/dev/null 2>&1 || true
      log "Default sink set to $SINK."
      break
    fi
  fi
  log "PulseAudio not ready yet (attempt $i)…"
  sleep 2
done

log "Done."
exit 0