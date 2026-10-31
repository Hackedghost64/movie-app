# MBX · private streaming gateway

One command, one API key, full search → stream → download pipeline.

```bash
pip install -e .
mbx setup
```

`mbx setup` checks your environment (players, ffmpeg), starts the gateway as a
background daemon, provisions your device identity and first API key, and
prints ready-to-paste examples.

## Daily use

| Command | What it does |
|---|---|
| `mbx tui` | interactive app: browse, pick episodes, play/download, manage server & keys |
| `mbx play "breaking bad" 5x1` | search + launch best player (mpv › vlc › ffplay) |
| `mbx dl "peaky blinders" 6x1` | download episode (direct MP4, or ffmpeg DASH/HLS remux) |
| `mbx up` / `down` / `status` | gateway lifecycle |
| `mbx mode links\|proxy` | toggle media delivery (links = direct URLs; proxy = byte-relay) |
| `mbx secure on\|off\|auto` | toggle API-key enforcement |
| `mbx key create/list/revoke` | manage client keys |
| `mbx doctor [--live]` | layered diagnostics |
| `mbx heal` | refresh provisioning facts from a new app bundle in `watch/` |

## The API

Every route speaks JSON with an `X-API-Key` header once keys exist.

```
GET  /health                      liveness (no auth)
GET  /search?q=&page=&per_page=   search titles
GET  /search/suggest?q=           autocomplete
GET  /search/rank                 trending catalog
GET  /titles/{id}                 metadata
GET  /titles/{id}/seasons         season index
GET  /titles/{id}/episodes        episode list window
GET  /titles/{id}/stream?season=&episode=    playable manifests (HLS/DASH)
GET  /titles/{id}/download?season=&episode=  direct files + metadata
GET  /titles/{id}/subtitles       caption tracks
GET  /discover/tabs               home feeds
POST /heal                        provisioning refresh
GET  /doctor?live=1               diagnostics JSON
```

Stream entries include CDN cookies when required — pass them as `Cookie:`
headers (mpv/ffmpeg do this automatically via `mbx play/dl`).

## Configuration

Everything lives in `config.yaml`:

- `mode:` links | proxy (per-request override `?mode=`)
- `security.require_api_key:` on/off/auto
- `rate_limit_per_minute`, cache TTLs, timeouts
- `paths.downloads_dir`

Runtime state (`data/`) holds the device identity, session token, CLI key and
pidfile. Raw request/response logging for debugging: `log_raw_traffic`.

## Self-maintenance

The gateway monitors upstream acceptance. If signatures stop being accepted it
flips to `PROTOCOL_STALE`, annotates error responses with remediation hints,
and can re-provision from a fresh app bundle dropped into `watch/`
(`mbx heal`). See [docs/PROVISIONING.md](docs/PROVISIONING.md).

Protocol-level technical reference: [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Layout

```
moviebox_wrapper/     gateway code (FastAPI)
protocol/             provisioning facts (single source of truth) + backups/
watch/                drop new app bundles here for self-provisioning
data/                 identity, sessions, keys, pidfile
docs/                 technical references
tests/                test suite (pytest)
```
