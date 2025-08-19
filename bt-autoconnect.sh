#!/usr/bin/env bash
# Robust BT autoconnect with waits + retries + logging

MAC="41:42:42:39:FA:61"
TRIES=10          # how many times to try
SLEEP_BETWEEN=5   # seconds between tries

log() { echo "[bt-autoconnect] $*"; logger -t bt-autoconnect "$*"; }

# Make sure we’re on bash and using UNIX line endings; run with: /bin/bash this_script.sh

set -u  # don’t exit on non-zero to allow retries

# Wait for the bluetooth service
log "Waiting for bluetooth.service…"
for i in $(seq 1 20); do
  if systemctl is-active --quiet bluetooth.service; then
    log "bluetooth.service is active."
    break
  fi
  sleep 1
done

# Ensure controller is powered on
rfkill unblock bluetooth 2>/dev/null || true
echo -e "power on\nagent on\ndefault-agent\n" | /usr/bin/bluetoothctl >/dev/null 2>&1

# Try to connect several times
for attempt in $(seq 1 "$TRIES"); do
  log "Attempt $attempt/$TRIES: connecting to $MAC…"
  /usr/bin/bluetoothctl connect "$MAC" >/dev/null 2>&1

  # Check connection state
  if /usr/bin/bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
    log "Connected to $MAC."
    connected=1
    break
  fi

  sleep "$SLEEP_BETWEEN"
done

if [ "${connected:-0}" -ne 1 ]; then
  log "Failed to connect after $TRIES attempts."
  exit 1
fi

# Give PulseAudio time to register sink and set it default (best effort)
sleep 3
if command -v pactl >/dev/null 2>&1; then
  # Prefer A2DP if available (does nothing if not applicable)
  if pactl list cards short | grep -q "bluez_card"; then
    CARD=$(pactl list cards short | awk '/bluez_card/ {print $1; exit}')
    pactl set-card-profile "$CARD" a2dp-sink >/dev/null 2>&1 || true
  fi

  SINK=$(pactl list short sinks | awk '/bluez/ {print $1; exit}')
  if [ -n "$SINK" ]; then
    pactl set-default-sink "$SINK" || true
    log "Default sink set to $SINK."
  else
    log "No bluez sink found yet; audio may still route after a moment."
  fi
else
  log "pactl not found; skipping default sink selection."
fi

log "Done."
exit 0
