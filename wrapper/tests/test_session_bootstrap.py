"""Anonymous session bootstrap: X-User capture + Authorization adoption (q.h parity)."""
import time

from moviebox_wrapper.upstream.identity import DeviceIdentity
from moviebox_wrapper.upstream.client import UpstreamClient

JWT = "eyJhbGciOiJIUzI1NiJ9.test.sig"


class FakeStore:
    def __init__(self, data):
        self._data = data

    @property
    def data(self):
        return self._data


class FakeResp:
    def __init__(self, headers, status=200, body_code="0"):
        self.headers = headers
        self.status_code = status


def make_identity(tmp_path):
    return DeviceIdentity(tmp_path / "device.json",
                          {"app": {"package": "x", "version_name": "1", "version_code": 1}},
                          region="US")


def test_session_roundtrip_persists(tmp_path):
    ident = make_identity(tmp_path)
    assert ident.get_session() is None
    ident.save_session({"token": JWT, "userId": 123, "userType": 0})
    again = make_identity(tmp_path)          # fresh instance -> file reload
    s = again.get_session()
    assert s and s["token"] == JWT and s["userId"] == "123"


def test_clear_session(tmp_path):
    ident = make_identity(tmp_path)
    ident.save_session({"token": JWT})
    ident.clear_session()
    assert ident.get_session() is None


def _client_with(tmp_path, proto=None):
    ident = make_identity(tmp_path)
    store = FakeStore(proto or {"session_token": ""})
    return UpstreamClient(store, ident), ident, store


def test_capture_session_from_x_user_header(tmp_path):
    c, ident, _ = _client_with(tmp_path)
    c._capture_session(FakeResp({"x-user": f'{{"token":"{JWT}","userId":"9","userType":0}}'}))
    assert ident.get_session()["token"] == JWT


def test_capture_ignored_when_explicit_token_configured(tmp_path):
    c, ident, _ = _client_with(tmp_path, {"session_token": "explicit.jwt"})
    c._capture_session(FakeResp({"x-user": f'{{"token":"{JWT}"}}'}))
    assert ident.get_session() is None


def test_capture_survives_malformed_header(tmp_path):
    c, ident, _ = _client_with(tmp_path)
    c._capture_session(FakeResp({"x-user": "not-json"}))
    c._capture_session(FakeResp({}))
    assert ident.get_session() is None


def test_auth_header_prefers_explicit_then_anon(tmp_path):
    c, ident, store = _client_with(tmp_path)
    assert c._auth_header(store.data) is None
    ident.save_session({"token": JWT})
    assert c._auth_header(store.data) == "Bearer " + JWT
    store._data["session_token"] = "explicit.jwt"
    assert c._auth_header(store.data) == "Bearer explicit.jwt"
