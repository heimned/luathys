"""
Luathys Offline Decompiler
Walks a dump folder and converts every .luac (raw Luau bytecode)
into readable .lua using unluau.exe.

Usage:
    python decompile_all.py <dump_folder>

Example:
    python decompile_all.py "Ugc_130960021905304"

Requires unluau.exe in this script's folder (or pass --unluau path).
"""

import argparse
import subprocess
import sys
from pathlib import Path

def find_unluau(explicit=None):
    if explicit:
        p = Path(explicit)
        if p.exists():
            return p
        raise FileNotFoundError(f"unluau not found at {explicit}")
    here = Path(__file__).parent
    for candidate in [here / "unluau.exe", here / "unluau" / "unluau.exe"]:
        if candidate.exists():
            return candidate
    raise FileNotFoundError(
        "unluau.exe not found next to this script. "
        "Download from https://github.com/atrexus/unluau/releases"
    )

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", help="dump folder containing .luac files")
    ap.add_argument("--unluau", help="path to unluau.exe", default=None)
    args = ap.parse_args()

    root = Path(args.folder)
    if not root.exists():
        print(f"Folder not found: {root}")
        sys.exit(1)

    unluau = find_unluau(args.unluau)
    print(f"Decompiler: {unluau}")

    luac_files = sorted(root.rglob("*.luac"))
    print(f"Found {len(luac_files)} bytecode files")

    ok, failed = 0, 0
    for i, luac in enumerate(luac_files, 1):
        out_path = luac.with_suffix(".lua")
        try:
            result = subprocess.run(
                [str(unluau), str(luac)],
                capture_output=True, text=True, timeout=60,
            )
            src = result.stdout or ""
            if result.returncode == 0 and src.strip():
                header = f"--[decompiled by Luathys/unluau | source: {luac.name}]\n"
                out_path.write_text(header + src, encoding="utf-8", errors="replace")
                ok += 1
            else:
                err = (result.stderr or "no output").strip()[:120]
                out_path.write_text(
                    f"-- unluau failed: {err}\n-- source bytecode: {luac.name}\n",
                    encoding="utf-8",
                )
                failed += 1
        except subprocess.TimeoutExpired:
            out_path.write_text("-- unluau timed out\n", encoding="utf-8")
            failed += 1

        if i % 25 == 0 or i == len(luac_files):
            print(f"  [{i}/{len(luac_files)}]")

    print(f"\nDone. Decompiled {ok}, failed {failed}")
    print("Failed files keep their .luac - retry when you have a better decompiler.")

if __name__ == "__main__":
    main()