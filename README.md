# AW Watcher Ask Away

[![PyPI - Version](https://img.shields.io/pypi/v/aw-watcher-ask-away.svg)](https://pypi.org/project/aw-watcher-ask-away)
[![PyPI - Python Version](https://img.shields.io/pypi/pyversions/aw-watcher-ask-away.svg)](https://pypi.org/project/aw-watcher-ask-away)

---

This [ActivityWatch](https://activitywatch.net) "watcher" asks you what you were doing in a pop-up dialogue when you get back to your computer from an AFK (away from keyboard) break.

## Installation

```console
pipx install aw-watcher-ask-away
```

([Need to install `pipx` first?](https://pypa.github.io/pipx/installation/))

## Custom visualization

This repository includes an experimental ActivityWatch custom visualization at:

```text
visualization/dist
```

The Windows installer embeds that HTML and installs it into the user's
ActivityWatch directory:

```text
%LOCALAPPDATA%\activitywatch\activitywatch\aw-watcher-ask-away\visualization\dist\index.html
```

It also registers the installed directory in `aw-server.toml`:

```toml
[server.custom_static]
aw-watcher-ask-away = "C:/Users/<USER>/AppData/Local/activitywatch/activitywatch/aw-watcher-ask-away/visualization/dist"
```

On Windows, the default config file is usually:

```text
%LOCALAPPDATA%\activitywatch\activitywatch\aw-server\aw-server.toml
```

Restart ActivityWatch after editing the config. Then open the Activity view, click
`Edit view`, add a visualization, select `Custom visualization`, and enter:

```text
aw-watcher-ask-away
```

The visualization finds the `aw-watcher-ask-away_<hostname>` bucket automatically
and summarizes the recorded `data.message` entries.

If you edit the TOML from PowerShell, make sure it is saved as UTF-8 without BOM.
Older Windows PowerShell commands such as `Set-Content -Encoding UTF8` can add a
BOM that makes `aw-server` fail at startup with `tomlkit.exceptions.EmptyKeyError`.

To build a visualization-only installer for users who already have ActivityWatch
and `aw-watcher-ask-away` installed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\build-windows-visualization-installer.ps1
```

The output is:

```text
dist\AskAwayVisualizationInstaller.exe
```

## Roadmap

Most of the improvements involve a more complicated pop-up window.

- Use `pyinstaller` or something for distribution to people who are not developers and know how to install things from PyPI.
  - Set up a website, probably with a GitHub organization.
- Handle calls better/stop asking what you were doing every couple minutes when in a call.
- See whether people would rather add data to AFK events instead of creating a separate bucket. Maybe make that an option/configurable.

## Contributing

Here are some helpful links:

- [How to create an ActivityWatch watcher](https://docs.activitywatch.net/en/latest/examples/writing-watchers.html).
- ["Manually tracking away/offline-time" forum discussion](https://forum.activitywatch.net/t/manually-tracking-away-offline-time/284)

Note: I am using this project to get experience with the `hatch` project manager.
I have never use it before and I'm probably doing some things wrong there.

## License

`aw-watcher-ask-away` is distributed under the terms of the [MIT](https://spdx.org/licenses/MIT.html) license.
