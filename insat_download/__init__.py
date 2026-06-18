"""
insat_download — modular MOSDAC downloader for INSAT-3DR L1C-SGP imager scenes.

Layers (each independently usable / testable):
    config.py      DownloadConfig — all knobs from env + CLI + defaults.
    client.py      MosdacClient  — thin MOSDAC REST client (search/token/download).
    downloader.py  Downloader    — range iteration, resume, manifest, retries.
    __main__.py    CLI           — `python -m insat_download ...`.

Quick start:
    export MOSDAC_USER=...   MOSDAC_PASS=...
    python -m insat_download --start 2024-07-01 --end 2024-07-03

Programmatic:
    from insat_download import DownloadConfig, Downloader
    cfg = DownloadConfig(dataset_id="3RIMG_L1C_SGP", dest="data/raw")
    Downloader(cfg).download_range("2024-07-01", "2024-07-03")
"""
from .config import DownloadConfig
from .client import MosdacClient, MosdacUnavailable
from .downloader import Downloader

__all__ = ["DownloadConfig", "MosdacClient", "MosdacUnavailable", "Downloader"]
