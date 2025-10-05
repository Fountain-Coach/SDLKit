# SDLKit Audio Demo (GPU Features + A2M Stub)

This guide shows a minimal flow using the JSON agent to capture from the default microphone, enable GPU-based mel extraction, and stream stub MIDI-like events.

1) Open a window (needed for a RenderBackend on macOS/Metal):

POST /agent/gui/window/open
{ "title":"Audio GPU", "width": 640, "height": 480 }
→ { "window_id": 1 }

2) Open audio capture on default device:

POST /agent/audio/capture/open
{}
→ { "audio_id": 1 }

3) Start features on GPU, pointing to the window and backend:

POST /agent/audio/features/start
{ "audio_id":1, "frame_size":2048, "hop_size":512, "mel_bands":64, "use_gpu":true, "window_id":1, "backend":"metal" }
→ { "ok": true }

4) Start A2M stub (threshold/hysteresis are tunable):

POST /agent/audio/a2m/start
{ "audio_id":1, "mel_bands":64, "energy_threshold":0.01, "min_on_frames":2, "min_off_frames":2 }
→ { "ok": true }

5) Begin streaming A2M events:

POST /agent/audio/a2m/stream/start
{ "audio_id":1 }
→ { "ok": true }

6) Poll for events (long-poll supported via timeout_ms):

POST /agent/audio/a2m/stream/poll
{ "audio_id":1, "since":0, "max_events":128, "timeout_ms":200 }
→ { "events": [ { "kind":"note_on", "note":48, "velocity":65, "frameIndex":1024, "timestamp_ms": 12 }, ... ], "next": 37 }

Call again with since=37 to continue receiving new events.

7) Optional: Monitor mic → playback (echo) with resample if needed:

POST /agent/audio/playback/open
{ "sample_rate":48000, "channels":2, "format":"f32" }
→ { "audio_id": 2 }

POST /agent/audio/monitor/start
{ "capture_id":1, "playback_id":2, "chunk_frames":1024 }
→ { "ok": true }

To stop the stream or monitor:

POST /agent/audio/a2m/stream/stop
{ "audio_id":1 }

POST /agent/audio/monitor/stop
{ "capture_id":1 }

Notes
- Headless CI does not perform audio I/O; endpoints are available but will error with sdlUnavailable.
- GPU features path requires a window-bound RenderBackend. Metal is the default backend on macOS; Vulkan on Linux.
- The A2M stub is not a real model; it’s a placeholder for integration.
