# 🌧️ MOSFETCH

Download INSAT-3DR L1C-SGP satellite imagery from MOSDAC in parallel with resume/retry.

**MOSFETCH** = MOSDAC + Fetch (with a weather-themed twist!)

## Requirements

- **Python 3.10+** ([download here](https://www.python.org/downloads/))
- **MOSDAC account** ([register at mosdac.gov.in](https://mosdac.gov.in/)) with dataset access
- **Internet connection** for downloading satellite data

## Installation

### Step 1: Clone the Repository

```bash
git clone https://github.com/explolar/mosfetch.git
cd mosfetch
```

Or download as ZIP and extract.

### Step 2: Install Dependencies

**Option A: Windows (PowerShell)**
```powershell
pip install requests
```

**Option B: Linux/Mac (Terminal)**
```bash
pip install requests
# or with pip3 if you have Python 2 and 3:
pip3 install requests
```

**Optional:** For reading `.h5` files locally:
```bash
pip install h5py
```

### Step 3: Set Up MOSDAC Credentials

**Option A: Environment Variables (Recommended)**

**Windows (PowerShell):**
```powershell
$env:MOSDAC_USER = "your_username"
$env:MOSDAC_PASS = "your_password"
```

**Linux/Mac (Terminal):**
```bash
export MOSDAC_USER="your_username"
export MOSDAC_PASS="your_password"
```

**Option B: System Environment Variables (Permanent)**

**Windows:**
1. Press `Win + X`, open **System (Settings)**
2. Click **Advanced system settings**
3. Click **Environment Variables**
4. Under **User variables**, click **New**
5. Variable name: `MOSDAC_USER`, Value: your username
6. Repeat for `MOSDAC_PASS`
7. Restart PowerShell

**Linux/Mac:** Add to `~/.bashrc` or `~/.zshrc`:
```bash
export MOSDAC_USER="your_username"
export MOSDAC_PASS="your_password"
```
Then run: `source ~/.bashrc`

## How to Use

### Method 1: Windows Menu (Easiest)

Open PowerShell in the folder and run:
```powershell
.\interactive_downloader.ps1
```

Follow the prompts:
1. **Satellite:** Choose 3DS, 3DR, 3D, or ALL
2. **Product:** Select products or press A for all
3. **Output folder:** Where to save `.h5` files (default: `D:\insat_data`)
4. **Date range:** Start and end dates (YYYY-MM-DD format)
5. **Confirm:** Review settings and press Y to start

Example interaction:
```
MOSDAC Username: user123
MOSDAC Password: ****
Satellite (3DS/3DR/3D/ALL): 3DR
Products for 3DR (1-5 or A): A
Output folder (D:\insat_data):  D:\insat_data
Start date (YYYY-MM-DD): 2024-07-01
End date (YYYY-MM-DD): 2024-07-31
Download 486 files? (Y/N): Y
Downloading... [████████████████░░] 85%
```

### Method 2: Command Line (CLI)

**List files (dry run, no download):**
```bash
python -m mosfetch --start 2024-07-01 --end 2024-07-03 --dry-run
```

**Download to default folder:**
```bash
python -m mosfetch --start 2024-07-01 --end 2024-07-31
```

**Download with custom options:**
```bash
python -m mosfetch \
  --start 2024-07-01 \
  --end 2024-07-31 \
  --bbox "74,16,84,26" \
  --dest "data/insat_raw" \
  --max-per-day 4 \
  --workers 6
```

**Full disk (all locations):**
```bash
python -m mosfetch \
  --start 2024-07-01 \
  --end 2024-07-31 \
  --bbox ""
```

### Method 3: Python Code (Programmatic)

```python
from mosfetch import DownloadConfig, Downloader

# Configure download
cfg = DownloadConfig(
    dataset_id="3RIMG_L1C_SGP",
    dest="data/insat_raw",
    bbox="74,16,84,26",         # Central India (or "" for full disk)
    max_per_day=4,              # Max 4 scenes per day
    workers=4                   # Parallel downloads
)

# Download and get summary
downloader = Downloader(cfg)
summary = downloader.download_range("2024-07-01", "2024-07-31")
print(summary)
# Output: {'found': 120, 'downloaded': 120, 'skipped': 0, 'failed': 0}
```

## Output Structure

Downloaded files are organized as:
```
<output_folder>/
├── 3RIMG_L1C_SGP/           # Dataset folder
│   ├── 20240701_0000.h5
│   ├── 20240701_0030.h5
│   ├── ...
│   └── manifest.jsonl       # Log: one line per file
└── <other_dataset>/
```

**Manifest file** (manifest.jsonl) contains one JSON object per line:
```json
{"time": "2024-07-01T00:00:00", "id": "3RIMG_L1C_SGP_20240701_0000", "bytes": 157286400, "path": "data/insat_raw/3RIMG_L1C_SGP/20240701_0000.h5"}
```

## Features

- **Resume mode** — Re-run anytime. Existing files skipped unless `--overwrite`
- **Parallel downloads** — Configurable number of workers (default: 4)
- **Manifest logging** — JSONL file tracks every download
- **Resilient** — Automatic retry on transient errors (5xx, timeouts)
- **Dry run** — List what would download without credentials
- **Bounding box** — Filter by geography or download full disk
- **Per-day cap** — Thin dataset (INSAT every ~30 min = 48 scenes/day)

## Troubleshooting

### "MOSDAC credentials missing"
**Error:** `RuntimeError: MOSDAC credentials missing`
- Check: `echo $env:MOSDAC_USER` (Windows) or `echo $MOSDAC_USER` (Linux)
- If empty, re-run Step 3 to set environment variables
- Or pass `--username=user --password=pass` on CLI

### "401 UNAUTHORIZED"
Your MOSDAC account lacks access to that product on that date. Request access on [mosdac.gov.in](https://mosdac.gov.in).

### "MOSDAC 500" / Timeouts
Transient server errors. Downloader retries automatically. Safe to re-run.

### "Permission denied" on PowerShell
If script won't run, execute once:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Files already exist
By default, existing files are skipped. To re-download:
```bash
python -m insat_download ... --overwrite
```

## Project Structure

```
mosfetch/
├── mosfetch/                    # Python module
│   ├── config.py               # DownloadConfig (all settings)
│   ├── client.py               # MosdacClient (REST layer)
│   ├── downloader.py           # Downloader (orchestration)
│   ├── __main__.py             # CLI argument parser
│   └── README.md               # Full API documentation
├── interactive_downloader.ps1  # PowerShell menu launcher
├── INSTRUCTIONS.txt            # Setup reference
└── README.md                   # This file
```

## Credentials Security

Credentials are **never** stored in code. Provide them via:
1. **Environment variables** (recommended): `MOSDAC_USER`, `MOSDAC_PASS`
2. **CLI arguments**: `--username=... --password=...`
3. **Interactive prompt** (PowerShell launcher will ask)

## CLI Reference

```bash
python -m mosfetch [OPTIONS]

Options:
  --dataset-id TEXT             MOSDAC catalog ID [default: 3RIMG_L1C_SGP]
  --dest PATH                   Output directory [default: data/insat_raw]
  --bbox TEXT                   "lon_min,lat_min,lon_max,lat_max" [default: 74,16,84,26]
  --username TEXT               MOSDAC username
  --password TEXT               MOSDAC password
  --start DATE                  Start date (YYYY-MM-DD)
  --end DATE                    End date (YYYY-MM-DD)
  --max-per-day INTEGER         Max scenes per calendar day [default: 0 = unlimited]
  --overwrite                   Re-download existing files
  --workers INTEGER             Parallel downloads [default: 4]
  --dry-run                     List scenes without downloading
  --manifest PATH               JSONL manifest file [default: <dest>/manifest.jsonl]
```

## Examples

**Download 1 week, central India, 8 parallel workers:**
```bash
python -m mosfetch --start 2024-07-01 --end 2024-07-07 --workers 8
```

**Full disk, thin to 2 scenes/day:**
```bash
python -m mosfetch --start 2024-07-01 --end 2024-07-31 --bbox "" --max-per-day 2
```

**Preview without downloading:**
```bash
python -m mosfetch --start 2024-07-01 --end 2024-07-03 --dry-run
```

## More Information

- **[API Docs](mosfetch/README.md)** — Module reference, config, programmatic examples
- **[INSTRUCTIONS.txt](INSTRUCTIONS.txt)** — Original setup guide

## License

MIT
