"""Response normalizers.

Upstream BFF response schemas are not fully known without live captures, so
normalizers are deliberately defensive:

- best-effort field mapping for common shapes
- a generic recursive URL harvester for stream/download discovery that works
  even if the JSON shape drifts between app versions
- `debug_raw=true` on any route returns the untouched upstream payload

When you capture real responses (see logs/upstream.log), tighten these
mappings and add golden fixtures under tests/fixtures/.
"""
from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Tuple

VIDEOISH = re.compile(r"\.(mp4|m3u8|mpd|ts)(\?|$)", re.IGNORECASE)
URL_KEYS = re.compile(r"url|uri|link|src", re.IGNORECASE)

_ID_KEYS = ["id", "subjectId", "subject_id", "sid"]
_TITLE_KEYS = ["title", "name", "subjectName", "subject_name"]
_POSTER_KEYS = ["cover", "poster", "imageUrl", "verticalUrl", "image", "coverUrl", "thumbnail"]
_YEAR_KEYS = ["year", "releaseYear", "release_year", "releaseDate", "release_date"]
_RATING_KEYS = ["score", "rating", "doubanScore", "imdbScore", "imdbRatingValue"]
_TYPE_KEYS = ["subjectType", "subject_type", "type"]
_DESC_KEYS = ["description", "introduce", "synopsis", "desc"]


def _first(d: Dict[str, Any], keys: Iterable[str], default=None):
    for k in keys:
        v = d.get(k)
        if v not in (None, ""):
            return v
    return default


def normalize_title_item(item: Dict[str, Any]) -> Dict[str, Any]:
    if not isinstance(item, dict):
        return {"value": item}
    poster_raw = _first(item, _POSTER_KEYS)
    if isinstance(poster_raw, dict):
        poster = poster_raw.get("url") or poster_raw.get("imageUrl") or str(poster_raw)
    else:
        poster = poster_raw

    year_raw = _first(item, _YEAR_KEYS)
    year = str(year_raw)[:4] if year_raw else None

    rating_raw = _first(item, _RATING_KEYS)
    rating = str(rating_raw) if rating_raw is not None else None

    out = {
        "id": str(_first(item, _ID_KEYS, "")),
        "title": _first(item, _TITLE_KEYS),
        "poster": poster,
        "year": year,
        "rating": rating,
        "type": _first(item, _TYPE_KEYS),
        "description": _first(item, _DESC_KEYS),
    }
    extras = {k: v for k, v in item.items()
              if k not in set(_ID_KEYS + _TITLE_KEYS + _POSTER_KEYS + _DESC_KEYS)}
    if extras:
        out["extra"] = extras
    return out


def find_lists(data: Any) -> List[List[Dict[str, Any]]]:
    """Recursively find lists-of-dicts that look like result collections."""
    found: List[List[Dict[str, Any]]] = []

    def walk(node: Any) -> None:
        if isinstance(node, list):
            dicts = [x for x in node if isinstance(x, dict)]
            if dicts and len(dicts) >= max(1, len(node) // 2):
                found.append(dicts)
            for x in node[:50]:
                walk(x)
        elif isinstance(node, dict):
            for v in node.values():
                walk(v)

    walk(data)
    return found


def normalize_search(payload: Any) -> Dict[str, Any]:
    items: List[Dict[str, Any]] = []
    seen_ids = set()

    # If top-level contains 'data', unwrap
    data_node = payload.get("data") if isinstance(payload, dict) else payload
    if isinstance(data_node, dict) and "items" in data_node and isinstance(data_node["items"], list):
        for section in data_node["items"]:
            if isinstance(section, dict) and "subjects" in section and isinstance(section["subjects"], list):
                for subj in section["subjects"]:
                    norm = normalize_title_item(subj)
                    sid = norm.get("id")
                    if sid and sid not in seen_ids:
                        seen_ids.add(sid)
                        items.append(norm)

    if not items:
        lists = find_lists(payload)
        for lst in lists:
            scored = [normalize_title_item(i) for i in lst]
            if scored and (scored[0].get("title") or scored[0].get("id")):
                items = scored
                break

    total = None
    if isinstance(payload, dict):
        for k in ("total", "totalCount", "count"):
            if isinstance(payload.get(k), int):
                total = payload[k]
                break
    return {"results": items, "count": len(items), "total": total}


def harvest_urls(node: Any, parent_key: str = "",
                 require_media_ext: bool = False) -> List[Dict[str, str]]:
    """Walk arbitrary JSON and pull out URL-ish strings with their key paths."""
    hits: List[Dict[str, str]] = []

    def walk(n: Any, path: str) -> None:
        if isinstance(n, dict):
            for k, v in n.items():
                walk(v, f"{path}.{k}" if path else k)
        elif isinstance(n, list):
            for i, v in enumerate(n[:200]):
                walk(v, f"{path}[{i}]")
        elif isinstance(n, str) and n.startswith(("http://", "https://")):
            key_hit = bool(URL_KEYS.search(path.rsplit(".", 1)[-1]))
            media_hit = bool(VIDEOISH.search(n))
            if require_media_ext and not media_hit:
                return
            if key_hit or media_hit:
                hits.append({"key_path": path, "url": n})

    walk(node, parent_key)
    seen, out = set(), []
    for h in hits:
        if h["url"] not in seen:
            seen.add(h["url"])
            out.append(h)
    return out


def guess_resolution(url: str, context: Dict[str, Any]) -> str:
    blob = url.lower() + json_blob(context)
    for tag in ("1080", "720", "480", "360", "240"):
        if tag in blob:
            return f"{tag}p"
    m = re.search(r"(\d{3,4})p", blob)
    return f"{m.group(1)}p" if m else "unknown"


def json_blob(o: Any) -> str:
    import json as _j
    try:
        return _j.dumps(o).lower()
    except Exception:
        return ""


DECOY_URL_PATTERNS = (
    "b164fbfb4347792950bdfbfb563d39d9",
    "80da52722ee7de7a4303290af6783424",
    "/other/",
    "macdn.aoneroom.com/other/",
)

DECOY_REGEX = re.compile(r"/other/(\d{4}/\d{2}/\d{2}/|.*\.mp4)", re.IGNORECASE)


def is_decoy_url(url: str | None) -> bool:
    """Detect upstream honeypot / decoy update announcement video URLs."""
    if not url:
        return False
    u = str(url).lower()
    return any(pat in u for pat in DECOY_URL_PATTERNS) or bool(DECOY_REGEX.search(u))


_RESOURCE_REGEX = re.compile(r'"Resource"\s*:\s*"([^"]+)"')


def extract_stream_from_cookie(sign_cookie: str | None) -> Tuple[Optional[str], Optional[str]]:
    """Extract true CDN media URL and format kind ('hls'|'dash') from signed cookies.

    Handles both:
    1. AWS CloudFront signed cookies: CloudFront-Policy=<base64 JSON statement>
    2. Edge Cache signed cookies: Edge-Cache-Cookie=...urlprefix=<base64 url prefix>...
    """
    if not sign_cookie:
        return None, None

    import base64

    def _decode_b64(b64_str: str) -> str:
        s = b64_str.strip().replace("-", "+").replace("~", "/").replace("_", "/")
        s += "=" * (-len(s) % 4)
        return base64.b64decode(s).decode("utf-8", "ignore")

    for part in sign_cookie.split(";"):
        part = part.strip()
        # 1. CloudFront Signed Cookies
        if part.startswith("CloudFront-Policy="):
            b64 = part.split("=", 1)[1]
            try:
                raw = _decode_b64(b64)
                m = _RESOURCE_REGEX.search(raw)
                if m:
                    res_url = m.group(1)
                    base_url = res_url.rstrip("*")
                    if "/hls/" in base_url:
                        return (base_url if base_url.endswith(".m3u8") else base_url + "local.m3u8"), "hls"
                    elif "/dash/" in base_url:
                        return (base_url if base_url.endswith(".mpd") else base_url + "index_web.mpd"), "dash"
                    return base_url, None
            except Exception:
                pass

        # 2. Edge Cache Cookies (urlprefix=<base64 url prefix>)
        if "Edge-Cache-Cookie" in part or "urlprefix=" in part:
            subparts = part.split(":") if ":" in part else [part]
            for sub in subparts:
                sub = sub.strip()
                if "urlprefix=" in sub:
                    b64 = sub.split("urlprefix=", 1)[1]
                    try:
                        prefix = _decode_b64(b64).strip()
                        if prefix.startswith(("http://", "https://")):
                            if "/hls/" in prefix:
                                return (prefix if prefix.endswith(".m3u8") else prefix.rstrip("/") + "/local.m3u8"), "hls"
                            elif "/dash/" in prefix:
                                return (prefix if prefix.endswith(".mpd") else prefix.rstrip("/") + "/index_web.mpd"), "dash"
                            return prefix, None
                    except Exception:
                        pass

    return None, None


def _clean_cookie(raw) -> str | None:
    """signCookie arrives as 'K1=V1;K2=V2;K3=V3;' (trailing ';')."""
    if not raw:
        return None
    parts = [p.strip() for p in str(raw).split(";") if p.strip()]
    return "; ".join(parts) if parts else None


def normalize_streams(play_payload: Any) -> List[Dict[str, Any]]:
    """Map upstream play-info `streams[]` (verified schema):
    {format: HLS|DASH, url, resolutions: "1080,720,480", size, duration, ...}.
    Automatically recovers genuine media URLs when upstream serves an update decoy.
    Falls back to generic harvester if the schema drifts."""
    out: List[Dict[str, Any]] = []
    seen = set()
    payload = play_payload.get("data") if (isinstance(play_payload, dict) and "data" in play_payload and isinstance(play_payload["data"], dict)) else play_payload
    raw_streams = payload.get("streams") if isinstance(payload, dict) else None
    for s in raw_streams or []:
        raw_url = s.get("url")
        cookie = _clean_cookie(s.get("signCookie"))
        real_url, deduced_kind = extract_stream_from_cookie(cookie)

        # Bypass upstream update trap: if raw_url is decoy or missing, use real_url from cookie
        is_decoy = is_decoy_url(raw_url)
        bypassed = False
        if real_url and (is_decoy or not raw_url):
            url = real_url
            kind = deduced_kind or "hls"
            bypassed = True
        elif is_decoy:
            url = raw_url
            kind = "mp4"
            bypassed = False
        else:
            url = raw_url
            fmt = str(s.get("format") or "").upper()
            kind = "dash" if fmt == "DASH" else ("hls" if fmt == "HLS" else (deduced_kind or fmt.lower()))
            bypassed = False

        if not url or url in seen:
            continue
        # Never output an active, unbypassed decoy update video as a playable stream
        if is_decoy and not bypassed:
            continue

        seen.add(url)

        res_list = [r.strip() for r in str(s.get("resolutions") or "").split(",")
                    if r.strip().isdigit()]
        try:
            size_mb = round(int(s.get("size") or 0) / 1e6, 1)
        except (TypeError, ValueError):
            size_mb = None
        out.append({
            "url": url,
            "kind": kind,
            "resolutions": res_list,
            "max_resolution": f"{max(map(int, res_list))}p" if res_list else (f"{s.get('resolutions')}p" if s.get("resolutions") else None),
            "size_mb": size_mb,
            "duration_seconds": s.get("duration"),
            # CloudFront / Edge Cache signed cookies -> required as Cookie header on CDN requests
            "cookie": cookie,
            "episode_title": s.get("title"),
            "source_key": "streams[]",
            "bypassed_decoy": bypassed,
        })
    if not out and isinstance(payload, dict) and payload.get("resourceDetectors"):
        for d in payload.get("resourceDetectors") or []:
            for r in d.get("resolutionList") or []:
                r_url = r.get("resourceLink") or r.get("downloadUrl")
                if r_url and not is_decoy_url(r_url) and r_url not in seen:
                    seen.add(r_url)
                    res = str(r.get("resolution") or "720")
                    out.append({
                        "url": r_url,
                        "kind": "hls" if ".m3u8" in r_url.lower() else ("dash" if ".mpd" in r_url.lower() else "mp4"),
                        "resolutions": [res.rstrip("pP")],
                        "max_resolution": f"{res}p" if not res.endswith("p") else res,
                        "size_mb": round(int(r.get("size") or 0) / 1e6, 1) if r.get("size") else None,
                        "duration_seconds": r.get("duration"),
                        "cookie": None,
                        "episode_title": r.get("title"),
                        "source_key": "resourceDetectors[]",
                        "bypassed_decoy": True,
                    })
    if not out:
        for h in harvest_urls(payload, require_media_ext=False):
            if is_decoy_url(h["url"]):
                continue
            out.append({
                "url": h["url"],
                "kind": "hls" if ".m3u8" in h["url"].lower()
                        else ("dash" if ".mpd" in h["url"].lower() else "progressive"),
                "resolutions": [],
                "max_resolution": guess_resolution(h["url"], payload),
                "size_mb": None,
                "duration_seconds": None,
                "source_key": h["key_path"],
                "bypassed_decoy": False,
            })
    return out


def normalize_downloads(resource_payload: Any) -> Dict[str, Any]:
    payload = resource_payload.get("data") if (isinstance(resource_payload, dict) and "data" in resource_payload and isinstance(resource_payload["data"], dict)) else resource_payload
    urls = harvest_urls(payload, require_media_ext=False)
    downloads = [{
        "url": h["url"],
        "source_key": h["key_path"],
        "resolution": guess_resolution(h["url"], payload),
    } for h in urls]
    episodes_hint = []
    for lst in find_lists(payload):
        for item in lst:
            ep = _first(item, ["episode", "ep", "epNum", "number"])
            if ep is not None and len(episodes_hint) < 500:
                episodes_hint.append({"episode": ep,
                                      **{k: v for k, v in item.items()
                                         if isinstance(v, (str, int))}})
    return {"downloads": downloads, "episodes_raw": episodes_hint}


def normalize_subtitles(captions_payload: Any) -> List[Dict[str, Any]]:
    payload = captions_payload.get("data") if (isinstance(captions_payload, dict) and "data" in captions_payload) else captions_payload
    subs = []
    for lst in find_lists(payload):
        for item in lst:
            lang = _first(item, ["language", "lang", "languageName", "name"])
            url = _first(item, ["url", "fileUrl", "subtitleUrl", "path"])
            if url and not url.endswith((".mp4", ".m3u8", ".mpd", ".ts")):
                subs.append({"language": lang, "url": url})
    return subs
