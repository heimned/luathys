"""
Luathys Offline Decompiler - Luacid edition
Converts every .luac (raw Luau bytecode) in a dump folder into readable .lua
using the Luacid API (https://luacid.dev), which handles current Roblox
bytecode versions and recovers real variable names + type annotations.

Keyless tier: 512 KB per file, 60 requests/min per IP.
The script self-rate-limits (~1.1s between calls) and can RESUME:
files whose .lua already exists and isn't a failure marker are skipped.

Usage:
    python decompile_all.py <dump_folder>
    python decompile_all.py <dump_folder> --key 67_your_luacid_key
"""

import argparse
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

API_URL = "https://api.luacid.dev/decompile"
FAIL_MARKERS = ("-- luacid error", "-- unluau failed", "-- unluau timed out")

def decompile_once(luac_path: Path, api_key: str | None):
    data = luac_path.read_bytes()
    req = urllib.request.Request(
        API_URL,
        data=data,
        method="POST",
        headers={"Content-Type": "application/octet-stream"},
    )
    if api_key:
        req.add_header("Authorization", f"Bearer {api_key}")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8", errors="replace")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", help="dump folder containing .luac files")
    ap.add_argument("--key", help="Luacid API key (raises rate limits)", default=None)
    ap.add_argument("--fresh", action="store_true",
                    help="re-decompile even if a .lua result already exists")
    args = ap.parse_args()

    root = Path(args.folder)
    if not root.exists():
        print(f"Folder not found: {root}")
        sys.exit(1)

    luac_files = sorted(root.rglob("*.luac"))
    print(f"Found {len(luac_files)} bytecode files")

    ok, failed, skipped = 0, 0, 0
    t0 = time.time()

    for i, luac in enumerate(luac_files, 1):
        out_path = luac.with_suffix(".lua")

        # Resume support
        if out_path.exists() and not args.fresh:
            existing = out_path.read_text(encoding="utf-8", errors="replace")
            if not any(m in existing for m in FAIL_MARKERS):
                skipped += 1
                continue

        # Keyless tier: 60 req/min -> stay just under with ~1.05s spacing
        if i > 1:
            time.sleep(1.05)

        try:
            src = decompile_once(luac, args.key)
            header = (
                f"--[decompiled by Luathys via luacid.dev | source: {luac.name}]\n"
            )
            out_path.write_text(header + src, encoding="utf-8", errors="replace")
            ok += 1
        except urllib.error.HTTPError as e:
            detail = ""
            try:
                detail = e.read().decode("utf-8", errors="replace")[:150]
            except Exception:
                pass
            out_path.write_text(
                f"-- luacid error HTTP {e.code}: {detail}\n-- source bytecode: {luac.name}\n",
                encoding="utf-8",
            )
            failed += 1
        except Exception as e:
            out_path.write_text(
                f"-- luacid error: {e}\n-- source bytecode: {luac.name}\n",
                encoding="utf-8",
            )
            failed += 1

        if i % 10 == 0 or i == len(luac_files):
            elapsed = time.time() - t0
            eta = elapsed / i * (len(luac_files) - i)
            print(f"  [{i}/{len(luac_files)}] ok={ok} fail={failed} skip={skipped} "
                  f"eta={eta/60:.1f}min")

    print(f"\nDone. Decompiled {ok}, failed {failed}, already-done {skipped}")

if __name__ == "__main__":
    main()