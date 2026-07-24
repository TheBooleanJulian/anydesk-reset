<div align="center">

# anydesk-reset

**Reset your AnyDesk ID cleanly — a Windows utility with backup/restore support.**

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/license-AGPLv3%20%7C%20Commercial-00D4C8.svg)

</div>

---

## What it does

AnyDesk ties its client identity to locally stored configuration files. This utility wipes that identity so AnyDesk generates a fresh ID on next launch — useful when a machine's ID needs to be rotated or when troubleshooting connection issues. It ships as a console flow (`.bat` + `.ps1`) and an optional WinForms GUI, both built on a shared PowerShell module, with a backup/restore flow so the original config can be recovered if needed.

## Features

- Resets the local AnyDesk ID by clearing relevant config/data files
- Backup step preserves the existing AnyDesk config before wiping
- Restore step lets you roll back to any previous backup
- Console flow — run the batch file, follow the prompts
- Optional lightweight GUI — buttons for Full Reset / Backup Only / Restore Selected, with a live log
- Works on Windows with no external dependencies

## Tech Stack

| Layer | Choice |
|---|---|
| Script | PowerShell + Batch |
| GUI | Windows Forms (WinForms) |
| Platform | Windows |

## Quick Start

1. Close AnyDesk completely (check the system tray).
2. Pick a front end:
   - **Console**: right-click `anydesk-reset.bat` and run as **Administrator**, or run the PowerShell script directly:
     ```powershell
     # Run as Administrator
     powershell -ExecutionPolicy Bypass -File anydesk-reset.ps1
     ```
   - **GUI**: right-click `anydesk-reset-gui.bat` and run as **Administrator**, or run the PowerShell script directly:
     ```powershell
     # Run as Administrator
     powershell -ExecutionPolicy Bypass -File anydesk-reset-gui.ps1
     ```
3. Follow the prompts (console) or click the buttons (GUI) to back up, reset, or restore your AnyDesk config.
4. Relaunch AnyDesk — a new ID will be assigned.

## Project Structure

```
anydesk-reset/
|-- anydesk-reset.bat        # Console entry point launcher
|-- anydesk-reset.ps1        # Console front end
|-- anydesk-reset-gui.bat    # GUI entry point launcher
|-- anydesk-reset-gui.ps1    # WinForms GUI front end
`-- AnyDeskReset.Core.psm1   # Shared backup/reset/restore logic used by both front ends
```

## Status

- [x] Reset flow working
- [x] Backup/restore UI
- [x] Lightweight GUI (WinForms) alongside the console flow

## Future Roadmap

- [ ] Silent/unattended mode flag (e.g. `-Silent`) for scripted/scheduled runs
- [ ] Auto-detect AnyDesk install path across versions (user vs. system install, portable/custom-branded clients)
- [ ] CLI arguments to trigger reset/backup/restore directly, bypassing the interactive prompts
- [ ] Action logging to a local log file for auditing what was backed up/reset/restored and when
- [ ] Checksum/integrity check on backups before allowing a restore
- [ ] Option to stop/restart the AnyDesk service automatically instead of relying on the user to close it manually
- [ ] Scheduled ID rotation via Task Scheduler integration
- [ ] System tray icon / notification when a scheduled reset runs in the background

## Changelog

Versioning follows `MAJOR.MINOR` based on commit significance — major for core functionality, minor for additive/non-breaking changes like docs.

| Version | Date | Change |
|---|---|---|
| v1.2 | 2026-07-24 | Added a WinForms GUI front end; extracted shared logic into `AnyDeskReset.Core.psm1` |
| v1.1 | 2026-07-18 | Added README documentation |
| v1.0 | 2026-07-02 | Initial release: AnyDesk reset utility with backup and restore UI, shipped as `.bat` + `.ps1` |

## License

This project is dual licensed.

**Community Edition** — [GNU Affero General Public License v3 (AGPLv3)](https://github.com/TheBooleanJulian/thebooleanjulian.github.io/blob/main/LICENSE). Free to use, modify, and self-host. If you distribute a modified version or run it as a network service, you must make the corresponding source available.

**Commercial License** — for organisations that want to embed, modify, or distribute this software without AGPLv3's obligations. See [COMMERCIAL-LICENSE.md](https://github.com/TheBooleanJulian/thebooleanjulian.github.io/blob/main/COMMERCIAL-LICENSE.md).

---

<div align="center">
<sub>Built by <a href="https://github.com/TheBooleanJulian">@TheBooleanJulian</a></sub>
</div>