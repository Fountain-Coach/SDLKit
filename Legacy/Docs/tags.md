# SDLKit Glossary & Tags

Use this appendix when a README, guide, or code comment references a tag-like identifier—environment variables, agent names, settings keys, or secrets. Each entry explains the intent in plain language so humans and automation can align on the same vocabulary.

## Agent & Tool Names

| Tag | Meaning |
| --- | --- |
| `GraphicsAgent` | Owns render backend implementations (Metal, Direct3D 12, Vulkan), resource lifetime, and frame orchestration. It turns shader artifacts into GPU pipelines and executes draw or compute work. |
| `ShaderAgent` | Builds single-source shaders into platform artifacts and exposes reflection metadata so other agents know attribute/binding layouts. |
| `SceneGraphAgent` | Traverses scene nodes, updates transforms, culls, and submits ordered draw calls to the graphics backend each frame. |
| `ComputeAgent` | Provides compute-only GPU workloads that share devices, resources, and synchronization with the graphics backend. |
| `SDLKitGUIAgent` | High-level Swift agent that exposes GUI/window controls to planners via a JSON contract. |
| `SDLKitJSONAgent` | Router used by HTTP/IPC front ends to invoke the GUI agent through JSON payloads. |
| `SDLKitSettings` | CLI tool that prints or mutates persisted configuration keys and suggests environment exports. |
| `SDLKitSecrets` | CLI tool for storing sensitive overrides (like light direction) in the encrypted keystore. |
| `SDLKitMigrate` | CLI helper that copies known `SDLKIT_*` environment variables into the settings store. |
| `SDLKitGolden` | CLI used to capture or compare golden image hashes during graphics regression checks. |

## Environment Variables

These variables shape runtime behavior. Unless noted, set values before launching Swift executables or running tests.

| Variable | Description |
| --- | --- |
| `SDLKIT_MAX_WINDOWS` | Soft limit on concurrently open GUI windows. Non-positive or invalid values fall back to the default of 8. |
| `SDLKIT_GUI_ENABLED` | Enables GUI execution paths in demos/tests when set to `1`; otherwise the GUI agent reports that SDL is unavailable. |
| `SDLKIT_RENDER_BACKEND` | Selects the graphics backend (`metal`, `d3d12`, or `vulkan`) used by demos and tests. |
| `SDLKIT_PRESENT_POLICY` | Chooses frame present behavior (`auto` or `explicit`) for the GUI agent. |
| `SDLKIT_DEMO_FORCE_2D` | Forces demos to run in 2D mode when set (skips the 3D scene graph walkthrough). |
| `SDLKIT_GOLDEN` | Turns on golden-image comparison runs during tests. |
| `SDLKIT_GOLDEN_WRITE` | When used with `SDLKIT_GOLDEN`, allows tests to record new golden hashes. |
| `SDLKIT_GOLDEN_REF` | Overrides the location of persisted golden-image baselines. |
| `SDLKIT_GOLDEN_AUTO_WRITE` | Enables automatic recording of missing golden hashes during migration from env vars to settings. |
| `SDLKIT_OPENAPI_PATH` | Points the JSON router to a custom OpenAPI contract file (YAML or JSON). |
| `SDLKIT_SERVER_HOST` / `SDLKIT_SERVER_PORT` | Override host and port binding for the JSON server example. |
| `SDLKIT_SHADER_ROOT` | Root directory override for shader artifacts that the shader library loads. |
| `SDLKIT_SHADER_DXC` | Absolute path override for the DirectX Shader Compiler used by the shader build toolchain. |
| `SDLKIT_SHADER_SPIRV_CROSS` | Override for the SPIRV-Cross executable used to produce Metal shaders. |
| `SDLKIT_SHADER_METAL` / `SDLKIT_SHADER_METALLIB` | Paths to Apple’s `metal` and `metallib` tools when the defaults are not on `PATH`. |
| `SDLKIT_VK_VALIDATION` | Enables Vulkan validation layers when truthy (`1`, `true`). |
| `SDLKIT_VK_VALIDATION_VERBOSE` | Turns on verbose Vulkan validation logging for troubleshooting. |
| `SDLKIT_DX12_DEBUG_LAYER` | Enables the Direct3D 12 debug layer through the migration utility. |
| `SDLKIT_SCENE_MATERIAL` | Preferred default material identifier for demos (e.g., `basic_lit`). |
| `SDLKIT_SCENE_BASE_COLOR` | Default scene base color expressed as comma-separated floats (`r,g,b,a`). |
| `SDLKIT_SCENE_LIGHT_DIR` | Default directional-light vector as comma-separated floats (`x,y,z`). |
| `SDLKIT_SECRET_PASSWORD` | Password used by the secrets CLI to encrypt or decrypt stored values (defaults to `change-me`). |
| `SDLKIT_USE_FILE_KEYSTORE` | Opts into storing secrets on disk instead of the system keychain. |
| `SDLKIT_NO_YAMS` | Skips adding the Yams YAML dependency during SwiftPM builds (`1` disables). |
| `SDLKIT_FORCE_HEADLESS` | Builds the package against stub SDL bindings for headless CI runs. |
| `SDLKIT_FORCE_SYSTEM_SDL` | Forces linking against a system-installed SDL instead of vendored builds. |
| `SDLKIT_LOG_LEVEL` | Overrides the logging level (`trace`, `debug`, `info`, etc.) for runtime diagnostics. |
| `SDLKIT_BACKEND` | Historical alias for render backend selection; prefer `SDLKIT_RENDER_BACKEND`. |
| `HEADLESS_CI` | Swift compiler define (set via `-DHEADLESS_CI`) that removes SDL linkage for CI builds. |

## Settings Keys

Persisted keys live in the `SettingsStore` and mirror many environment variables. They can be inspected or updated via `SDLKitSettings`.

| Key | Stored Value | Purpose |
| --- | --- | --- |
| `render.backend.override` | `String` (`metal`, `d3d12`, `vulkan`) | Preferred render backend when SDLKit chooses automatically. |
| `present.policy` | `String` (`auto`, `explicit`) | Default present policy applied by GUI flows. |
| `vk.validation` | `Bool` | Toggles Vulkan validation layers persistently. |
| `scene.default.material` | `String` | Default material name for demos and the scene graph. |
| `scene.default.baseColor` | `String` | Serialized RGBA floats used as the default base color. |
| `scene.default.lightDirection` | `String` | Serialized XYZ floats representing the default light direction. |
| `golden.last.key` | `String` | Records the last golden-image hash that was written for debugging. |
| `golden.auto.write` | `Bool` | When true, missing golden hashes are persisted without manual approval. |

## Secret Keys

Secrets stored via `SDLKitSecrets` complement environment and settings data.

| Key | Purpose |
| --- | --- |
| `light_dir` | Overrides the default scene light direction using encrypted storage instead of plaintext settings. |

---

**Need another tag explained?** File an issue or PR so the glossary keeps pace with new configuration options and agent terminology.
