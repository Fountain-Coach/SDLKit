# Installation Guide

SDLKit builds on the Fountain‑Coach SDL3 fork and discovers the library via `pkg-config`. This guide aggregates the steps for fetching the fork, pointing SwiftPM at custom prefixes, and verifying your environment before you begin development.

## Use the Fountain‑Coach SDL3 fork

SDLKit is designed to track the Fountain‑Coach fork of SDL3.

- Repository: <https://github.com/Fountain-Coach/SDL>
- Follow that repository's instructions to build or install SDL3 for your platform.
- SDLKit consumes the library through the `sdl3` `pkg-config` module and links `SDL3` automatically.

When installing to a nonstandard prefix, expose the locations so SwiftPM can forward include and library paths:

- `SDL3_INCLUDE_DIR` — SDL headers (for example `/opt/sdl/include`).
- `SDL3_LIB_DIR` — SDL libraries (for example `/opt/sdl/lib`).

These environment variables are read by `Package.swift` to emit the correct `-I`/`-L` flags.

## Platform-specific install instructions

### macOS

```bash
brew install sdl3
```

You can also build the Fountain‑Coach fork from source when you need its bleeding-edge features.

### Linux (Debian/Ubuntu)

```bash
sudo apt-get install -y libsdl3-dev
```

Alternatively, build and install the fork manually, then export `PKG_CONFIG_PATH` so `pkg-config` finds the resulting `.pc` file.

Install the Vulkan SDK packages so SwiftPM can link the `CVulkan` module:

```bash
sudo apt-get install -y libvulkan-dev vulkan-headers vulkan-validationlayers vulkan-tools
```

This brings in the loader, headers, and validation layers used by SDLKit’s Vulkan backend.

### Linux (Fedora/RHEL)

```bash
sudo dnf install -y vulkan-devel vulkan-headers vulkan-validation-layers vulkan-tools
```

### Linux (Arch/Manjaro)

```bash
sudo pacman -S --needed vulkan-headers vulkan-icd-loader vulkan-validation-layers vulkan-tools
```

After installation, confirm `pkg-config --exists vulkan` succeeds; SDLKit’s manifest now fails fast when these packages are missing.

### Windows

Install SDL3 via vcpkg:

```powershell
vcpkg install sdl3
```

Ensure the resulting headers and libraries are visible to your Swift toolchain. When running binaries, you may need to extend `PATH`/`LD_LIBRARY_PATH` (for example `setx PATH "C:\path\to\sdl3\bin;%PATH%"`) so the loader finds `SDL3.dll`/`libSDL3.so`.

### Dynamic library lookups

If you install the fork under a custom prefix, export:

```bash
export LD_LIBRARY_PATH=/path/to/prefix/lib:$LD_LIBRARY_PATH
```

on Linux or set the equivalent search path on Windows and macOS. This ensures the runtime loader discovers SDL3 when you launch samples or tests.

## Verify your installation

After installing SDL3, run the standard SwiftPM commands to confirm your environment is ready:

```bash
swift build
swift test
```

Headless CI builds continue to succeed even when SDL3 is absent, but installing the library locally lets you exercise the windowing and rendering paths.
