# AudioAgent — SDL3 Audio Capture/Playback and Real‑Time Pipelines (Preview)

This document tracks the audio scope for SDLKit: SDL3 stream‑based capture and playback APIs, a lock‑free ring buffer, and the real‑time processing pipeline used by A2M (Audio→MIDI) and other features.

## Goals
- Uniform, low‑latency audio capture and playback via SDL3 `SDL_AudioStream`.
- Safe, headless‑friendly APIs (compile in, throw on use under HEADLESS_CI).
- Building block for real‑time pipelines (framing, features, inference).

## Current Status
- C shim exposes minimal audio wrappers:
  - `SDLKit_OpenDefaultAudioRecordingStream`, `SDLKit_OpenDefaultAudioPlaybackStream`
  - `SDLKit_GetAudioStream{Available,Data}`, `SDLKit_PutAudioStreamData`, `SDLKit_DestroyAudioStream`
  - Format helpers: `SDLKit_AudioFormat_F32`, `SDLKit_AudioFormat_S16`
- Swift API (preview):
  - `SDLAudioCapture` — pull interleaved `.f32` frames from default or selected recording device
  - `SDLAudioPlayback` — queue PCM samples; `playSine()` helper
  - `SDLAudioDeviceList` — enumerate playback/recording devices with preferred formats
  - `SDLAudioResampler` — convert/sample-rate via SDL_CreateAudioStream
  - `SDLAudioChunkedCapturePump` — background pump into a ring buffer
- JSON endpoints: list devices, open capture, read chunks; open playback, queue sine
- Tests: headless‑safe constructor + ring buffer unit tests.

## Milestones & Acceptance

M0 — Shim + Swift wrappers (this change)
- Acceptance: HEADLESS_CI builds; shims compile; API throws gracefully without SDL.

M1 — Device enumeration and selection (done)
- Add device listing (playback/recording), names, and preferred specs.
- Acceptance: list non‑zero devices on dev machines; default open succeeds or produces readable error.

M2 — Ring buffer + chunked capture (done)
- Lock‑free SPSC ring buffer between SDL audio thread and processing thread.
- `readFrames(count:)` guarantees exact hops; back‑pressure policy documented.
- Acceptance: synthetic capture harness verifies chunking and no drops under load.

M3 — Playback helpers (done)
- Convenience sine/beep generator; utility resampler via SDL streams.
- Acceptance: audible playback on dev machines; queue depth remains bounded.

M4 — A2M pipeline glue (CPU path)
- Framing + STFT + mel + onset on CPU.
- Acceptance: end‑to‑end pipeline emits stable note events from a known input file.

M5 — GPU uplift (optional)
- Compute shaders for batched STFT/mel (via existing RenderBackend compute).
- Acceptance: latency improvement vs CPU on Metal/Vulkan; parity tests.

M6 — JSON Agent endpoints
- Minimal control surface to open/close devices, query frames available, and pull chunks.
- Acceptance: smoke tests with agent runner; headless skip logic documented.

## Risks & Mitigations
- Device/driver variance → default device macros + spec negotiation; detailed errors.
- Latency tuning → ring buffer metrics, adjustable frame/hop presets.
- Cross‑platform differences → rely on SDL3 stream API uniformly; minimize OS‑specific paths.

## Usage (preview)

```swift
import SDLKit

let capture = try SDLAudioCapture(spec: .init(sampleRate: 48000, channels: 2, format: .f32))
var interleaved = Array(repeating: Float(0), count: 48000) // 0.5s stereo buffer
let frames = try capture.readFrames(into: &interleaved)
print("read frames=\(frames)")

let playback = try SDLAudioPlayback(spec: .init(sampleRate: 48000, channels: 2, format: .f32))
try playback.queue(samples: interleaved)
```

Note: In headless/CI builds, these constructors throw `sdlUnavailable`.
