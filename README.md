SDLKit — Swift SDL3 Runtime (Windowing, 2D, Audio)

Overview
- Swift-first wrapper over SDL3 for windowing, input, immediate 2D drawing, image/font helpers, and audio.
- Works in two modes: GUI (with system SDL3) and headless (no SDL3 required) for CI and servers.
- Provides a small JSON agent for scripted control and tests; integrates with LayoutKit as a Canvas backend.
- Clean, resilient C shim uses void* for SDL handles; Swift sees `UnsafeMutableRawPointer` and stays stable across SDL3 changes.

OpenAPI (Source of Truth)
- Spec: `Sources/SDLKitAPI/openapi.yaml` (OpenAPI 3.1)
- Generator: Apple’s Swift OpenAPI Generator (types + client + server)
- Dedicated workflow: `SDLKit/.github/workflows/openapi.yml` (non‑blocking)
- Human docs: `docs/agent.md` (mirrors the spec)
- Optional server: `SDLKitNIO` routes HTTP path → `SDLKitJSONAgent` (manual transport). A generated‑server adapter can be added to conform to the spec’s server interfaces and delegate to the router.

What’s In, Right Now
- Windowing: open/close, show/hide, resize, title, position; fetch native handles (CAMetalLayer, HWND, Vulkan surface).
- 2D Drawing: a thin wrapper over `SDL_Renderer` for clear, lines, filled rects, textures, screenshots (ABGR8888, PNG).
- Images/Fonts: optional `sdl3_image` for PNG/JPEG and `sdl3_ttf` for text; graceful no-op when not present.
- Audio: capture, playback, resampling (SDL3 audio stream APIs); simple device enumeration and formats.
- Headless: compiles with a stub C impl; GUI paths return `not_implemented` but code can build and test logic.
- CI: macOS headless + Linux headless are blocking; macOS SDL3 (Homebrew) is blocking and compiles full GUI/audio.

How It Relates
- LayoutKit: SDLKit is the primary “Canvas runtime” for interactive previews and screenshots. LayoutKit generates a `Scene` (vector list); SDLKit paints it on-screen or to PNG.
- ScoreKit/Teatro: Higher-level tools (Teatro) can embed `SDLKitJSONAgent` to drive UI from intents; ScoreKit uses SDLKit for interactive coaching visuals.

Getting Started
- macOS GUI
  - Install: `brew install sdl3 sdl3_image sdl3_ttf`
  - Build: `cd SDLKit && swift build`
  - Run demo: `swift run SDLKitDemo` (basic window + drawing; text path requires sdl3_ttf)
- Linux headless (CI identical)
  - Install: `apt-get update && apt-get install -y libvulkan-dev`
  - Build: `SDLKIT_FORCE_HEADLESS=1 swift build` (no SDL3 needed)
- Package usage
  - Add to Package.swift: `.package(path: "path/to/SDLKit")`
  - Target deps: `.product(name: "SDLKit", package: "SDLKit")`
  - OpenAPI types/client (optional): `.target(name: "SDLKitAPI")` and depend on it
  - NIO server (optional): `swift run SDLKitNIO` (accepts JSON body per spec)

Key Targets
- `CSDL3`: system module for SDL3 (pkg-config `sdl3`), or `CSDL3Stub` when not found.
- `CSDL3IMAGE`/`CSDL3TTF`: system modules (or stubs) for image/ttf helpers.
- `CSDL3Compat`: tiny C helpers (Win32 HWND property, TTF UTF8) to avoid fragile inline imports.
- `SDLKit`: the Swift API (window, renderer, audio, JSON agent).
- `SDLKitTTF`: optional text helpers layered on SDLKit.
- Demos/Tools: `SDLKitDemo`, `SDLKitGolden`, `SDLKitSettings`, `SDLKitMigrate`.
- OpenAPI: `SDLKitAPI` (spec-driven generated types/client/server stubs), `SDLKitNIO` (manual HTTP server)

Build Flags & Env
- `HEADLESS_CI`: defined when `sdl3` is unavailable → stubs compiled; GUI/audio features become no-ops.
- `SDLKIT_FORCE_HEADLESS=1`: force headless even if SDL3 is available (useful in CI).
- `SDL3_INCLUDE_DIR`/`SDL3_LIB_DIR`: override discovery if pkg-config isn’t available.
- `SDLKIT_GUI_ENABLED` (default true): turn GUI targets on/off (demo/ttf/image helpers).

Design Choices
- Opaque handles: C shim takes/returns `void*`; all casts happen in C; Swift only handles raw pointers (fewer importer surprises).
- Actor isolation: `SDLCore` is `@MainActor`; audio threads snapshot cross-actor state at init and dispatch back to main when needed.
- Graceful optional deps: `sdl3_ttf`/`sdl3_image` codepaths check availability and fallback.

CI & Quality Gates
- GitHub Actions: headless macOS/Linux (blocking) and macOS SDL3 (blocking).
- Headless jobs validate build/test without SDL; macOS job compiles and runs the non-headless suite.
- Separate OpenAPI job generates/compiles spec outputs and stays non‑blocking.

Roadmap (Near-Term)
- 2D vector “Canvas” API for LayoutKit with batching and path/glyph support (CoreGraphics on macOS; SDL primitives elsewhere).
- Text shaping (HarfBuzz + FreeType where available) with `sdl3_ttf` fallback; crisp font rendering on all OSes.
- Windows leg: enable when Swift 6+ is available on GitHub-hosted Windows runners.
- Extended JSON agent surface for remote preview/testing (beyond simple GUI ops).

Repository Layout
- `Sources/SDLKit/Core` — window, renderer, audio, JSON agent.
- `Sources/CSDL3*` — C shims and stubs.
- `Legacy/` — archived planning docs, early agent write-ups, and unmaintained OpenAPI files.
- `Tests/` — smoke tests + golden references where applicable.

License
- Copyright (c) Fountain‑Coach.
