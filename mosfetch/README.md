# mosfetch

Modular MOSDAC downloader for **INSAT-3DR L1C-SGP imager** scenes
(`3RIMG_*_L1C_SGP_*.h5`) — the 9-channel product behind `single_sat_radar_v2.nc`.

## Layers

| File | Responsibility |
|---|---|
| `config.py` | `DownloadConfig` — all knobs (env + CLI + defaults). No secrets in code. |
| `client.py` | `MosdacClient` — REST client: `search` / `get_token` / `download` + retry. |
| `downloader.py` | `Downloader` — date-range walk, product filter, dedupe, resume, parallel, manifest. |
| `__main__.py` | CLI (`python -m mosfetch`). |

Each layer is independent: swap the client, reuse the downloader, test config alone.

## Setup

```bash
export MOSDAC_USER=your_user
export MOSDAC_PASS=your_pass
# optional: exact catalog id (else default 3RIMG_L1C_SGP)
export MOSDAC_DATASET_ID=3RIMG_L1C_SGP
pip install requests          # only hard dep (h5py only needed to READ files)
```

> **dataset_id**: copy the exact `datasetId` string from the MOSDAC "Open Data"
> catalog page for the INSAT-3DR Imager L1C-SGP collection if the default does
> not match your account's catalog.

## Use

```bash
# dry run — list what would download (public search, no credentials)
python -m mosfetch --start 2024-07-01 --end 2024-07-03 --dry-run

# download central-India domain, all scenes in range
python -m mosfetch --start 2024-07-01 --end 2024-07-03

# thin to 4 scenes/day, full disk, custom output
python -m mosfetch --start 2024-07-01 --end 2024-07-31 \
    --bbox "" --max-per-day 4 --dest data/insat_raw --workers 6
```

Programmatic:

```python
from mosfetch import DownloadConfig, Downloader

cfg = DownloadConfig(dataset_id="3RIMG_L1C_SGP", dest="data/insat_raw",
                     bbox="74,16,84,26", max_per_day=4)
summary = Downloader(cfg).download_range("2024-07-01", "2024-07-31")
print(summary)   # {'found': N, 'downloaded': N, 'skipped': 0, 'failed': 0}
```

## Features

- **Resume**: existing files skipped unless `--overwrite`.
- **Manifest**: one JSONL line per file at `<dest>/manifest.jsonl` (time, id, bytes, path).
- **Resilient**: transient MOSDAC 5xx / timeouts retried with backoff; one bad
  file never kills the batch.
- **Dry run**: `--dry-run` lists scenes without auth/download.

Default bbox `74,16,84,26` covers the central-India DWR domain. Pass `--bbox ""`
for full disk.
