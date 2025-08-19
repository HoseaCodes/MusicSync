import os, time, random, sys
from gpiozero import MotionSensor

# --- Config ---
GPIO_PIN = 4
MUSIC_DIR = os.path.expanduser("~/Music")
NO_MOTION_TIMEOUT = 30  # seconds
FADEOUT_MS = 1500       # smooth stop

# --- Setup PIR ---
pir = MotionSensor(GPIO_PIN)

# --- Use pygame only after Bluetooth sink is likely ready ---
import pygame
pygame.mixer.init()

def list_songs():
    exts = (".mp3", ".wav", ".ogg")
    return [
        os.path.join(MUSIC_DIR, f)
        for f in os.listdir(MUSIC_DIR)
        if f.lower().endswith(exts)
    ]

def play_random(loop=True):
    tracks = list_songs()
    if not tracks:
        print("No tracks in", MUSIC_DIR)
        return False
    track = random.choice(tracks)
    print(f"[PLAY] {os.path.basename(track)}")
    pygame.mixer.music.load(track)
    # For looped ambient behavior while present
    pygame.mixer.music.play(-1 if loop else 0)
    return True

def is_playing():
    return pygame.mixer.music.get_busy()

def stop_smooth():
    try:
        pygame.mixer.music.fadeout(FADEOUT_MS)
    except Exception:
        pygame.mixer.music.stop()

print("Presence music system ready.")
last_motion = 0

# Small warmup so PulseAudio/BT can settle after boot
time.sleep(3)

while True:
    if pir.motion_detected:
        last_motion = time.time()
        if not is_playing():
            ok = play_random(loop=True)
            if not ok:
                time.sleep(5)
                continue
    else:
        if is_playing() and (time.time() - last_motion) > NO_MOTION_TIMEOUT:
            print("[STOP] No motion for", NO_MOTION_TIMEOUT, "seconds.")
            stop_smooth()
    time.sleep(0.5)