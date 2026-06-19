"""
downloader.py — Downloader: orchestrate a date-range INSAT-3DR L1C-SGP pull.

Responsibilities (the API client knows none of this):
  • walk a [start, end] date range day-by-day (MOSDAC search is date-windowed),
    retrying days whose search failed once the rest of the range is done,
  • filter entries by product substring (name_filter) + de-duplicate by identifier,
  • optional per-day cap,
  • resume (skip files already on disk),
  • a small download thread pool (only one product runs per process now, so
    bounded concurrency no longer floods MOSDAC the way unbounded per-product
    pools did; 429s are retried with backoff regardless),
  • append a JSONL manifest line per file (time, identifier, bytes, path).

Use via the package CLI (`python -m mosfetch`) or programmatically:
    Downloader(cfg).download_range("2024-07-01", "2024-07-31")
"""
from __future__ import annotations

import json
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta

from .client import MosdacClient, MosdacUnavailable
from .config import DownloadConfig

logger = logging.getLogger("mosfetch")


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
    def _search_day(self, ds: str, nxt: str, seen: set[str], scenes: list[dict]) -> bool:
        """Search one [ds, nxt) day, appending newly-seen matches to scenes.
        Returns True on success, False if the search itself failed."""
        try:
            entries = self.client.search_all(
                self.cfg.dataset_id, start=ds, end=nxt, bbox=self.cfg.bbox,
                page_size=self.cfg.search_count, timeout=self.cfg.timeout_search)
        except MosdacUnavailable as e:
            logger.warning(f"{ds}: search failed ({e})")
            return False
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
        return True

    def list_scenes(self, start: str, end: str) -> list[dict]:
        """Return the de-duplicated, product-filtered entries across [start, end].
        Pure search (no auth, no download) — handy for a dry run. Days whose
        search fails (e.g. transient MOSDAC 500s) get one retry pass after the
        rest of the range, once server load has likely dropped. If search fails
        for many days in a row, that's a persistent problem (e.g. a bad
        dataset_id), not transient load — abort the range instead of grinding
        through every remaining day."""
        seen: set[str] = set()
        scenes: list[dict] = []
        failed_days: list[tuple[str, str]] = []
        consecutive_fails = 0
        aborted = False
        for day in _daterange(start, end):
            ds = day.strftime("%Y-%m-%d")
            nxt = (day + timedelta(days=1)).strftime("%Y-%m-%d")
            if self._search_day(ds, nxt, seen, scenes):
                consecutive_fails = 0
            else:
                failed_days.append((ds, nxt))
                consecutive_fails += 1
                if consecutive_fails >= self.cfg.max_consecutive_search_failures:
                    logger.error(
                        f"{consecutive_fails} consecutive search failures (dataset_id="
                        f"'{self.cfg.dataset_id}') — likely a persistent problem (bad "
                        f"dataset_id?) rather than transient load; aborting remaining range")
                    aborted = True
                    break

        if failed_days and not aborted:
            logger.info(f"retrying {len(failed_days)} day(s) that failed search: "
                        f"{[d for d, _ in failed_days]}")
            time.sleep(10)
            still_failed = []
            for ds, nxt in failed_days:
                if not self._search_day(ds, nxt, seen, scenes):
                    still_failed.append(ds)
            if still_failed:
                logger.warning(f"giving up on {len(still_failed)} day(s) after retry: {still_failed}")
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
        on_disk = set(os.listdir(self.cfg.dest))
        to_fetch = []
        downloaded = skipped = failed = 0
        for e in scenes:
            ident = e.get("identifier", "")
            if not self.cfg.overwrite and ident in on_disk:
                skipped += 1
                logger.info(f"SKIP {ident}  (already on disk)")
            else:
                to_fetch.append(e)

        with open(self.cfg.manifest, "a", encoding="utf-8") as mf, \
             ThreadPoolExecutor(max_workers=self.cfg.workers) as ex:
            futs = {ex.submit(self._download_one, e): e for e in to_fetch}
            for fut in as_completed(futs):
                entry, path, err = fut.result()
                ident = entry.get("identifier", "")
                if err:
                    failed += 1
                    logger.error(f"FAIL {ident}: {err}")
                    continue
                existed = os.path.getsize(path) if os.path.exists(path) else 0
                downloaded += 1
                rec = {"time": entry.get("updated"), "identifier": ident,
                       "bytes": existed, "path": path}
                mf.write(json.dumps(rec) + "\n")
                mf.flush()
                logger.info(f"OK   {ident}  ({existed/1e6:.1f} MB)")
        summary = {"found": len(scenes), "downloaded": downloaded,
                   "skipped": skipped, "failed": failed}
        logger.info(f"done: {summary}")
        return summary
