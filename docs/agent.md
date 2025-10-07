SDLKit JSON Agent — Endpoints (Current)

Overview
- Lightweight JSON router for scripted control (tests, demos, remote driving).
- Works in GUI mode (with SDL3 installed). In headless builds (`HEADLESS_CI`), GUI/audio/MIDI endpoints return not_implemented.
- All calls are synchronous in-process Swift; you provide `Data` request and receive `Data` response.

Getting a Router
```swift
import SDLKit
let agent = SDLKitJSONAgent()
```

Window
- `/agent/gui/window/open` → `{ title, width, height }` → `{ window_id }`
- `/agent/gui/window/close` → `{ window_id }` → `{ ok }`
- `/agent/gui/window/show|hide|maximize|minimize|restore|center` → `{ window_id }` → `{ ok }`
- `/agent/gui/window/resize` → `{ window_id, width, height }` → `{ ok }`
- `/agent/gui/window/setTitle` → `{ window_id, title }` → `{ ok }`
- `/agent/gui/window/setPosition` → `{ window_id, x, y }` → `{ ok }`
- `/agent/gui/window/getInfo` → `{ window_id }` → `{ x, y, width, height, title }`
- `/agent/gui/window/setFullscreen` → `{ window_id, enabled }` → `{ ok }`
- `/agent/gui/window/setOpacity` → `{ window_id, opacity }` → `{ ok }`
- `/agent/gui/window/setAlwaysOnTop` → `{ window_id, enabled }` → `{ ok }`

Render and Drawing
- `/agent/gui/present` → `{ window_id }` → `{ ok }`
- `/agent/gui/clear` → `{ window_id, color }` → `{ ok }`
- `/agent/gui/drawRectangle` → `{ window_id, x, y, width, height, color }` → `{ ok }`
- `/agent/gui/drawLine` → `{ window_id, x1, y1, x2, y2, color }` → `{ ok }`
- `/agent/gui/drawCircleFilled` → `{ window_id, cx, cy, radius, color }` → `{ ok }`
- `/agent/gui/drawText` → `{ window_id, x, y, color, font_path, size, text }` → `{ ok }` (requires `sdl3_ttf`)
- `/agent/gui/texture/load` → `{ window_id, id, path }` → `{ ok }` (uses `sdl3_image` for non‑BMP)
- `/agent/gui/texture/draw` → `{ window_id, id, x, y, width?, height? }` → `{ ok }`
- `/agent/gui/texture/drawTiled` → `{ window_id, id, x, y, width, height, tile_w, tile_h }` → `{ ok }`
- `/agent/gui/texture/drawRotated` → `{ window_id, id, x, y, width?, height?, angle_degrees, center_x?, center_y? }` → `{ ok }`
- `/agent/gui/texture/free` → `{ window_id, id }` → `{ ok }`

Render State Queries
- `/agent/gui/render/getOutputSize` → `{ window_id }` → `{ width, height }`
- `/agent/gui/render/getScale` → `{ window_id }` → `{ sx, sy }`
- `/agent/gui/render/setScale` → `{ window_id, sx, sy }` → `{ ok }`
- `/agent/gui/render/getDrawColor` → `{ window_id }` → `{ color }`
- `/agent/gui/render/setDrawColor` → `{ window_id, color }` → `{ ok }`
- `/agent/gui/render/getViewport` → `{ window_id }` → `{ x, y, width, height }`
- `/agent/gui/render/setViewport` → `{ window_id, x, y, width, height }` → `{ ok }`
- `/agent/gui/render/getClipRect` → `{ window_id }` → `{ x, y, width, height }`
- `/agent/gui/render/setClipRect` → `{ window_id, x, y, width, height }` → `{ ok }`
- `/agent/gui/render/disableClipRect` → `{ window_id }` → `{ ok }`
- `/agent/gui/screenshot/capture` → `{ window_id, format: "raw|png" }` → raw/PNG payload

Input, Clipboard, Displays
- `/agent/gui/captureEvent` → `{ timeout_ms }` → `{ type, x?, y?, keycode?, button? }`
- `/agent/gui/clipboard/get` → `{}` → `{ text }`
- `/agent/gui/clipboard/set` → `{ text }` → `{ ok }`
- `/agent/gui/input/getKeyboardState` → `{}` → `{ modMask }`
- `/agent/gui/input/getMouseState` → `{}` → `{ x, y, buttons }`
- `/agent/gui/display/list` → `{}` → `{ displays: [index] }`
- `/agent/gui/display/getInfo` → `{ index }` → `{ name, x, y, width, height }`

Audio (preview)
- `/agent/audio/devices` → `{ kind: "playback|recording" }` → `{ devices: [{ id, kind, name, preferred, bufferFrames }] }`
- `/agent/audio/capture/open` → `{ sample_rate?, channels?, format? }` → `{ audio_id }`
- `/agent/audio/capture/read` → `{ audio_id, frames }` → `{ frames, pcm_base64 }` (f32 interleaved)
- `/agent/audio/playback/open` → `{ sample_rate?, channels?, format? }` → `{ playback_id }`
- `/agent/audio/playback/sine` → `{ playback_id, frequency, amplitude?, seconds }` → `{ ok }`
- `/agent/audio/playback/queue/open` → `{ playback_id, capacity_frames?, chunk_frames? }` → `{ queue_id }`
- `/agent/audio/playback/queue/enqueue` → `{ queue_id, pcm_base64 }` → `{ ok }`
- `/agent/audio/playback/play_wav` → `{ playback_id, path }` → `{ ok }`
- `/agent/audio/monitor/start|stop` → `{ audio_id, playback_id, chunk_frames? }` → `{ ok }`

A2M/Features (experimental; headless‑guarded)
- `/agent/audio/features/start` → `{ audio_id, gpu?: bool }` → `{ ok }`
- `/agent/audio/features/read_mel` → `{ audio_id, frames }` → `{ frames, mel_bands, mel_base64 }`
- `/agent/audio/a2m/test` → `{ mel_bands, frames, mel_base64 }` → `{ events }`
- `/agent/audio/a2m/start|read` → derive notes from feature frames (internal test stub)
- `/agent/audio/a2m/stream/start|poll|stop` → streaming note events (macOS, non‑headless)

MIDI (macOS, non‑headless)
- `/agent/midi/start|stop` → `{ midi1?: bool }` ↔ `{ ok }`
- `/agent/midi/destinations` → `{}` → `{ destinations: [String] }`
- `/agent/midi/select` → `{ index }` → `{ ok }`
- `/agent/midi/selectByName` → `{ name }` → `{ ok }`
- `/agent/midi/channel` → `{ channel }` → `{ ok }`

Health & Version
- `/health` → `{ ok }`
- `/version` → `{ version }`

Notes
- Colors: accept `#RRGGBB` or ARGB `UInt32` (0xAARRGGBB); draw APIs set ARGB (alpha in high byte).
- Formats: raw screenshots are ABGR8888; PNG requires `sdl3_image`.
- Headless: GUI/audio/MIDI endpoints return `not_implemented` with a descriptive message.

