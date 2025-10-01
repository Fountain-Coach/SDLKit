#!/usr/bin/env python3
import sys
from pathlib import Path

def main(argv: list[str]) -> int:
    if "-o" not in argv:
        sys.stderr.write("fake_metal: missing -o argument\n")
        return 1
    out_index = argv.index("-o")
    try:
        output = Path(argv[out_index + 1])
    except IndexError:
        sys.stderr.write("fake_metal: missing output path\n")
        return 1
    if out_index <= 0:
        sys.stderr.write("fake_metal: missing input file\n")
        return 1
    input_path = Path(argv[out_index - 1])
    try:
        data = input_path.read_bytes()
    except FileNotFoundError:
        sys.stderr.write(f"fake_metal: input {input_path} not found\n")
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    header = b"// fake metal AIR placeholder\n"
    output.write_bytes(header + data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
