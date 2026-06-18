"""
downloader.py — Downloader: orchestrate a date-range INSAT-3DR L1C-SGP pull.

Responsibilities (the API client knows none of this):
  • walk a [start, end] date range day-by-day (MOSDAC search is date-windowed),
  • filter entries by product substring (name_filter) + de-duplicate by identifier,
  • optional per-day cap,
  • resume (skip files already on disk),
  • parallel downloads (thread pool),
  • append a JSONL manifest line per file (time, identifier, bytes, path).

Use via the package CLI (`python -m insat_download`) or programmatically:
    Downloader(cfg).download_range("2024-07-01", "2024-07-31")
"""
from __future__ import annotations

import json
import logging
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta

from .client import MosdacClient, MosdacUnavailable
from .config import DownloadConfig

logger = logging.getLogger("insat_download")


def _daterange(start: str, end: str):
    d0 = datetime.strptime(start, "%Y-%m-%d")
    d1 = datetime.strptime(end, "%Y-%m-%d")
    d = d0
    while d <= d1:
        yield d
        d += timedelta(days=1)


class Downloader:
    def __init__(self, cfg: DownloadConfig, client: MosdacClient | None = None):
        self.cfg = cfg
        self.client = client or MosdacClient(cfg.username, cfg.password)

    # ── discovery ─────────────────────────────────────────────────────────────
    def list_scenes(self, start: str, end: str) -> list[dict]:
        """Return the de-duplicated, product-filtered entries across [start, end].
        Pure search (no auth, no download) — handy for a dry run."""
        seen: set[str] = set()
        scenes: list[dict] = []
        for day in _daterange(start, end):
            ds = day.strftime("%Y-%m-%d")
            nxt = (day + timedelta(days=1)).strftime("%Y-%m-%d")
            try:
                entries = self.client.search_all(
                    self.cfg.dataset_id, start=ds, end=nxt, bbox=self.cfg.bbox,
                    page_size=self.cfg.search_count, timeout=self.cfg.timeout_search)
            except MosdacUnavailable as e:
                logger.warning(f"{ds}: search failed ({e}); skipping day")
                continue
            kept = 0
            for e in entries:
                ident = e.get("identifier", "")
                if self.cfg.name_filter and self.cfg.name_filter not in ident:
                    continue
                if ident in seen:
                    continue
                seen.add(ident)
                scenes.append(e)
                kept += 1
                if self.cfg.max_per_day and kept >= self.cfg.max_per_day:
                    break
            logger.info(f"{ds}: {kept} scene(s) matched (total so far {len(scenes)})")
        return scenes

    # ── download ──────────────────────────────────────────────────────────────
    def _download_one(self, entry: dict) -> tuple[dict, str | None, str | None]:
        ident = entry.get("identifier", "")
        try:
            path = self.client.download(
                entry["id"], ident, self.cfg.dest,
                overwrite=self.cfg.overwrite, timeout=self.cfg.timeout_download)
            return entry, path, None
        except Exception as e:        # one bad file shouldn't kill the batch
            return entry, None, str(e)

    def download_range(self, start: str, end: str, dry_run: bool = False) -> dict:
        """Search [start, end] then download everything matched. Returns a summary
        dict {found, downloaded, skipped, failed}."""
        self.cfg.require_credentials() if not dry_run else None
        scenes = self.list_scenes(start, end)
        logger.info(f"discovered {len(scenes)} scene(s) in [{start} .. {end}]")
        if dry_run:
            for e in scenes:
                logger.info(f"  would download: {e.get('identifier')}")
            return {"found": len(scenes), "downloaded": 0, "skipped": 0, "failed": 0}

        os.makedirs(self.cfg.dest, exist_ok=True)
        downloaded = skipped = failed = 0
        with open(self.cfg.manifest, "a", encoding="utf-8") as mf, \
             ThreadPoolExecutor(max_workers=self.cfg.workers) as ex:
            futs = {ex.submit(self._download_one, e): e for e in scenes}
            for fut in as_completed(futs):
                entry, path, err = fut.result()
                ident = entry.get("identifier", "")
                if err:
                    failed += 1
                    logger.error(f"FAIL {ident}: {err}")
                    continue
                existed = os.path.getsize(path) if os.path.exists(path) else 0
                # heuristic: was it freshly written this run? we can't tell cheaply,
                # so count any successful return as downloaded-or-present.
                downloaded += 1
                rec = {"time": entry.get("updated"), "identifier": ident,
                       "bytes": existed, "path": path}
                mf.write(json.dumps(rec) + "\n")
                logger.info(f"OK   {ident}  ({existed/1e6:.1f} MB)")
        summary = {"found": len(scenes), "downloaded": downloaded,
                   "skipped": skipped, "failed": failed}
        logger.info(f"done: {summary}")
        return summary
