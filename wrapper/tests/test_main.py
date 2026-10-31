import pytest
from fastapi.testclient import TestClient

def test_app_import_and_routes():
    from moviebox_wrapper.main import app
    assert app is not None
    with TestClient(app) as client:
        # Verify health route exists and responds
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data.get("ok") is True

def test_stream_model_normalization():
    from moviebox_wrapper.translate import normalize_streams
    fake_play_info = {
        "streams": [
            {
                "format": "DASH",
                "id": "123",
                "url": "https://sbcdn5.hakunaymatata.com/dash/123/index_web.mpd",
                "resolutions": "1080,720",
                "size": "500000000",
                "duration": 2000,
                "signCookie": "CloudFront-Policy=test; CloudFront-Signature=sig"
            }
        ]
    }
    streams = normalize_streams(fake_play_info)
    assert len(streams) == 1
    st = streams[0]
    assert st["kind"] == "dash"
    assert st["max_resolution"] == "1080p"
    assert st["cookie"] is not None
