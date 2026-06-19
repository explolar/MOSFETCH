"""
config.py — DownloadConfig: every knob for the INSAT-3DR downloader in one place.

Resolution order (later wins): dataclass defaults  <  environment variables  <
explicit constructor args / CLI flags. Credentials NEVER hard-coded — they come
from MOSDAC_USER / MOSDAC_PASS in the environment.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


def _env(name: str, default: str | None = None) -> str | None:
    v = os.environ.get(name)
    return v if v not in (None, "") else default


@dataclass
class DownloadConfig:
    """All settings for one download session.

    Parameters
    ----------
    dataset_id : str
        MOSDAC catalog datasetId for the product. For the 9-channel training
        data this is the INSAT-3DR Imager L1C-SGP collection. Set it via
        --dataset-id or the MOSDAC_DATASET_ID env var (the exact catalog string
        is account/catalog-specific; copy it from the MOSDAC "Open Data" page).
    dest : str | Path
        Output directory for downloaded .h5 files.
    bbox : str | None
        "lon_min,lat_min,lon_max,lat_max" passed to MOSDAC boundingBox search.
        None = full disk. Central-India default covers the DWR domain.
    username, password : str | None
        MOSDAC credentials. Default to MOSDAC_USER / MOSDAC_PASS env vars.
    name_filter : str
        Substring an entry identifier must contain to be kept (product guard so
        a broad datasetId doesn't pull the wrong sub-product).
    max_per_day : int
        Cap scenes downloaded per calendar day (0 = no cap). INSAT images every
        ~30 min → up to 48/day; cap to thin the set if you only need a few.
    overwrite : bool
        Re-download even if the file already exists (default False = resume).
    workers : int
        Parallel download threads. Kept modest by default since the 429 retry
        in client.py absorbs occasional rate-limit hits; raise cautiously.
    max_consecutive_search_failures : int
        Abort the date range if this many days in a row fail search — a sign
        of a persistent problem (e.g. bad dataset_id) rather than transient load.
    search_count : int
        Page size for the MOSDAC search call.
    timeout_search, timeout_token, timeout_download : int
        Per-request timeouts (seconds).
    manifest : str | None
        Path to a JSONL manifest appended to as files land (None = <dest>/manifest.jsonl).
    """
    dataset_id: str = field(default_factory=lambda: _env("MOSDAC_DATASET_ID", "3RIMG_L1C_SGP"))
    dest: str = "data/insat_raw"
    bbox: str | None = field(default_factory=lambda: _env("INSAT_BBOX", "74,16,84,26"))
    username: str | None = field(default_factory=lambda: _env("MOSDAC_USER"))
    password: str | None = field(default_factory=lambda: _env("MOSDAC_PASS"))
    name_filter: str = "L1C_SGP"
    max_per_day: int = 0
    overwrite: bool = False
    workers: int = 3
    max_consecutive_search_failures: int = 5
    search_count: int = 100
    timeout_search: int = 30
    timeout_token: int = 90
    timeout_download: int = 240
    manifest: str | None = None

    def __post_init__(self):
        self.dest = str(Path(self.dest))
        if self.manifest is None:
            self.manifest = str(Path(self.dest) / "manifest.jsonl")

    def require_credentials(self) -> None:
        """Raise a clear error if credentials are missing (search is public, but
        download needs them)."""
        if not self.username or not self.password:
            raise RuntimeError(
                "MOSDAC credentials missing. Set MOSDAC_USER and MOSDAC_PASS "
                "environment variables (or pass username=/password=)."
            )
