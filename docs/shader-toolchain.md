# Shader Toolchain Guide

SDLKit ships committed shader binaries, but the repository also contains the end-to-end toolchain so contributors can rebuild artifacts or author new shaders. This guide collects the workflow, required tooling, and verification steps that previously lived in the README.

## 1. Install external tools

SDLKit uses a single-source HLSL flow that targets multiple graphics APIs. Install the following utilities and expose them via your `PATH` or the documented environment variables.

- **DXC** — required to compile HLSL to DXIL and SPIR-V. Configure `SDLKIT_SHADER_DXC` or ensure `dxc` is discoverable.
- **SPIRV-Cross** *(optional)* — converts SPIR-V to MSL when native `.metal` sources are unavailable. Configure `SDLKIT_SHADER_SPIRV_CROSS`.
- **Apple `metal` / `metallib`** *(optional, macOS)* — builds `.metallib` outputs directly. Override discovery with `SDLKIT_SHADER_METAL` and `SDLKIT_SHADER_METALLIB`.
- **Python 3** — runs the helper script invoked by the SwiftPM plugin.

You can also place tool binaries under `External/Toolchains/bin` to avoid editing your global `PATH`.

## 2. Provide per-project overrides

The shader build plugin reads optional `.fountain/sdlkit/shader-tools.env` files to inject environment overrides when it runs. This lets teams codify tool paths or compiler flags per repository without touching user shells.

## 3. Invoke the build

Building `SDLKit` automatically triggers the `ShaderBuildPlugin`, which calls:

```
Scripts/ShaderBuild/build-shaders.py <package-root> <workdir>
```

before compilation. You can also trigger the script manually:

```bash
python3 Scripts/ShaderBuild/build-shaders.py "$(pwd)" .build/shader-cache
```

The script emits DXIL, SPIR-V, and Metallib artifacts, writes optional intermediate `.msl/.air` files, and records a `shader-build.log` summary inside the working directory.

## 4. Artifact layout

The plugin copies final binaries into `Sources/SDLKit/Generated/{dxil,spirv,metal}`. `ShaderLibrary` loads these artifacts at runtime and exposes both graphics and compute shaders so render and compute paths share metadata.

## 5. Verification

Run the focused shader tests to ensure the manifest matches the committed binaries:

```bash
swift test --filter ShaderArtifactsTests
```

The tests confirm the expected files exist and align with the manifest checked into source control.
