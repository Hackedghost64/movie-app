# Protocol reference (internal)

Verified behavior of the upstream service the gateway speaks to.

## Request signing
- Canonical string (field order configurable via `protocol/protocol.yaml`):
  `METHOD\naccept\ncontent-type\ncontent-length\ntimestamp\nbody_md5(≤100KB)\npath?sorted_query`
- Query canonicalization: URL-decode pairs, duplicate keys last-wins,
  sort by key only, rejoin raw values without re-encoding.
- Header: `x-tr-signature: {ts}|2|{base64(HMAC-MD5(secret, canonical))}`;
  secret = base64-decoded `gateway_secret_online`.
- Clock skew: HTTP 500 + body code GW.4410 carries server time; store offset
  and retry once.

## Identity & session
- Guest header set: X-Client-Token = `{ms},{md5(reversed ms)}` plus
  x-tr-app/version/device/region and X-Client-Info JSON fingerprint.
- Server auto-provisions an anonymous account per device and returns it in the
  `X-User` response header: `{token (JWT ~90d), userId, userType}`. The client
  adopts it silently and switches to `Authorization: Bearer <jwt>`.
  Implemented in `upstream/client.py` (`_capture_session`, `_bootstrap_session`).

## Routing quirks
- `subject-api/*` endpoints require a `host=<api-host>` query parameter for
  backend routing (flagged `needs_host_param` in protocol.yaml).
- Streaming manifests are CloudFront-signed: each play-info stream entry ships
  a `signCookie` (CloudFront-Policy/Signature/Key-Pair-Id) that must be sent as
  the `Cookie` header on manifest + segment requests.
- Direct MP4 resources use query-signed URLs with a short `t=` expiry.

## Upstream envelope
`{code:"0", message, data, reason}` — ok codes configured in protocol.yaml.

## Self-provisioning
All volatile facts (secrets, hosts, endpoints, signing profile) live in
`protocol/protocol.yaml`. The healer extracts fresh facts from an app bundle
in `watch/`, diffs value-only vs structural drift, live-verifies candidates
and hot-swaps with backup on success. Signing algorithms are pluggable
profiles registered in `upstream/signers.py`.
