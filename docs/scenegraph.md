# Scene Graph & Demo Guide

SDLKit ships a 3D scene graph layered on top of the core SDL windowing and rendering primitives. The demo targets Metal, Direct3D 12, and Vulkan backends through the shared `RenderBackend` protocol. This guide covers how to launch the demo, override backends, and validate rendering output.

## Run the demo

```bash
swift run SDLKitDemo
```

The sample opens a window, selects the platform backend (Metal on macOS, D3D12 on Windows, Vulkan on Linux), uploads a static triangle, and drives a `beginFrame → draw → endFrame` loop. It exercises the new `RenderBackend` protocol and the scene graph traversal that submits meshes every frame.

## Choose a specific backend

You can override the default backend selection either through the persisted settings CLI or environment variables.

- Persisted: `swift run SDLKitSettings set --key render.backend.override --value metal`
- Environment variable: `SDLKIT_RENDER_BACKEND=metal|d3d12|vulkan swift run SDLKitDemo`

To force the legacy 2D smoke test instead of the 3D triangle, run:

```bash
SDLKIT_DEMO_FORCE_2D=1 swift run SDLKitDemo
```

## Golden image parity (Milestone M3)

Automated validation compares rendered output to reference hashes. Enable the tests with:

```bash
SDLKIT_GOLDEN=1 swift test
```

You can also manage references directly:

- Write a new reference: `swift run SDLKitGolden --backend metal --size 256x256 --material basic_lit --write`
- Verify against the reference: `swift run SDLKitGolden --backend metal --size 256x256 --material basic_lit`

## Scene graph defaults and settings

The scene graph respects configuration stored under `.fountain/sdlkit` via the `SDLKitSettings` CLI.

Examples:

- `swift run SDLKitSettings set --key scene.default.material --value basic_lit`
- `swift run SDLKitSettings set --key scene.default.baseColor --value "1.0,1.0,1.0,1.0"`
- `swift run SDLKitSettings set --key scene.default.lightDirection --value "0.3,-0.5,0.8"`

Use `swift run SDLKitMigrate` to port known `SDLKIT_*` environment variables into the settings store and print a JSON summary.

Secrets are managed via `SDLKitSecrets` (Keychain on macOS, Secret Service on Linux, file-based fallback elsewhere). For example:

```bash
swift run SDLKitSecrets set --key light_dir --value "0.3,-0.5,0.8"
```

The demo reads `light_dir` when present to configure the default scene light direction.
