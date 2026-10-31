"""Wrapper self-security: API keys + rate limiting.

API keys live hashed in data/api_keys.json. Enforcement policy:
  require_api_key: true   -> always enforce
                    false -> never
                    auto  -> enforce iff at least one key exists (default)

Health endpoint stays open so supervisors can probe liveness.
"""
from __future__ import annotations

import hashlib
import json
import secrets
import threading
import time
from pathlib import Path
from typing import List, Optional

from fastapi import HTTPException, Request


class ApiKeyStore:
    FILE = "api_keys.json"

    def __init__(self, directory: Path):
        self.path = directory / self.FILE
        self._lock = threading.Lock()

    def _load(self) -> List[dict]:
        if not self.path.exists():
            return []
        try:
            return json.loads(self.path.read_text(encoding="utf-8"))
        except Exception:
            return []

    def _save(self, keys: List[dict]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(keys, indent=2), encoding="utf-8")
        tmp.replace(self.path)

    @staticmethod
    def _hash(raw: str) -> str:
        return hashlib.sha256(raw.encode()).hexdigest()

    def create(self, name: str) -> dict:
        raw = "mbx_" + secrets.token_urlsafe(24)
        prefix = raw[:10]
        rec = {"name": name, "prefix": prefix, "sha256": self._hash(raw),
               "created": int(time.time())}
        with self._lock:
            keys = self._load()
            keys.append(rec)
            self._save(keys)
        return {"record": rec, "plaintext": raw}

    def list(self) -> List[dict]:
        return [{k: v for k, v in k_.items() if k != "sha256"}
                for k_ in self._load()]

    def revoke(self, prefix: str) -> bool:
        with self._lock:
            keys = self._load()
            kept = [k for k in keys if k["prefix"] != prefix]
            if len(kept) == len(keys):
                return False
            self._save(kept)
            return True

    def verify(self, raw: str) -> bool:
        h = self._hash(raw)
        return any(k["sha256"] == h for k in self._load())

    @property
    def count(self) -> int:
        return len(self._load())


class SlidingWindowRateLimiter:
    """Per-client-IP minute window; honors config rate_limit_per_minute."""

    def __init__(self, per_minute: int):
        self.per_minute = max(0, per_minute)
        self._hits: dict[str, list[float]] = {}
        self._lock = threading.Lock()

    def check(self, client_ip: str) -> bool:
        """True = allowed. False = over limit."""
        if self.per_minute <= 0:
            return True
        now = time.time()
        window_start = now - 60.0
        with self._lock:
            hits = [t for t in self._hits.get(client_ip, []) if t > window_start]
            if len(hits) >= self.per_minute:
                self._hits[client_ip] = hits
                return False
            hits.append(now)
            self._hits[client_ip] = hits
            if len(self._hits) > 4096:          # prune stale clients
                cutoff = now - 120
                for ip in [ip for ip, ts in self._hits.items()
                           if not ts or ts[-1] < cutoff]:
                    del self._hits[ip]
            return True


def extract_api_key(request: Request) -> Optional[str]:
    key = request.headers.get("x-api-key")
    if key:
        return key
    return request.query_params.get("api_key")


def make_auth_dependency(store: ApiKeyStore, mode: str):
    """mode: true | false | 'auto'"""
    def guard(request: Request) -> None:
        enforce = True if mode is True else False if mode is False \
            else store.count > 0
        if not enforce:
            return
        if request.url.path == "/health":
            return
        raw = extract_api_key(request)
        if not raw or not store.verify(raw):
            raise HTTPException(
                status_code=401,
                detail="invalid or missing X-API-Key (create one: mbx key create <name>)",
                headers={"WWW-Authenticate": "ApiKey"})
    return guard
