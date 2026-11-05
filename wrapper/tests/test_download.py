import io
import json
from pathlib import Path
from unittest.mock import MagicMock, patch
import pytest
from fastapi.testclient import TestClient

from moviebox_wrapper.main import app, state
from moviebox_wrapper.translate import normalize_downloads
from moviebox_wrapper.tui import download_file, smart_download


def test_normalize_downloads_metadata():
    """Verify normalize_downloads parses raw upstream resource payloads."""
    payload = {
        "data": {
            "episodes": [
                {
                    "ep": 1,
                    "se": 1,
                    "resolution": "1080",
                    "codecName": "hevc",
                    "size": 750000000,
                    "resourceLink": "https://cdn.example.com/downloads/s1e1_1080p.mp4",
                    "requireMemberType": 0,
                },
                {
                    "ep": 2,
                    "se": 1,
                    "resolution": "720",
                    "codecName": "h264",
                    "size": 450000000,
                    "downloadUrl": "https://cdn.example.com/downloads/s1e2_720p.mp4",
                    "requireMemberType": 0,
                },
            ]
        }
    }
    result = normalize_downloads(payload)
    assert "downloads" in result
    downloads = result["downloads"]
    assert len(downloads) == 2

    # Verify harvested URLs
    assert downloads[0]["url"] == "https://cdn.example.com/downloads/s1e1_1080p.mp4"
    assert downloads[1]["url"] == "https://cdn.example.com/downloads/s1e2_720p.mp4"

    # Verify parsed episodes list
    assert "episodes_raw" in result
    raw_episodes = result["episodes_raw"]
    assert len(raw_episodes) == 2
    assert raw_episodes[0]["episode"] == 1
    assert raw_episodes[1]["episode"] == 2


def test_download_endpoint_with_direct_resources():
    """Verify /titles/{subject_id}/download queries upstream, filters season/episode, and sorts by resolution."""
    with TestClient(app) as client:
        app.state.auth_guard = None
        mock_client = MagicMock()
        mock_client.request.return_value = {
            "upstream_code": 0,
            "data": {
                "list": [
                    {
                        "se": 1,
                        "ep": 1,
                        "episode": 1,
                        "title": "Pilot (720p)",
                        "resolution": "720",
                        "codecName": "h264",
                        "size": 350000000,
                        "duration": 3600,
                        "resourceLink": "https://cdn.example.com/s1e1_720p.mp4",
                    },
                    {
                        "se": 1,
                        "ep": 1,
                        "episode": 1,
                        "title": "Pilot (1080p)",
                        "resolution": "1080",
                        "codecName": "hevc",
                        "size": 700000000,
                        "duration": 3600,
                        "resourceLink": "https://cdn.example.com/s1e1_1080p.mp4",
                    },
                    {
                        "se": 1,
                        "ep": 2,
                        "episode": 2,
                        "title": "Chapter 2",
                        "resolution": "1080",
                        "codecName": "hevc",
                        "size": 710000000,
                        "duration": 3600,
                        "resourceLink": "https://cdn.example.com/s1e2_1080p.mp4",
                    },
                ]
            },
        }

        with patch.dict(state, {"client": mock_client}):
            # Test download request for Season 1, Episode 1 with pages=1
            resp = client.get("/titles/sub-999/download?se=1&ep=1&pages=1")
            assert resp.status_code == 200
            data = resp.json()

            assert data["ok"] is True
            assert data["count"] == 2
            resources = data["all"]

            # Verify highest resolution comes first (1080p > 720p)
            assert resources[0]["resolution"] == "1080p"
            assert resources[0]["signed_url"] == "https://cdn.example.com/s1e1_1080p.mp4"
            assert resources[1]["resolution"] == "720p"
            assert resources[1]["signed_url"] == "https://cdn.example.com/s1e1_720p.mp4"
            assert data["selected"]["resolution"] == "1080p"


def test_download_endpoint_strips_decoy_honeypot_urls():
    """Verify download endpoint eliminates honeypot decoy URLs from downloadable resources."""
    with TestClient(app) as client:
        app.state.auth_guard = None
        mock_client = MagicMock()
        mock_client.request.return_value = {
            "upstream_code": 0,
            "data": {
                "list": [
                    {
                        "se": 1,
                        "ep": 1,
                        "title": "Decoy Trap",
                        "resolution": "1080",
                        "resourceLink": "https://macdn.aoneroom.com/other/2026/09/04/b164fbfb4347792950bdfbfb563d39d9.mp4",
                    },
                    {
                        "se": 1,
                        "ep": 1,
                        "title": "Authentic Media",
                        "resolution": "720",
                        "resourceLink": "https://bcdn.hakunaymatata.com/resource/genuine.mp4",
                    },
                ]
            },
        }

        with patch.dict(state, {"client": mock_client}):
            resp = client.get("/titles/sub-999/download?se=1&ep=1&pages=1")
            assert resp.status_code == 200
            data = resp.json()
            assert data["ok"] is True
            resources = data["all"]

            # Decoy must be purged, only authentic media remains
            assert len(resources) == 1
            assert "b164fbfb" not in resources[0]["signed_url"]
            assert resources[0]["signed_url"] == "https://bcdn.hakunaymatata.com/resource/genuine.mp4"


def test_download_endpoint_fallback_to_play_info():
    """When direct download resources are empty, fallback to play_info streams for download."""
    with TestClient(app) as client:
        app.state.auth_guard = None
        mock_client = MagicMock()

        def mock_request(endpoint, params=None):
            if endpoint.name == "resource":
                return {"upstream_code": 0, "data": {"list": []}}
            elif endpoint.name == "play_info":
                return {
                    "upstream_code": 0,
                    "data": {
                        "streams": [
                            {
                                "format": "MP4",
                                "url": "https://cdn.hakunaymatata.com/fallback/stream.mp4",
                                "resolutions": "720",
                                "size": "420000000",
                                "duration": 2400,
                            }
                        ]
                    },
                }
            return {"upstream_code": 0, "data": {}}

        mock_client.request.side_effect = mock_request

        with patch.dict(state, {"client": mock_client}):
            resp = client.get("/titles/sub-123/download?se=1&ep=1&pages=1")
            assert resp.status_code == 200
            data = resp.json()
            assert data["ok"] is True
            resources = data["all"]
            assert len(resources) == 1
            assert resources[0]["signed_url"] == "https://cdn.hakunaymatata.com/fallback/stream.mp4"
            assert resources[0]["resolution"] == "720p"


def test_tui_download_file_and_smart_download(tmp_path):
    """Verify download_file stream writing and smart_download destination formatting."""
    content = b"fake video content for testing download feature"

    class FakeResponse:
        def __init__(self):
            self.headers = {"content-length": str(len(content))}
            self._stream = io.BytesIO(content)

        def read(self, size):
            return self._stream.read(size)

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

    progress_events = []

    def on_progress(done, total):
        progress_events.append((done, total))

    dest = tmp_path / "downloads" / "TestMovie.mp4"

    with patch("urllib.request.urlopen", return_value=FakeResponse()):
        ok = download_file("https://cdn.example.com/test.mp4", dest, on_progress=on_progress)
        assert ok is True
        assert dest.exists()
        assert dest.read_bytes() == content
        assert len(progress_events) > 0
        assert progress_events[-1] == (len(content), len(content))

    # Test smart_download with signed_url resource
    with patch("moviebox_wrapper.tui._downloads_dir", return_value=tmp_path / "downloads"), \
         patch("moviebox_wrapper.tui.download_file", return_value=True):
        res = {"signed_url": "https://cdn.example.com/s01e05.mp4"}
        ok, out_path = smart_download(res, stream=None, title="Breaking Bad", se=1, ep=5)
        assert ok is True
        assert out_path is not None
        assert out_path.name == "Breaking.Bad.S01E05.mp4"
