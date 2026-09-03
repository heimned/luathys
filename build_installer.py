"""Build script for Luathys Extractor - creates a standalone executable.

Entry point: src/core/main.py (the desktop GUI).

Prerequisites:
    pip install -r requirements.txt
"""
import shutil
import subprocess
import sys
from pathlib import Path


def build() -> bool:
    app_dir = Path(__file__).parent.resolve()
    entry = app_dir / "src" / "core" / "main.py"
    dist_dir = app_dir / "dist"
    build_dir = app_dir / "build"

    if not entry.exists():
        print(f"Entry point not found: {entry}")
        return False

    # Clean previous builds
    if dist_dir.exists():
        shutil.rmtree(dist_dir)
    if build_dir.exists():
        shutil.rmtree(build_dir)

    args = [
        "--onefile",
        "--windowed",
        "--name", "LuathysExtractor",
        "--distpath", str(dist_dir),
        "--workpath", str(build_dir),
        "--specpath", str(app_dir),
        "--noconfirm",
        str(entry),
    ]

    print("Building Luathys Extractor...")
    result = subprocess.run(
        [sys.executable, "-m", "PyInstaller", *args],
        cwd=str(app_dir),
    )

    if result.returncode != 0:
        print(f"\nBuild failed with code {result.returncode}")
        return False

    exe = dist_dir / "LuathysExtractor.exe"
    if not exe.exists():
        print("Build completed but executable not found")
        return False

    print("\nBuild successful!")
    print(f"Executable: {exe}")
    print(f"Size: {exe.stat().st_size / 1024 / 1024:.1f} MB")
    return True


if __name__ == "__main__":
    sys.exit(0 if build() else 1)
