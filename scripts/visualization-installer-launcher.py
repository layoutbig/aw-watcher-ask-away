import os
import subprocess
import sys
from pathlib import Path


def resource_path(name: str) -> Path:
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    return base / name


def main() -> int:
    script = resource_path("install-windows-visualization.ps1")
    if not script.exists():
        print(f"Installer script not found: {script}")
        input("Press Enter to exit...")
        return 1

    os.chdir(script.parent)

    print("Ask Away Visualization Installer")
    print()
    print("This will install the aw-watcher-ask-away custom visualization for ActivityWatch.")
    print()

    command = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
    ]

    result = subprocess.run(command, cwd=script.parent)
    print()

    if result.returncode == 0:
        print("Visualization installation finished successfully.")
    else:
        print(f"Visualization installation failed with exit code {result.returncode}.")

    print()
    input("Press Enter to close...")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
