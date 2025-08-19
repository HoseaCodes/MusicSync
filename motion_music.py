#!/usr/bin/env python3
import os, time, random, threading, signal, sys
from gpiozero import MotionSensor
import pygame

# --- Config ---
GPIO_PIN = 4
MUSIC_DIR = os.path.expanduser("~/Music")
NO_MOTION_TIMEOUT = 30     # seconds of no motion before stopping
FADEOUT_MS = 1500

# --- State ---
stop_timer = None
playing = False
current_track = None
lock = threading.Lock()

def list_songs():
    exts = (".mp3", ".wav", ".ogg")
    try:
        return [os.path.join(MUSIC_DIR, f) for f in os.listdir(MUSIC_DIR) if f.lower().endswith(exts)]
    except FileNotFoundError:
        return []

def pick_track(tracks):
    return random.choice(tracks) if tracks else None

def start_play():
    global playing, current_track
    with lock:
        if playing:
            return
        tracks = list_songs()
        current_track = pick_track(tracks)
        if not current_track:
            print("[ERR] No audio files in", MUSIC_DIR)
            return
        print(f"[PLAY] {os.path.basename(current_track)}")
        pygame.mixer.music.load(current_track)
        pygame.mixer.music.play(-1)  # loop while present
        playing = True

def stop_play():
    global playing
    with lock:
        if not playing:
            return
        print("[STOP] Fade out")
        pygame.mixer.music.fadeout(FADEOUT_MS)
        pygame.mixer.music.stop()
        playing = False

def arm_stop_timer():
    global stop_timer
    # Cancel prior timer and start a fresh one
    if stop_timer and stop_timer.is_alive():
        stop_timer.cancel()
    stop_timer = threading.Timer(NO_MOTION_TIMEOUT, stop_play)
    stop_timer.daemon = True
    stop_timer.start()

def on_motion():
    # Motion resets the “no motion” timer and ensures music is playing
    start_play()
    arm_stop_timer()

def on_no_motion():
    # No motion event starts countdown to stop
    arm_stop_timer()

def main():
    # Audio init
    pygame.mixer.init()
    # PIR init; tweak sample_rate/queue_len if you get false triggers
    pir = MotionSensor(GPIO_PIN)
    pir.when_motion = on_motion
    pir.when_no_motion = on_no_motion

    print("[READY] Waiting for motion. Ctrl+C to exit.")
    # Sleep forever without a busy loop
    signal.signal(signal.SIGINT, lambda s, f: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))
    while True:
        time.sleep(3600)

if __name__ == "__main__":
    main()