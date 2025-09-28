# SDLKit — Swift SDL3 Wrapper (Pre‑Alpha)

SDLKit is a Swift Package that wraps SDL3 and exposes a Swift‑friendly API and a small, bounded GUI Agent for the FountainAI ecosystem.

- Purpose: decouple SDL3 interop from higher‑level modules, enable reuse across projects, and provide a safe tool surface for AI planners.
- SDL upstream: this project targets the Fountain‑Coach SDL fork: https://github.com/Fountain-Coach/SDL

## Status

- Pre‑alpha skeleton. Compiles as a SwiftPM package, but no SDL calls are wired yet.
- Public API and agent contract are drafted; most methods throw `notImplemented` until wired.
- See `AGENTS.md:1` for the official agent contract and repo guidelines.

## Project Structure

- `Package.swift:1` — SwiftPM definition with system library `CSDL3` and library target `SDLKit`.
- `Sources/CSDL3/module.modulemap:1`, `Sources/CSDL3/shim.h:1` — system bindings for SDL3 headers and link flags.
- `Sources/SDLKit/SDLKit.swift:1` — config and global feature flags.
- `Sources/SDLKit/Support/Errors.swift:1` — canonical error types for tools.
- `Sources/SDLKit/Core/SDLWindow.swift:1`, `Sources/SDLKit/Core/SDLRenderer.swift:1` — placeholders for wrappers.
- `Sources/SDLKit/Agent/SDLKitGUIAgent.swift:1` — agent with stubbed tool methods.
- `Tests/SDLKitTests/SDLKitTests.swift:1` — minimal XCTest.

## Using Our SDL Fork

This package is designed to work with the Fountain‑Coach SDL3 fork:

- Repo: https://github.com/Fountain-Coach/SDL
- Follow that repo’s instructions to build/install SDL3 for your platform.
- SDLKit discovers SDL3 via `pkg-config` name `sdl3` and links `SDL3`.
- If you install the fork to a nonstandard prefix, set:
  - `SDL3_INCLUDE_DIR` to the SDL include directory (e.g., `/opt/sdl/include`)
  - `SDL3_LIB_DIR` to the SDL lib directory (e.g., `/opt/sdl/lib`)
  These are picked up by `Package.swift` to pass `-I`/`-L` to the build.

## Install SDL3

- macOS: `brew install sdl3` (or build/install the Fountain‑Coach fork if preferred).
- Linux (Debian/Ubuntu): `sudo apt-get install -y libsdl3-dev` (or build from the fork).
- Windows: install via vcpkg (`vcpkg install sdl3`) and ensure headers/libs are discoverable.
  - If using a custom prefix, export `LD_LIBRARY_PATH=/path/to/prefix/lib:$LD_LIBRARY_PATH` when running binaries so the dynamic linker can find `libSDL3.so`.

## Build & Test

- Requires Swift 6.1+
- Build: `swift build`
- Test: `swift test`

CI builds the SDL fork with minimal features and console mode (no window backends) in a local prefix and runs `swift build`/`swift test` on Linux using the official Swift 6.1 Docker image (see `.github/workflows/ci.yml:1`). Runtime linking note: the workflow adds `LD_LIBRARY_PATH` to include the local SDL install for test execution.

macOS CI: not enabled by default. If you need macOS validation, set up a self‑hosted macOS runner and add a job targeting `runs-on: [self-hosted, macOS]`.

## Quick Start (pre‑alpha)

```swift
import SDLKit

let agent = SDLKitGUIAgent()
let windowId = try agent.openWindow(title: "SDLKit", width: 800, height: 600)
// drawText/drawRectangle/present currently throw notImplemented until wired
agent.closeWindow(windowId: windowId)
```

## Agent Contract

See `AGENTS.md:1` for the `sdlkit.gui.v1` tool definitions, error codes, event schema, threading policy, present policy, configuration keys, and contributor workflow.

## Roadmap

- Wire actual SDL window/renderer in `Core` wrappers.
- Implement agent tools (open/close/present/draw primitives/text).
- Add optional SDL_ttf text rendering and color parsing.
- Headless/CI execution paths and cross‑platform tests.
- OpenAPI/tool wiring samples and end‑to‑end examples.

## Contributing

- Start with `AGENTS.md:1` for repo conventions and the agent schema.
- Keep changes focused; update docs when adding/changing public API.
- Platform notes and SDL build guidance live in the SDL fork and will be referenced here as wiring progresses.
