from moviebox_wrapper.protocol_store import (
    ProtocolDiff, apply_diff, diff_extracted, mask_secrets, validate_protocol)

BASE = {
    "version": 1,
    "app": {"package": "com.community.oneroom", "version_name": "3.0.14",
            "version_code": 30014},
    "secrets": {"gateway_secret_online": "AAAAt79EBJZulIQIsV64FZr2O",
                "gateway_secret_test": "TESTOLD"},
    "hosts": {"primary": "api6.aoneroom.com", "fallbacks": []},
    "signature": {"profile": "hmac_md5_v2"},
    "endpoints": {"search_v2": {"method": "POST", "path": "/x"}},
}
REQUIRED = ["gateway_secret_online"]


def extracted(secrets=None, **app):
    s = {"gateway_secret_online": "NEWNEWNEWNEWNEWNEWNEWNEWNEW",
         "gateway_secret_test": "TESTOLD"}
    if secrets is not None:
        s = secrets
    return {"app": {"package": app.get("package", BASE["app"]["package"]),
                    "version_name": app.get("version_name", "3.0.14"),
                    "version_code": app.get("version_code", 30014)},
            "secrets": s}


def extracted_same():
    return extracted(secrets=dict(BASE["secrets"]))


def test_no_changes_is_not_healable_flag():
    d = diff_extracted(BASE, extracted_same(), REQUIRED)
    assert not d.has_changes and not d.changed_secrets


def test_rotated_secret_is_value_only_and_healable():
    d = diff_extracted(BASE, extracted(), REQUIRED)
    assert d.healable
    assert set(d.changed_secrets) == {"gateway_secret_online"}
    cand = apply_diff(BASE, d, "new.apk")
    assert cand["secrets"]["gateway_secret_online"] == "NEWNEWNEWNEWNEWNEWNEWNEWNEW"
    assert cand["version"] == 2
    assert cand["source_apk"] == "new.apk"
    validate_protocol(cand)


def test_version_bump_recorded():
    d = diff_extracted(BASE, extracted(version_code=31000, version_name="3.1.0"), REQUIRED)
    assert d.healable
    assert "app.version_code" in d.changed_app and "app.version_name" in d.changed_app


def test_missing_required_key_is_structural():
    d = diff_extracted(BASE, extracted(secrets={}), REQUIRED)
    assert not d.healable
    assert d.missing_required == ["gateway_secret_online"]
    assert "missing_required_keys" in d.summary()


def test_summary_masks_secret_values():
    d = diff_extracted(BASE, extracted(), REQUIRED)
    s = d.summary()
    old = s["changed_secrets"]["gateway_secret_online"]["old"]
    new = s["changed_secrets"]["gateway_secret_online"]["new"]
    assert old != "AAAAt79EBJZulIQIsV64FZr2O" and len(old) <= 4
    assert new != "NEWNEWNEWNEWNEWNEWNEWNEWNEW"


def test_mask_secrets_view_safe():
    m = mask_secrets(BASE)
    assert m["secrets"]["gateway_secret_online"].endswith("chars)")
    assert BASE["secrets"]["gateway_secret_online"] not in str(m)


def test_protocol_store_accepts_str_and_saves(tmp_path):
    from moviebox_wrapper.protocol_store import ProtocolStore
    proto_file = str(tmp_path / "proto.yaml")
    import yaml
    with open(proto_file, "w") as f:
        yaml.safe_dump(BASE, f)
    store = ProtocolStore(proto_file)
    assert store.data["version"] == 1
    new_data = dict(BASE)
    new_data["version"] = 2
    store.save(new_data, backup_dir=tmp_path / "backups")
    assert store.data["version"] == 2
