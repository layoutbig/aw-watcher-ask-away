# Windows ActivityWatch install

This repository includes a one-file Windows installer for machines that already
have ActivityWatch installed.

## Simple installer

Build the EXE:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-windows-installer.ps1
```

Send this generated file to the user:

```text
dist\AskAwayActivityWatchInstaller.exe
```

The user double-clicks the EXE and follows the console progress. The installer
uses the ActivityWatch module manager, so Ask Away starts with ActivityWatch and
does not create a separate Startup shortcut.

The EXE build uses PyInstaller and applies the ActivityWatch icon from the local
ActivityWatch installation when available.

## Script installer

You can also run the raw installer script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-windows-activitywatch.ps1
```

To install from this local checkout instead of the embedded wheel or PyPI:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-windows-activitywatch.ps1 -PackageSpec .
```

## What the installer does

1. Confirms that ActivityWatch has created `aw-qt.toml`.
2. Finds Python 3.11+.
3. If no compatible Python exists, downloads and installs Python 3.12.10 for the current user.
4. Installs `pipx`.
5. Installs `aw-watcher-ask-away` through `pipx`.
6. Includes a standalone `aw-watcher-ask-away.exe` payload built with PyInstaller.
7. Copies that standalone watcher into ActivityWatch's own modules folder:

```text
%LOCALAPPDATA%\Programs\ActivityWatch\aw-watcher-ask-away\aw-watcher-ask-away.exe
```

This avoids relying on the user's PATH when ActivityWatch starts with Windows.

8. Removes any separate Windows Startup shortcut named `aw-watcher-ask-away.lnk`.
9. Adds `aw-watcher-ask-away` to ActivityWatch's `autostart_modules` list in:

```text
%LOCALAPPDATA%\activitywatch\activitywatch\aw-qt\aw-qt.toml
```

10. Restarts ActivityWatch unless `-NoRestartActivityWatch` is passed.

The installer also writes a diagnostic log to:

```text
%LOCALAPPDATA%\aw-watcher-ask-away\installer.log
```

## Exact changes applied on this computer

The manual installation on this computer did the following:

1. Installed Python 3.12.10 for the current user because `python` and `pipx` were not available in PATH.
2. Installed `pipx` with:

```powershell
py -3.12 -m pip install --user pipx
py -3.12 -m pipx ensurepath
```

3. Installed the local checkout with:

```powershell
py -3.12 -m pipx install . --python "C:\Users\Projeto2\AppData\Local\Programs\Python\Python312\python.exe"
```

4. Confirmed the command worked:

```powershell
C:\Users\Projeto2\.local\bin\aw-watcher-ask-away.exe --help
```

5. Initially created a separate Windows Startup shortcut, then removed it because ActivityWatch should manage the module itself.
6. Updated:

```text
C:\Users\Projeto2\AppData\Local\activitywatch\activitywatch\aw-qt\aw-qt.toml
```

to:

```toml
[aw-qt]
autostart_modules = ["aw-server", "aw-watcher-afk", "aw-watcher-window", "aw-watcher-ask-away"]

[aw-qt-testing]
#autostart_modules = ["aw-server", "aw-watcher-afk", "aw-watcher-window"]
```

7. Rebuilt:

```text
C:\Users\Projeto2\.local\bin\aw-watcher-ask-away.exe
```

as a GUI launcher pointing to:

```text
C:\Users\Projeto2\pipx\venvs\aw-watcher-ask-away\Scripts\pythonw.exe
```

8. Removed the temporary duplicate launcher:

```text
C:\Users\Projeto2\.local\bin\aw-watcher-ask-away.console.exe
```

9. Restarted ActivityWatch and verified that `aw-watcher-ask-away.exe` starts as a child process of `aw-qt.exe`.

## Notes

The installer does not add a separate Windows Startup entry for Ask Away. It
uses ActivityWatch's own module manager. This is what makes the module appear
checked under ActivityWatch > Modules and start together with ActivityWatch.
