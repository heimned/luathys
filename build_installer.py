"""Build script for Luathys Extractor - creates standalone executable."""
import os
import sys
import shutil
import subprocess
from pathlib import Path

def build():
    app_dir = Path(__file__).parent
    dist_dir = app_dir / "dist"
    build_dir = app_dir / "build"

    # Clean previous builds
    if dist_dir.exists():
        shutil.rmtree(dist_dir)
    if build_dir.exists():
        shutil.rmtree(build_dir)

    # Install dependencies
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyqt6", "pymem", "pyinstaller"])

    args = [
        "--onefile",
        "--windowed",
        "--name", "LuathysExtractor",
        "--add-data", f"{Path('unluau')}#unluau",
        "--distpath", str(dist_dir),
        "--workpath", str(build_dir),
        "--specpath", str(app_dir),
        str(app_dir / "main.py"),
    ]

    print("Building Luathys Extractor...")
    result = subprocess.run(
        [sys.executable, "-m", "PyInstaller"] + args,
        cwd=str(app_dir)
    )

    if result.returncode == 0:
        exe_path = dist_dir / "LuathysExtractor.exe"
        if exe_path.exists():
            print(f"\n✅ Build successful!")
            print(f"Executable: {exe_path}")
            print(f"Size: {exe_path.stat().st_size / 1024 / 1024:.1f} MB")
            return True
        else:
            print("Build completed but executable not found")
            return False
    else:
        print(f"\n❌ Build failed with code {result.returncode}")
        return False

if __name__ == "__main__":
    success = build()
    sys.exit(0 if success else 1)