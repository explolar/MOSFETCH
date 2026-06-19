"""
client.py — MosdacClient: thin REST client for the MOSDAC download API.

Endpoints are the official ones (cf. MOSDAC mdapi.py). Search is public; token +
download need credentials. Transient 5xx / connection errors are retried with
backoff. This layer knows nothing about INSAT products or date ranges — it just
does search / get_token / download. Orchestration lives in downloader.py.

Adapted from the project's proven NIRA/server/vendor/mosdac_io.py.
"""
from __future__ import annotations

import os
import time

import requests

TOKEN_URL = "https://mosdac.gov.in/download_api/gettoken"
SEARCH_URL = "https://mosdac.gov.in/apios/datasets.json"
DOWNLOAD_URL = "https://mosdac.gov.in/download_api/download"

_RETRY_STATUS = {429, 500, 502, 503, 504}
_TOKEN_TTL = 3000   # ~50 min; MOSDAC tokens last ~1 h


class MosdacUnavailable(RuntimeError):
    """MOSDAC transiently down (5xx / timeout) after retries."""


class MosdacClient:
    """Stateful client: caches the access token across calls."""

    def __init__(self, username: str | None = None, password: str | None = None,
                 attempts: int = 5):
        self.username = username
        self.password = password
        self.attempts = attempts
        self._token: str | None = None
        self._token_expiry: float = 0.0

    # ── low-level request with retry/backoff ──────────────────────────────────
    def _request(self, method: str, url: str, **kw) -> requests.Response:
        last = None
        for i in range(self.attempts):
            try:
                r = requests.request(method, url, **kw)
            except (requests.ConnectionError, requests.Timeout) as e:
                last = e
                time.sleep(2.0 * (i + 1))
                continue
            if r.status_code in _RETRY_STATUS:
                last = MosdacUnavailable(f"MOSDAC {r.status_code} ({r.reason}) for {url}")
                retry_after = r.headers.get("Retry-After")
                wait = float(retry_after) if retry_after and retry_after.isdigit() else 2.0 * (i + 1)
                time.sleep(wait)
                continue
            r.raise_for_status()
            return r
        if isinstance(last, (requests.ConnectionError, requests.Timeout)):
            raise MosdacUnavailable(f"MOSDAC unreachable ({type(last).__name__}) for {url}") from last
        raise last

    # ── public search (no auth) ───────────────────────────────────────────────
    def search(self, dataset_id: str, *, start: str | None = None, end: str | None = None,
               bbox: str | None = None, count: int | str | None = None,
               start_index: int = 1, timeout: int = 30) -> dict:
        """One search page. start/end are 'YYYY-MM-DD'. Returns the JSON dict
        with keys totalResults, itemsPerPage, entries[]."""
        params = {"datasetId": dataset_id, "startIndex": start_index}
        for k, v in (("startTime", start), ("endTime", end),
                     ("boundingBox", bbox), ("count", count)):
            if v:
                params[k] = v
        return self._request("GET", SEARCH_URL, params=params, timeout=timeout).json()

    def search_all(self, dataset_id: str, *, start=None, end=None, bbox=None,
                   page_size: int = 100, timeout: int = 30, max_pages: int = 50) -> list[dict]:
        """Page through search results, returning the full entries list."""
        out, idx = [], 1
        for _ in range(max_pages):
            res = self.search(dataset_id, start=start, end=end, bbox=bbox,
                              count=page_size, start_index=idx, timeout=timeout)
            entries = res.get("entries") or []
            out.extend(entries)
            total = int(res.get("totalResults", 0) or 0)
            idx += len(entries)
            if not entries or idx > total:
                break
        return out

    # ── auth ──────────────────────────────────────────────────────────────────
    def get_token(self, *, force: bool = False, timeout: int = 90) -> str:
        if self._token and not force and self._token_expiry > time.time():
            return self._token
        if not self.username or not self.password:
            raise RuntimeError("credentials required for token (set username/password)")
        r = self._request("POST", TOKEN_URL,
                          json={"username": self.username, "password": self.password},
                          timeout=timeout)
        acc = r.json().get("access_token")
        if not acc:
            raise RuntimeError("MOSDAC authentication failed — check username/password")
        self._token = acc
        self._token_expiry = time.time() + _TOKEN_TTL
        return acc

    # ── download ──────────────────────────────────────────────────────────────
    def download(self, record_id: str, identifier: str, dest_dir: str, *,
                 overwrite: bool = False, timeout: int = 240) -> str:
        """Download one record to dest_dir/identifier (atomic via .part).
        Returns the local path; skips if present and not overwrite."""
        os.makedirs(dest_dir, exist_ok=True)
        out = os.path.join(dest_dir, identifier)
        if os.path.exists(out) and not overwrite:
            return out
        token = self.get_token()
        try:
            r = self._request("GET", DOWNLOAD_URL,
                              headers={"Authorization": f"Bearer {token}"},
                              params={"id": record_id}, stream=True, timeout=timeout)
        except requests.HTTPError as e:
            if e.response is not None and e.response.status_code == 401:
                # cached token expired server-side sooner than our local TTL guess;
                # force a fresh one and retry once.
                token = self.get_token(force=True)
                r = self._request("GET", DOWNLOAD_URL,
                                  headers={"Authorization": f"Bearer {token}"},
                                  params={"id": record_id}, stream=True, timeout=timeout)
            else:
                raise
        tmp = out + ".part"
        with open(tmp, "wb") as f:
            for chunk in r.iter_content(chunk_size=1 << 20):
                if chunk:
                    f.write(chunk)
        os.replace(tmp, out)
        return out
