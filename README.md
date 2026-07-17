<div align="center">

# anydesk-reset

**Reset your AnyDesk ID cleanly — a Windows utility with backup/restore support.**

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-00D4C8.svg)

</div>

---

## What it does

AnyDesk ties its client identity to locally stored configuration files. This utility wipes that identity so AnyDesk generates a fresh ID on next launch — useful when a machine's ID needs to be rotated or when troubleshooting connection issues. It ships as both a `.bat` launcher and a `.ps1` core script, and includes a backup/restore flow so the original config can be recovered if needed.

## Features

- Resets the local AnyDesk ID by clearing relevant config/data files
- Backup step preserves the existing AnyDesk config before wiping
- Restore step lets you roll back to the backed-up config
- Simple UI flow — run the batch file, follow the prompts
- Works on Windows with no external dependencies

## Tech Stack

| Layer | Choice |
|---|---|
| Script | PowerShell + Batch |
| Platform | Windows |

## Quick Start

1. Close AnyDesk completely (check the system tray).
2. Right-click `anydesk-reset.bat` and run as **Administrator**, or run the PowerShell script directly:

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File anydesk-reset.ps1
```

3. Follow the on-screen prompts to back up, reset, or restore your AnyDesk config.
4. Relaunch AnyDesk — a new ID will be assigned.

## Project Structure

```
anydesk-reset/
|-- anydesk-reset.bat    # Entry point launcher
`-- anydesk-reset.ps1    # Core reset/backup/restore logic
```

## Status / Roadmap

- [x] Reset flow working
- [x] Backup/restore UI
- [ ] Silent/unattended mode flag
- [ ] Auto-detect AnyDesk install path across versions

## Changelog

- **2025-07** — Initial release: AnyDesk reset utility with backup and restore UI, shipped as `.bat` + `.ps1`

## License

MIT

---

<div align="center">
<sub>Built by <a href="https://github.com/TheBooleanJulian">@TheBooleanJulian</a></sub>
</div>