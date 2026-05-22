# Windows ActivityWatch installer

Build the one-file installer:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-windows-installer.ps1
```

Send this generated file:

```text
dist\CursorBusyActivityWatchInstaller.exe
```

The installer is for Windows machines that already have ActivityWatch installed
and opened at least once.

It installs these bundled ActivityWatch modules:

```text
%LOCALAPPDATA%\Programs\ActivityWatch\aw-watcher-cursor-busy\aw-watcher-cursor-busy.exe
%LOCALAPPDATA%\Programs\ActivityWatch\aw-cursor-busy-report\aw-cursor-busy-report.exe
```

It removes old PATH-based launchers from locations such as:

```text
%USERPROFILE%\.local\bin
%APPDATA%\Python\Python312\Scripts
```

It also adds `aw-watcher-cursor-busy` to:

```text
%LOCALAPPDATA%\activitywatch\activitywatch\aw-qt\aw-qt.toml
```

The installer writes diagnostics to:

```text
%LOCALAPPDATA%\aw-watcher-cursor-busy\installer.log
```
