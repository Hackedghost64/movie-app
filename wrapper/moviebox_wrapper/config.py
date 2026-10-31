"""Runtime settings.

App root resolution order:
  1. $MBX_HOME
  2. source checkout (config.yaml next to the package's parent)
  3. XDG state home ~/.local/share/mbx  (bootstrapped from packaged template)
"""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path
from typing import Any, Dict

import yaml

PACKAGE_ROOT = Path(__file__).resolve().parent.parent   # wrapper/ in a checkout


def _bootstrap_app_root(root: Path) -> Path:
    """First run of an installed copy: seed config + protocol from templates."""
    root.mkdir(parents=True, exist_ok=True)
    pkg = Path(__file__).resolve().parent
    if not (root / "protocol" / "protocol.yaml").exists():
        (root / "protocol").mkdir(parents=True, exist_ok=True)
        src = pkg / "protocol_default.yaml"
        if src.exists():
            shutil.copy(src, root / "protocol" / "protocol.yaml")
    if not (root / "config.yaml").exists():
        (root / "config.yaml").write_text(
            (pkg / "config_default.yaml").read_text(encoding="utf-8")
            if (pkg / "config_default.yaml").exists() else DEFAULT_CONFIG_TEXT,
            encoding="utf-8")
    return root


def _app_root() -> Path:
    env = os.environ.get("MBX_HOME")
    if env:
        return _bootstrap_app_root(Path(env).expanduser().resolve())
    if (PACKAGE_ROOT / "config.yaml").exists():
        return PACKAGE_ROOT                       # source checkout
    base = os.environ.get("XDG_STATE_HOME") or str(
        Path.home() / ".local" / "share")
    return _bootstrap_app_root(Path(base) / "mbx")


DEFAULT_CONFIG_TEXT = """server:
  host: 127.0.0.1
  port: 8399

mode: links            # links | proxy  (per-request override: ?mode=proxy)
region: US

cache_ttl:
  metadata: 3600
  search: 600
  stream: 120          # stream URLs are time-limited upstream; keep short

rate_limit_per_minute: 60
upstream_timeout_seconds: 15
log_raw_traffic: true   # every signed request+response -> logs/upstream.log (diff-debugging gold)

selfheal:
  auto_scan_on_start: true
  auth_fail_threshold: 3     # consecutive signature rejections before PROTOCOL_STALE
  verify_probe_on_heal: true # test candidate secrets live BEFORE committing them
  offline: false             # true = never touch network during heal/doctor

media_allow_host_suffixes: [aoneroom.com, aliyuncs.com, akamaized.net]
"""

DEFAULTS: Dict[str, Any] = {
    "server": {"host": "127.0.0.1", "port": 8399},
    "mode": "links",                      # links | proxy
    "region": "US",
    "paths": {
        "protocol_file": "protocol/protocol.yaml",
        "watch_dir": "watch",
        "device_file": "data/device.json",
        "logs_dir": "logs",
        "backups_dir": "protocol/backups",
        "downloads_dir": "downloads",
    },
    "cache_ttl": {"metadata": 3600, "search": 600, "stream": 120},
    "rate_limit_per_minute": 60,
    "upstream_timeout_seconds": 15,
    "log_raw_traffic": True,
    "selfheal": {
        "auto_scan_on_start": True,
        "auth_fail_threshold": 3,
        "verify_probe_on_heal": True,
        "offline": False,
    },
}


def _deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(base)
    for k, v in override.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


class Settings:
    def __init__(self) -> None:
        self.app_root = _app_root()
        self.config_path = self.app_root / "config.yaml"
        data: Dict[str, Any] = {}
        if self.config_path.exists():
            with open(self.config_path, "r", encoding="utf-8") as fh:
                data = yaml.safe_load(fh) or {}
        merged = _deep_merge(DEFAULTS, data)
        for env_key, env_val in os.environ.items():
            if env_key.startswith("MBW_"):
                path = [x for x in env_key[4:].lower().split("__") if x]
                node = merged
                for p in path[:-1]:
                    node = node.setdefault(p, {})
                node[path[-1]] = env_val
        self._d = merged

    def p(self, rel: str) -> Path:
        return (self.app_root / self._d["paths"][rel]).resolve()

    @property
    def protocol_file(self) -> Path:
        return self.p("protocol_file")

    @property
    def watch_dir(self) -> Path:
        return self.p("watch_dir")

    @property
    def device_file(self) -> Path:
        return self.p("device_file")

    @property
    def backups_dir(self) -> Path:
        return self.p("backups_dir")

    @property
    def logs_dir(self) -> Path:
        return self.p("logs_dir")

    def get(self, dotted: str, default: Any = None) -> Any:
        node: Any = self._d
        for part in dotted.split("."):
            if not isinstance(node, dict) or part not in node:
                return default
            node = node[part]
        return node


_settings: Settings | None = None


def settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings
