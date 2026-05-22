import os
import subprocess
import sys
from pathlib import Path


def resource_path(name: str) -> Path:
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    return base / name


def main() -> int:
    script = resource_path("install-windows-activitywatch.ps1")
    if not script.exists():
        print(f"Installer script not found: {script}")
        input("Press Enter to exit...")
        return 1

    os.chdir(script.parent)

    print("Ask Away ActivityWatch Installer")
    print()
    print("This will install aw-watcher-ask-away and enable it inside ActivityWatch.")
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
        print("Installation finished successfully.")
    else:
        print(f"Installation failed with exit code {result.returncode}.")

    print()
    input("Press Enter to close...")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
