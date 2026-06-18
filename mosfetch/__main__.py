"""
CLI for the modular INSAT-3DR downloader.

Examples
--------
  # credentials from env (MOSDAC_USER / MOSDAC_PASS)
  python -m mosfetch --start 2024-07-01 --end 2024-07-03

  # dry run — just list what WOULD download (no auth needed)
  python -m mosfetch --start 2024-07-01 --end 2024-07-03 --dry-run

  # thin to 4 scenes/day, full disk, custom output + dataset id
  python -m mosfetch --start 2024-07-01 --end 2024-07-31 \
      --dataset-id 3RIMG_L1C_SGP --bbox "" --max-per-day 4 --dest data/insat_raw
"""
from __future__ import annotations

import argparse
import logging
import sys

from .config import DownloadConfig
from .downloader import Downloader


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="mosfetch",
                                 description="Modular MOSDAC INSAT-3DR L1C-SGP downloader.")
    ap.add_argument("--start", required=True, help="start date YYYY-MM-DD (inclusive)")
    ap.add_argument("--end", required=True, help="end date YYYY-MM-DD (inclusive)")
    ap.add_argument("--dataset-id", default=None, help="MOSDAC datasetId (else env/default)")
    ap.add_argument("--dest", default=None, help="output dir (default data/insat_raw)")
    ap.add_argument("--bbox", default=None,
                    help='"lon_min,lat_min,lon_max,lat_max"; pass "" for full disk')
    ap.add_argument("--name-filter", default=None, help="product substring guard")
    ap.add_argument("--max-per-day", type=int, default=None, help="cap scenes/day (0=all)")
    ap.add_argument("--workers", type=int, default=None, help="parallel downloads")
    ap.add_argument("--overwrite", action="store_true", help="re-download existing files")
    ap.add_argument("--dry-run", action="store_true", help="list scenes, download nothing")
    ap.add_argument("--username", default=None, help="MOSDAC user (else MOSDAC_USER env)")
    ap.add_argument("--password", default=None, help="MOSDAC pass (else MOSDAC_PASS env)")
    ap.add_argument("-v", "--verbose", action="store_true")
    return ap


def config_from_args(a: argparse.Namespace) -> DownloadConfig:
    """Build a DownloadConfig, letting non-None CLI flags override env/defaults."""
    cfg = DownloadConfig()
    if a.dataset_id is not None:  cfg.dataset_id = a.dataset_id
    if a.dest is not None:
        cfg.dest = a.dest
        cfg.manifest = None       # re-derive manifest path under the new dest
    if a.bbox is not None:        cfg.bbox = a.bbox or None   # "" -> full disk
    if a.name_filter is not None: cfg.name_filter = a.name_filter
    if a.max_per_day is not None: cfg.max_per_day = a.max_per_day
    if a.workers is not None:     cfg.workers = a.workers
    if a.username is not None:    cfg.username = a.username
    if a.password is not None:    cfg.password = a.password
    cfg.overwrite = a.overwrite
    cfg.__post_init__()           # re-resolve dest/manifest after overrides
    return cfg


def main(argv=None) -> int:
    a = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if a.verbose else logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s")
    cfg = config_from_args(a)
    logger = logging.getLogger("insat_download")
    logger.info(f"dataset={cfg.dataset_id}  bbox={cfg.bbox or 'full-disk'}  dest={cfg.dest}")
    try:
        summary = Downloader(cfg).download_range(a.start, a.end, dry_run=a.dry_run)
    except RuntimeError as e:
        logger.error(str(e))
        return 2
    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
