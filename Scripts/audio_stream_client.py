#!/usr/bin/env python3
"""
Long-poll client for SDLKit audio A2M streaming endpoints.

Assumes an HTTP server exposing SDLKitJSONAgent at http://localhost:8080.

Flow:
 - Open a window (for GPU backend where applicable)
 - Open audio capture
 - Start features (GPU preferred)
 - Start A2M stub
 - Optionally start MIDI out
 - Start stream and poll for events

Usage:
  python3 Scripts/audio_stream_client.py --gpu --midi --seconds 10
"""
import argparse
import time
import requests

BASE = "http://localhost:8080"

def post(path: str, payload: dict) -> dict:
    r = requests.post(BASE + path, json=payload, timeout=10)
    r.raise_for_status()
    try:
        return r.json()
    except Exception:
        return {}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gpu', action='store_true', help='Use GPU features when available')
    ap.add_argument('--midi', action='store_true', help='Mirror events to MIDI (macOS)')
    ap.add_argument('--seconds', type=int, default=10, help='Duration to poll for events')
    args = ap.parse_args()

    # 1) Open a window
    win = post('/agent/gui/window/open', { 'title':'Audio GPU', 'width':640, 'height':360 })
    window_id = win.get('window_id', 1)

    # 2) Open capture
    cap = post('/agent/audio/capture/open', {})
    audio_id = cap.get('audio_id', 1)

    # 3) Start features
    features = post('/agent/audio/features/start', {
        'audio_id': audio_id,
        'frame_size': 2048,
        'hop_size': 512,
        'mel_bands': 64,
        'use_gpu': bool(args.gpu),
        'window_id': window_id,
        'backend': 'metal'
    })
    assert features.get('ok', False), f"features/start failed: {features}"

    # 4) Start A2M
    a2m = post('/agent/audio/a2m/start', {
        'audio_id': audio_id,
        'mel_bands': 64,
        'energy_threshold': 0.01,
        'min_on_frames': 2,
        'min_off_frames': 2
    })
    assert a2m.get('ok', False), f"a2m/start failed: {a2m}"

    # 5) MIDI (optional)
    if args.midi:
        post('/agent/midi/start', { 'midi1': True })

    # 6) Start stream
    stream = post('/agent/audio/a2m/stream/start', {
        'audio_id': audio_id,
        'midi': bool(args.midi)
    })
    assert stream.get('ok', False), f"stream/start failed: {stream}"

    # 7) Poll
    cursor = 0
    end = time.time() + args.seconds
    print('Polling events... (Ctrl+C to stop)')
    while time.time() < end:
        res = post('/agent/audio/a2m/stream/poll', {
            'audio_id': audio_id,
            'since': cursor,
            'max_events': 128,
            'timeout_ms': 200
        })
        evts = res.get('events', [])
        cursor = res.get('next', cursor)
        for e in evts:
            print(f"{e['timestamp_ms']:>6}ms  {e['kind']:<8}  note={e['note']:<3} vel={e['velocity']:<3}")

    # Stop stream and MIDI
    post('/agent/audio/a2m/stream/stop', { 'audio_id': audio_id })
    if args.midi:
        post('/agent/midi/stop', {})

if __name__ == '__main__':
    main()

