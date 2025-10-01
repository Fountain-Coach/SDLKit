#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
from pathlib import Path

MODULES = [
    {
        "name": "unlit_triangle",
        "source": Path("Shaders/graphics/unlit_triangle.hlsl"),
        "vertex_entry": "unlit_triangle_vs",
        "fragment_entry": "unlit_triangle_ps",
    },
    {
        "name": "basic_lit",
        "source": Path("Shaders/graphics/basic_lit.hlsl"),
        "vertex_entry": "basic_lit_vs",
        "fragment_entry": "basic_lit_ps",
    }
]


def resolve_tool(env_key: str, executable: str, package_root: Path) -> str | None:
    if env_key and env_key in os.environ and os.environ[env_key]:
        return os.environ[env_key]

    tool = shutil.which(executable)
    if tool:
        return tool

    local = package_root / "External" / "Toolchains" / "bin" / executable
    if local.exists():
        return str(local)

    return None


def run_process(executable: Path, *arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(executable), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def ensure_directory(path: Path) -> bool:
    try:
        path.mkdir(parents=True, exist_ok=True)
        return True
    except OSError as error:
        sys.stderr.write(f"ShaderBuildPlugin: failed to create directory {path}: {error}\n")
        return False


def main() -> int:
    if len(sys.argv) < 3:
        sys.stderr.write("Usage: build-shaders.py <package-root> <output-dir>\n")
        return 1

    package_root = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])

    messages: list[str] = []

    if not ensure_directory(output_dir):
        messages.append(f"Unable to create shader output directory: {output_dir}")
        return 0

    generated_root = package_root / "Sources" / "SDLKit" / "Generated"
    if not generated_root.exists():
        messages.append(f"Generated directory missing at {generated_root}; skipping shader build")
        write_summary(messages, output_dir)
        return 0

    dxc = resolve_tool("SDLKIT_SHADER_DXC", "dxc", package_root)
    if not dxc:
        messages.append("dxc not found on PATH; skipping shader compilation")
        write_summary(messages, output_dir)
        return 0

    spirv_cross = resolve_tool("SDLKIT_SHADER_SPIRV_CROSS", "spirv-cross", package_root)
    metal = resolve_tool("SDLKIT_SHADER_METAL", "metal", package_root)
    metallib = resolve_tool("SDLKIT_SHADER_METALLIB", "metallib", package_root)

    for module in MODULES:
        source_path = package_root / module["source"]
        if not source_path.exists():
            messages.append(f"Source shader {source_path} missing; skipping")
            continue

        dxil_root = generated_root / "dxil"
        spirv_root = generated_root / "spirv"
        metal_root = generated_root / "metal"

        vertex_dxil = dxil_root / f"{module['name']}_vs.dxil"
        fragment_dxil = dxil_root / f"{module['name']}_ps.dxil"
        vertex_spv = spirv_root / f"{module['name']}.vert.spv"
        fragment_spv = spirv_root / f"{module['name']}.frag.spv"
        vertex_msl = output_dir / f"{module['name']}.vert.msl"
        fragment_msl = output_dir / f"{module['name']}.frag.msl"
        combined_msl = output_dir / f"{module['name']}.combined.msl"
        air_file = output_dir / f"{module['name']}.air"
        metallib_file = metal_root / f"{module['name']}.metallib"
        metal_source = package_root / "Shaders" / "graphics" / f"{module['name']}.metal"

        vertex_result = run_process(
            Path(dxc),
            "-T",
            "vs_6_7",
            "-E",
            module["vertex_entry"],
            "-Fo",
            str(vertex_dxil),
            str(source_path),
        )
        if vertex_result.returncode != 0:
            messages.append(f"dxc vertex compilation failed for {module['name']}\n{vertex_result.stderr}")
            continue

        fragment_result = run_process(
            Path(dxc),
            "-T",
            "ps_6_7",
            "-E",
            module["fragment_entry"],
            "-Fo",
            str(fragment_dxil),
            str(source_path),
        )
        if fragment_result.returncode != 0:
            messages.append(f"dxc fragment compilation failed for {module['name']}\n{fragment_result.stderr}")
            continue

        spirv_vertex = run_process(
            Path(dxc),
            "-spirv",
            "-fvk-use-dx-layout",
            "-fspv-target-env=vulkan1.2",
            "-T",
            "vs_6_7",
            "-E",
            module["vertex_entry"],
            "-Fo",
            str(vertex_spv),
            str(source_path),
        )
        if spirv_vertex.returncode != 0:
            messages.append(f"dxc SPIR-V vertex compilation failed for {module['name']}\n{spirv_vertex.stderr}")

        spirv_fragment = run_process(
            Path(dxc),
            "-spirv",
            "-fvk-use-dx-layout",
            "-fspv-target-env=vulkan1.2",
            "-T",
            "ps_6_7",
            "-E",
            module["fragment_entry"],
            "-Fo",
            str(fragment_spv),
            str(source_path),
        )
        if spirv_fragment.returncode != 0:
            messages.append(f"dxc SPIR-V fragment compilation failed for {module['name']}\n{spirv_fragment.stderr}")

        # Prefer native .metal sources if available
        if metal and metallib and metal_source.exists():
            metal_result = run_process(Path(metal), str(metal_source), "-o", str(air_file))
            if metal_result.returncode != 0:
                messages.append(f"metal compilation failed for {module['name']}\n{metal_result.stderr}")
            elif air_file.exists():
                metallib_result = run_process(Path(metallib), str(air_file), "-o", str(metallib_file))
                if metallib_result.returncode != 0:
                    messages.append(f"metallib linkage failed for {module['name']}\n{metallib_result.stderr}")
        elif spirv_cross and Path(vertex_spv).exists() and Path(fragment_spv).exists():
            vert_cross = run_process(
                Path(spirv_cross),
                str(vertex_spv),
                "--msl",
                "--entry",
                module["vertex_entry"],
                "--output",
                str(vertex_msl),
            )
            if vert_cross.returncode != 0:
                messages.append(f"SPIRV-Cross vertex conversion failed for {module['name']}\n{vert_cross.stderr}")

            frag_cross = run_process(
                Path(spirv_cross),
                str(fragment_spv),
                "--msl",
                "--entry",
                module["fragment_entry"],
                "--output",
                str(fragment_msl),
            )
            if frag_cross.returncode != 0:
                messages.append(f"SPIRV-Cross fragment conversion failed for {module['name']}\n{frag_cross.stderr}")

            if vertex_msl.exists():
                try:
                    combined_source = vertex_msl.read_text()
                    if fragment_msl.exists():
                        fragment_lines = fragment_msl.read_text().splitlines()
                        filtered = [
                            line
                            for line in fragment_lines
                            if not line.strip().startswith("#include")
                            and not line.strip().startswith("using namespace")
                        ]
                        combined_source += "\n" + "\n".join(filtered)
                    combined_msl.write_text(combined_source)
                except OSError as error:
                    messages.append(f"Failed to merge MSL sources for {module['name']}: {error}")

                if metal and metallib:
                    metal_result = run_process(Path(metal), str(combined_msl), "-o", str(air_file))
                    if metal_result.returncode != 0:
                        messages.append(f"metal compilation failed for {module['name']}\n{metal_result.stderr}")
                    elif air_file.exists():
                        metallib_result = run_process(Path(metallib), str(air_file), "-o", str(metallib_file))
                        if metallib_result.returncode != 0:
                            messages.append(f"metallib linkage failed for {module['name']}\n{metallib_result.stderr}")
                else:
                    messages.append(f"Apple Metal tools not available; skipping metallib for {module['name']}")
        else:
            messages.append(f"SPIRV-Cross not available; skipping Metal artifacts for {module['name']}")

    if not messages:
        messages.append("Shader compilation completed")
    write_summary(messages, output_dir)
    return 0


def write_summary(messages: list[str], output_dir: Path) -> None:
    summary = output_dir / "shader-build.log"
    try:
        summary.write_text("\n".join(messages))
    except OSError as error:
        sys.stderr.write(f"ShaderBuildPlugin: failed to write summary: {error}\n")


if __name__ == "__main__":
    sys.exit(main())
