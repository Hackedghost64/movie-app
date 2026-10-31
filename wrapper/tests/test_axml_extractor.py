"""End-to-end extractor test against the REAL APK in the repo (if present)
and the decoded apktool manifest fixture."""
import os

import pytest

from moviebox_wrapper.selfheal.extractor import extract, newest_apk_in

WRAPPER = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(WRAPPER)
_candidates = [
    os.path.join(WRAPPER, "watch", "moviebox-v-3.0.14(1).apk"),
    os.path.join(REPO, "moviebox-v-3.0.14(1).apk"),
    os.path.join(WRAPPER, "watch", "moviebox-v-4.0.02.0831.03.apk"),
]
REAL_APK = next((p for p in _candidates if os.path.exists(p)), _candidates[0])
DECODED_TREE = os.path.join(REPO, "work", "moviebox-3014", "apktool_out")

EXPECTED_ONLINE = "76iRl07s0xSN9jqmEWAt79EBJZulIQIsV64FZr2O"
EXPECTED_TEST = "Xqn2nnO41/L92o1iuXhSLHTbXvY4Z5ZZ62m8mSLA"


def _assert_facts(ex, require_version=True):
    assert ex.package == "com.community.oneroom"
    assert ex.secrets["gateway_secret_online"] == EXPECTED_ONLINE
    assert ex.secrets["gateway_secret_test"] == EXPECTED_TEST
    if require_version:
        assert str(ex.version_code).isdigit()


@pytest.mark.skipif(not os.path.exists(REAL_APK), reason="real APK not present")
def test_extract_from_real_apk_binary_manifest():
    ex = extract(REAL_APK)
    _assert_facts(ex)


@pytest.mark.skipif(not os.path.exists(DECODED_TREE), reason="decoded tree not present")
def test_extract_from_decoded_tree():
    # apktool tree for this build omits versionCode on <manifest>; don't require it
    ex = extract(DECODED_TREE)
    _assert_facts(ex, require_version=False)


def test_watch_dir_scan(tmp_path):
    assert newest_apk_in(tmp_path) is None
    old = tmp_path / "old.apk"; new = tmp_path / "new.apk"
    old.write_bytes(b"x"); new.write_bytes(b"yy")
    import time
    time.sleep(0.01)
    old.touch(); new.touch()
    assert newest_apk_in(tmp_path) == new
