# Provisioning & self-healing

The gateway depends on a set of provisioning facts (credentials, hosts,
endpoint paths, signing profile) held in `protocol/protocol.yaml`. Upstream
services occasionally rotate these; MBX detects and repairs itself.

## Detection

Every signed request is classified. Repeated auth rejections
(`auth_fail_threshold` in config.yaml, default 3 consecutive) flip the gateway
to `PROTOCOL_STALE`:

- `/health` reports the state + remediation text
- error responses carry `X-Wrapper-State` / `X-Wrapper-Remediation` headers

## Repair flow

```
1. obtain a fresh app bundle (APK) for the service you proxy
2. drop it into  watch/
3. mbx heal        (also runs automatically at startup)
```

The healer:

1. extracts provisioning facts from the bundle's binary manifest
   (zero-dependency parser; also accepts an already-decoded manifest tree)
2. diffs them against the live `protocol.yaml`
   - **value-only drift** (rotated credentials / version bump)
     → builds a candidate, live-verifies it with a real signed probe request,
       backs up the current file to `protocol/backups/`, swaps and hot-reloads
   - **structural drift** (required keys missing/renamed)
     → refuses to guess; reports exactly which keys moved so they can be
       remapped manually in protocol.yaml
3. resets the staleness detector on success

## Algorithm changes

If the signing *algorithm* itself changes (not just values), add a profile
class in `moviebox_wrapper/upstream/signers.py` and point
`signature.profile` at it. Field order of the canonical string is data, not
code (`signature.canonical_fields`).

## Diagnostics

```bash
mbx doctor          # config/identity layers
mbx doctor --live   # + DNS/TLS/signature/session probes
```
