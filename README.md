# INSAT Downloader

Download INSAT-3DR L1C-SGP satellite imagery from MOSDAC in parallel with resume/retry.

## Quick Start

**Requirements:** Python 3.10+, MOSDAC account ([mosdac.gov.in](https://mosdac.gov.in/))

**Windows (PowerShell):**
```powershell
.\interactive_downloader.ps1
# Follow prompts for satellite, product, date range, output folder
```

**Linux/Mac (CLI):**
```bash
export MOSDAC_USER=your_username
export MOSDAC_PASS=your_password
python -m insat_download --start 2024-07-01 --end 2024-07-31
```

## Features

- **Parallel downloads** — configurable workers
- **Resume mode** — skip existing files, safe to re-run
- **Manifest** — JSONL log per file (time, id, bytes, path)
- **Resilient** — retry transient 5xx errors with backoff
- **Dry run** — list scenes without downloading

## Documentation

- **[insat_download/README.md](insat_download/README.md)** — module API, config, programmatic use
- **INSTRUCTIONS.txt** — detailed setup & troubleshooting

## Project Structure

```
insat_downloader/
├── insat_download/              # Python module
│   ├── config.py               # DownloadConfig (all settings)
│   ├── client.py               # MosdacClient (REST layer)
│   ├── downloader.py           # Downloader (orchestration)
│   ├── __main__.py             # CLI
│   └── README.md               # Full API docs
├── interactive_downloader.ps1  # Menu-driven launcher (Windows)
├── INSTRUCTIONS.txt            # User guide
└── README.md                   # This file
```

## Credentials

Never stored in code. Provide via:
- Environment: `MOSDAC_USER`, `MOSDAC_PASS`
- CLI: `python -m insat_download --username=... --password=...`
- Interactive prompt (PowerShell launcher)

## License

MIT
