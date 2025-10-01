#!/usr/bin/env python3
import sys
from pathlib import Path

def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] != "-o":
        sys.stderr.write("Usage: fake_metallib <input.air> -o <output.metallib>\n")
        return 1
    input_path = Path(argv[0])
    output_path = Path(argv[2])
    try:
        data = input_path.read_bytes()
    except FileNotFoundError:
        sys.stderr.write(f"fake_metallib: input {input_path} not found\n")
        return 1
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(b"// fake metallib placeholder\n" + data)
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
