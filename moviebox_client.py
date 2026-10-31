#!/usr/bin/env python3
"""
MovieBox (com.community.oneroom) Complete Reverse-Engineered Python Client
Reproduces all device headers, token mechanics, and gateway signing.
"""

import base64
import hashlib
import hmac
import json
import time
import urllib.parse
import uuid
from typing import Any, Dict, Optional
import requests

# Secrets & Constants from APK
GATEWAY_SECRET_ONLINE = "76iRl07s0xSN9jqmEWAt79EBJZulIQIsV64FZr2O"
DEFAULT_API_HOST = "https://api6.aoneroom.com"
APP_PACKAGE = "com.community.oneroom"
APP_VERSION = "4.0.03.0922.03"
APP_VERSION_CODE = 50020131


def generate_device_id() -> str:
    return uuid.uuid4().hex


def generate_client_token() -> str:
    """
    Implements com.transsion.baselib.net.f & wg.a
    Formula: timestamp_ms + "," + md5(reverse(timestamp_ms))
    """
    ts_str = str(int(time.time() * 1000))
    reversed_ts = ts_str[::-1]
    md5_hash = hashlib.md5(reversed_ts.encode("utf-8")).hexdigest()
    return f"{ts_str},{md5_hash}"


def generate_client_info(device_id: str) -> str:
    """
    Implements jg.b X-Client-Info JSON payload.
    """
    info = {
        "package_name": APP_PACKAGE,
        "version_name": APP_VERSION,
        "version_code": APP_VERSION_CODE,
        "os": "android",
        "os_version": "14",
        "device_id": device_id,
        "install_store": "google_play",
        "brand": "Google",
        "model": "Pixel 8 Pro",
        "system_language": "en",
        "net": "WIFI",
        "region": "US",
        "timezone": "America/New_York",
        "sp_code": "0"
    }
    return json.dumps(info, separators=(",", ":"))


class MovieBoxSigner:
    """
    Implements Transsion GateWaySdk / GatewayInterceptor HMAC-MD5 signing.
    """
    def __init__(self, secret: str = GATEWAY_SECRET_ONLINE):
        self.secret_bytes = base64.b64decode(secret)

    def _canonical_query(self, query_string: str) -> str:
        if not query_string:
            return ""
        params = urllib.parse.parse_qsl(query_string, keep_blank_values=True)
        sorted_params = sorted(params, key=lambda x: x[0])
        return urllib.parse.urlencode(sorted_params)

    def sign(
        self,
        method: str,
        path: str,
        query: str = "",
        headers: Optional[Dict[str, str]] = None,
        body: Optional[bytes] = None,
        timestamp_ms: Optional[int] = None
    ) -> str:
        if headers is None:
            headers = {}
        if timestamp_ms is None:
            timestamp_ms = int(time.time() * 1000)

        method_str = method.upper()
        accept_str = headers.get("accept", headers.get("Accept", "*/*"))
        content_type_str = headers.get("content-type", headers.get("Content-Type", ""))
        content_length_str = str(len(body)) if body is not None and len(body) > 0 else ""

        if body:
            body_to_hash = body[:102400] if len(body) > 102400 else body
            body_md5 = hashlib.md5(body_to_hash).hexdigest()
        else:
            body_md5 = ""

        canonical_q = self._canonical_query(query)
        full_path = path
        if canonical_q:
            full_path = f"{path}?{canonical_q}"

        canonical_string = (
            f"{method_str}\n"
            f"{accept_str}\n"
            f"{content_type_str}\n"
            f"{content_length_str}\n"
            f"{timestamp_ms}\n"
            f"{body_md5}\n"
            f"{full_path}"
        )

        hmac_digest = hmac.new(self.secret_bytes, canonical_string.encode("utf-8"), hashlib.md5).digest()
        sig_base64 = base64.b64encode(hmac_digest).decode("utf-8")

        return f"{timestamp_ms}|2|{sig_base64}"


class MovieBoxClient:
    """Client for MovieBox backend."""

    def __init__(self, base_url: str = DEFAULT_API_HOST, secret: str = GATEWAY_SECRET_ONLINE):
        self.base_url = base_url.rstrip("/")
        self.signer = MovieBoxSigner(secret=secret)
        self.device_id = generate_device_id()
        self.session = requests.Session()
        self.user_token: Optional[str] = None
        self.user_id: Optional[str] = None

    def _bootstrap_session(self) -> None:
        """Bootstraps anonymous session token via search-suggest endpoint."""
        try:
            self._request("GET", "/wefeed-mobile-bff/subject-api/search-suggest", params={"q": "a"})
        except Exception:
            pass

    def _request(
        self,
        method: str,
        path: str,
        params: Optional[Dict[str, Any]] = None,
        json_data: Optional[Dict[str, Any]] = None,
        headers: Optional[Dict[str, str]] = None
    ) -> requests.Response:
        if not self.user_token and path != "/wefeed-mobile-bff/subject-api/search-suggest":
            self._bootstrap_session()

        url = f"{self.base_url}{path}"
        
        # Complete headers matching app's OkHttp Interceptor stack
        client_token = generate_client_token()
        client_info = generate_client_info(self.device_id)

        req_headers = {
            "accept": "application/json, text/plain, */*",
            "User-Agent": f"MovieBox/{APP_VERSION} (Android 14; Pixel 8 Pro)",
            "X-Client-Info": client_info,
            "X-Client-Status": "1",
            "X-Client-Token": client_token,
            "x-client-token": client_token,
            "token": client_token,
            "x-tr-app": APP_PACKAGE,
            "x-tr-version": APP_VERSION,
            "x-tr-device": self.device_id,
            "x-tr-region": "US"
        }

        if self.user_token:
            req_headers.pop("x-client-token", None)
            req_headers.pop("token", None)
            req_headers["Authorization"] = f"Bearer {self.user_token}"

        if headers:
            req_headers.update(headers)

        body_bytes = None
        if json_data is not None:
            req_headers["content-type"] = "application/json"
            body_bytes = json.dumps(json_data, separators=(",", ":")).encode("utf-8")
            req_headers["content-length"] = str(len(body_bytes))

        query_str = urllib.parse.urlencode(params) if params else ""

        # Sign request with x-tr-signature
        sig = self.signer.sign(
            method=method,
            path=path,
            query=query_str,
            headers=req_headers,
            body=body_bytes
        )
        req_headers["x-tr-signature"] = sig

        resp = self.session.request(
            method=method,
            url=url,
            params=params,
            data=body_bytes,
            headers=req_headers,
            timeout=15
        )

        # Harvest X-User token
        x_user = resp.headers.get("x-user")
        if x_user:
            try:
                user_obj = json.loads(x_user)
                if user_obj.get("token"):
                    self.user_token = user_obj["token"]
                if user_obj.get("userId"):
                    self.user_id = str(user_obj["userId"])
            except Exception:
                pass

        return resp

    # ==================== Core Media Endpoints ====================

    def get_subject_detail(self, subject_id: str) -> Dict[str, Any]:
        """Fetch movie / series detail by subject ID."""
        path = "/wefeed-mobile-bff/subject-api/get"
        params = {"subjectId": subject_id}
        resp = self._request("GET", path, params=params)
        return resp.json()

    def get_season_info(self, subject_id: str) -> Dict[str, Any]:
        """Fetch season & episode metadata for series."""
        path = "/wefeed-mobile-bff/subject-api/season-info"
        params = {"subjectId": subject_id}
        resp = self._request("GET", path, params=params)
        return resp.json()

    def get_play_info(self, subject_id: str, season: int = 1, episode: int = 1) -> Dict[str, Any]:
        """Fetch video stream URL & subtitle tracks."""
        path = "/wefeed-mobile-bff/subject-api/play-info"
        params = {"subjectId": subject_id, "se": season, "ep": episode}
        resp = self._request("GET", path, params=params)
        return resp.json()

    def get_download_resources(
        self,
        subject_id: str,
        page: int = 1,
        per_page: int = 10,
        resolution: int = 0
    ) -> Dict[str, Any]:
        """Fetch direct download links."""
        path = "/wefeed-mobile-bff/subject-api/resource"
        params = {
            "subjectId": subject_id,
            "page": str(page),
            "perPage": per_page,
            "all": 0,
            "startPosition": 1,
            "endPosition": per_page,
            "pagerMode": 0,
            "resolution": resolution,
            "se": 1,
            "epFrom": 1,
            "epTo": per_page
        }
        resp = self._request("GET", path, params=params)
        return resp.json()


if __name__ == "__main__":
    print("=" * 60)
    print("🎬 MovieBox Complete Client (With X-Client-Info & Tokens)")
    print("=" * 60)

    client = MovieBoxClient()
    print(f"[*] Generated Device ID: {client.device_id}")
    print(f"[*] Target Base URL: {client.base_url}")

    test_subject_id = "5904172458474619680"
    print(f"\n[*] Querying subject detail for ID: {test_subject_id}...")
    try:
        res = client.get_subject_detail(test_subject_id)
        print(f"[+] Response:\n{json.dumps(res, indent=2)}")
    except Exception as e:
        print(f"[-] Error: {e}")
