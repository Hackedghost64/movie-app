"""Auth-failure and upstream trap detector.

Tracks:
1. Consecutive signature/auth rejections from upstream.
2. Decoy update traps intercepted.
3. Upstream mandatory update notices.
"""
from __future__ import annotations

import threading
import time
from typing import Callable, Optional


class StalenessDetector:
    def __init__(self, threshold: int = 3):
        self.threshold = max(1, int(threshold))
        self._lock = threading.Lock()
        self._streak = 0
        self._stale_since: Optional[float] = None
        self._last_reason = ""
        self._decoys_intercepted = 0
        self._last_decoy_time: Optional[float] = None
        self._upstream_update_info: dict = {}

    def on_auth_failure(self, reason: str) -> None:
        with self._lock:
            self._last_reason = reason
            self._streak += 1
            if self._streak >= self.threshold and self._stale_since is None:
                self._stale_since = time.time()

    def on_success(self) -> None:
        with self._lock:
            self._streak = 0
            self._stale_since = None

    def on_decoy_bypassed(self) -> None:
        with self._lock:
            self._decoys_intercepted += 1
            self._last_decoy_time = time.time()

    def on_upstream_update_notice(self, info: dict) -> None:
        with self._lock:
            self._upstream_update_info = dict(info)

    def reset(self) -> None:
        with self._lock:
            self._streak = 0
            self._stale_since = None
            self._last_reason = ""

    def status(self) -> dict:
        with self._lock:
            stale = self._stale_since is not None
            force_update = self._upstream_update_info.get("forceUpdate", False)
            if stale:
                state = "PROTOCOL_STALE"
            elif force_update:
                state = "UPSTREAM_UPDATE_AVAILABLE"
            else:
                state = "HEALTHY"

            remediation = ""
            if stale:
                remediation = (
                    "Upstream rejected our signatures repeatedly. The app likely rotated "
                    "its secrets. Download the latest MovieBox APK and drop it into the "
                    "wrapper 'watch/' folder, then POST /heal (or restart). "
                    "Run GET /doctor?live=1 to diagnose."
                )
            elif force_update:
                remediation = (
                    f"Upstream flagged mandatory update to version "
                    f"{self._upstream_update_info.get('noticeConfig', {}).get('updateVersionName', 'newer')}. "
                    f"Trigger POST /heal to auto-download and sync, or place the APK in watch/."
                )

            return {
                "state": state,
                "consecutive_auth_failures": self._streak,
                "threshold": self.threshold,
                "last_reason": self._last_reason,
                "stale_since": time.strftime(
                    "%Y-%m-%dT%H:%M:%S%z", time.localtime(self._stale_since)) if stale else None,
                "decoys_intercepted": self._decoys_intercepted,
                "last_decoy_intercepted_at": time.strftime(
                    "%Y-%m-%dT%H:%M:%S%z", time.localtime(self._last_decoy_time)) if self._last_decoy_time else None,
                "upstream_update_notice": self._upstream_update_info if self._upstream_update_info else None,
                "remediation": remediation,
            }


def make_callbacks(detector: StalenessDetector) -> tuple[Callable[[str], None], Callable[[], None]]:
    return detector.on_auth_failure, detector.on_success
