AGENT.md — SDLKit Contributor Guide

Purpose
- Keep SDLKit’s Swift API stable while the underlying SDL3 evolves.
- Provide clear rules for shims, pointer types, actor isolation, CI, and optional dependencies.
- Align with LayoutKit/ScoreKit/Teatro so higher layers can rely on consistent behavior.

Core Principles
- Stable C boundary: all SDL handles are `void*` in the shim; Swift uses `UnsafeMutableRawPointer?`.
- Zero global state leaks: `SDLCore` is `@MainActor`; init/shutdown is explicit and idempotent.
- Optional dependencies degrade gracefully (no fatalError in library code).
- Determinism: when we add snapshots (PNG/SVG), they must be reproducible in CI.

Shim Policy (CSDL3)
- All wrapper signatures take/return `void*` for window/renderer/texture/surface/audio stream.
- Cast at the C boundary; never expose SDL_* types to Swift.
- Keep a matching headless stub (`CSDL3Stub/shim_stub.c`) with identical prototypes.
- Place fragile helpers in `CSDL3Compat` (e.g., SDL property lookups, text helpers) to avoid inline importer quirks.

Swift Concurrency
- `SDLCore` is `@MainActor` (initialization, shutdown, error string access).
- Background threads (audio capture/playback/queues) snapshot the channels/spec at init; any interaction that must touch main actor uses `Task { @MainActor in … }`.
- No `fatalError` paths; return typed errors with actionable messages.

Optional Features
- `sdl3_ttf`: gated via `SDLKit_TTF_Available()` and target `SDLKitTTF`.
- `sdl3_image`: checked per-callsite; BMP falls back to core SDL when image is unavailable.
- Headless builds: define `HEADLESS_CI` when `sdl3` is missing or `SDLKIT_FORCE_HEADLESS=1`.

CI & Support Matrix
- GitHub Actions: macOS headless (blocking), Linux headless (blocking), macOS SDL3 (blocking via Homebrew: `sdl3`, `sdl3_image`, `sdl3_ttf`).
- Linux GUI legs are currently validated via headless build + Vulkan headers; enable full GUI once SDL3 packages are consistent across runners.
- Windows leg is on hold until a Swift 6+ toolchain is available on hosted runners.

Working With LayoutKit
- SDLKit acts as a runtime Canvas and windowing/input/audio host.
- LayoutKit generates vector `Scene`s; SDLKit will host a Canvas painter that maps `Scene` to 2D primitives, glyphs, and images.
- Keep Canvas APIs crisp and platform-agnostic; avoid leaking SDL or OS-specific types to LayoutKit.

Commits & Reviews
- Semantic commits: `feat:`, `fix:`, `perf:`, `refactor:`, `docs:`, `test:`, `ci:`.
- Keep changes surgical; update this file when altering contributor conventions.
- If a commit touches shims, make sure headless stub and CI both compile.

Release Hygiene
- Don’t bump version numbers until all CI legs are green for at least two consecutive runs.
- Document behavioral changes in the README under “What’s New”.

Backlog (Short Horizon)
- Add a minimal 2D Canvas and wire it to LayoutKit sample.
- Integrate HarfBuzz/FreeType for shaping and crisp glyphs (platform gating).
- Add PNG/SVG snapshot tests for small viewports.

