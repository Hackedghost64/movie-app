# MovieBox (v3.0.14) Complete System Deconstruction & Vulnerability Documentation

**Target Application:** MovieBox (`com.community.oneroom`)  
**Package Version:** 3.0.14 (Build 35 / Android 15 target)  
**Primary Developer / Framework Provider:** Transsion Holdings (`com.transsion.*`)  
**Document Nature:** Comprehensive Technical Breakdown & Vulnerability Inventory (Findings Only)

---

## 1. System Architecture & Component Inventory

### 1.1 Multi-DEX & Package Breakdown
The application bytecode spans 8 distinct DEX files (`classes.dex` to `classes8.dex`) organized into several core functional domains:

* **Core Gateway & Routing:** `com.transsion.api.gateway.*`
  * Manages global service discovery, DNS fallback resolution, multi-region host switching, and HMAC request signing.
* **Networking & HTTP Layer:** `com.cloud.hisavana.net.*`, `kg.c`, `jg.*`, `ig.*`
  * Wraps OkHttp, Retrofit, and Cronet (QUIC protocol support).
  * Automatically injects tracking headers, device metrics, client tokens, and HMAC signatures on every outbound request.
* **Media & Download Engine:** `com.transsion.player.*`, `com.transsnet.downloader.*`, `com.transsion.videodetail.*`
  * Media3 / ExoPlayer integration with custom native codecs.
  * Multi-part, multi-threaded background download manager.
* **User Authentication & Session Management:** `com.transsnet.login.*`, `com.transsnet.loginapi.*`
  * Handles phone (SMS), email, and third-party (Google OAuth) authentication states.
* **Telemetry & Tracking:** `com.cloud.hisavana.sdk.common.athena.*`, `com.transsion.athena.*`
  * Deep analytics tracking recording user interactions, video watch duration, and device attributes.
* **MiniApp Runtime:** `com.cloud.tmc.miniapp.*`
  * Embedded hybrid micro-application engine capable of executing external offline bundles and web-based applets.

### 1.2 Native Shared Libraries (`.so`)
The APK bundles 28 native binaries across `arm64-v8a` and `armeabi-v7a`:

| Library Name | Identified Role / Subsystem |
| :--- | :--- |
| `libsaasCorePlayer.so` | Proprietary media rendering and playback engine |
| `libsaasDownloader.so` | Video chunking and accelerated download pipeline |
| `libalivcffmpeg.so`, `libavcodec.so`, `libavformat.so` | Custom FFmpeg builds for audio/video decoding |
| `libpglarmor.so` | PGL Armour anti-tamper and environment integrity layer |
| `libstub.so` | Dynamic DEX loader / stub execution mechanism |
| `libtobEmbedPagEncrypt.so` | ByteDance PAG encrypted graphic animation rendering |
| `libmmkv.so` | High-performance Tencent memory-mapped key-value storage |

---

## 2. Complete Inventory of Discovered Credentials & Secrets

The following sensitive credentials and static keys are hardcoded in the application assets and manifests:

```
[ Manifest & Resource Secrets Extracted ]
├── AndroidManifest.xml
│   ├── gateway_secret_online: "76iRl07s0xSN9jqmEWAt79EBJZulIQIsV64FZr2O"
│   ├── gateway_secret_test:   "Xqn2nnO41/L92o1iuXhSLHTbXvY4Z5ZZ62m8mSLA"
│   ├── alivc_license:         "volXpoYXKsoRJDDPt89df7215938a4eb88c536e67cd49923c"
│   └── AdMob App ID:          "ca-app-pub-5464101117258718~2034480240"
├── res/values/strings.xml
│   ├── google_api_key:        "AIzaSyDoUlg4QWx_EYkLV9IoIzaRvysnE_7G_EQ"
│   ├── google_client_token:   "696179319202-hekemrrgc6kdd33tfr0sktarq53808ga.apps.googleusercontent.com"
│   └── crashlytics_mapping:   "af0f4e533c244d7aa65842dc1dbcbd05"
└── assets/
    ├── rsa_public_key.pem:     RSA-2048 Public Key (Hisavana Auth)
    └── license.crt:            Alibaba Media Player Certificate
```

---

## 3. Communication Mechanics & Cryptographic Vulnerabilities

### 3.1 Transsion Gateway HMAC Signing (`x-tr-signature`)
All HTTP interactions with Transsion API hosts (`api6.aoneroom.com`, `i-api.aoneroom.com`, `api.eagllwin.com`) require a cryptographic signature calculated in `com.transsion.api.gateway.interceptor.GatewayInterceptor`:

* **Canonical String Format:**
  ```text
  <HTTP_METHOD>
  <accept_header>
  <content_type_header>
  <content_length>
  <timestamp_ms>
  <body_md5_hex>
  <path_and_alphabetically_sorted_query>
  ```
* **Signing Algorithm:** `HMAC-MD5` using `Base64.decode(gateway_secret_online)` as the HMAC secret key.
* **Header Format:** `x-tr-signature: <timestamp_ms>|2|<base64_digest>`

### 3.2 Client Token Insecurity (`X-Client-Token`)
In `com.transsion.baselib.net.f`, guest and unauthenticated sessions pass an `X-Client-Token` header. The token is generated through a deterministic, entirely client-side computation:

$$\text{X-Client-Token} = \text{timestamp\_ms} + \text{","} + \text{MD5}(\text{reverse}(\text{timestamp\_ms}))$$

No server entropy or asymmetric signing is used, making it forgeable by any client.

### 3.3 Dynamic Header Injection (`X-Client-Info`)
Requests automatically attach a JSON payload containing device metrics in the `X-Client-Info` header (`jg.b`):
```json
{
  "package_name": "com.community.oneroom",
  "version_name": "3.0.14",
  "version_code": 30014,
  "os": "android",
  "os_version": "14",
  "device_id": "<uuid>",
  "install_store": "google_play",
  "brand": "Google",
  "model": "Pixel 8 Pro",
  "system_language": "en",
  "net": "WIFI",
  "region": "US",
  "timezone": "America/New_York",
  "sp_code": "0"
}
```

### 3.4 Transport Security & Certificate Pinning Bypasses
The application's `network_security_config.xml` disables standard TLS protection:
* `cleartextTrafficPermitted="true"` permits unencrypted HTTP across the network layer.
* `overridePins="true"` allows intercepting HTTPS traffic when a user certificate authority (such as a proxy certificate) is present on the device.

---

## 4. Backend Endpoints & Service Catalog

The backend services communicate via clear REST interfaces mapped below:

### 4.1 Media Discovery, Streaming & Downloads
* **`GET /wefeed-mobile-bff/subject-api/get`**  
  Retrieves complete metadata for a title (title, synopsis, actors, genres, cover images, rating).
* **`GET /wefeed-mobile-bff/subject-api/season-info`**  
  Lists available seasons and episode numbers for TV series.
* **`GET /wefeed-mobile-bff/subject-api/play-info`**  
  Fetches direct streaming URLs (HLS / MP4), resolution options, and subtitle track indices.
* **`GET /wefeed-mobile-bff/subject-api/resource`**  
  Returns downloadable media chunks and source download URLs.
* **`GET /wefeed-mobile-bff/sniff/config`**  
  Returns web-scraping rules and video sniffing regex definitions for web sources.

### 4.2 User Management & Authentication
* **`POST /wefeed-mobile-bff/user-api/check-mail-account`**  
  Verifies if an email account is registered in the database.
* **`POST /wefeed-mobile-bff/user-api/check-phone-account`**  
  Verifies phone number registration status.
* **`POST /wefeed-mobile-bff/user-api/get-sms-code`**  
  Triggers verification code delivery for login/registration.
* **`POST /wefeed-mobile-bff/user-api/login`**  
  Authenticates credentials and returns a user session `token` and `userId`.
* **`GET /wefeed-mobile-bff/user-api/info`**  
  Returns profile data for a given `userId`.

---

## 5. Security Findings & Exposure Summary

1. **Static Cryptographic Secret Exposure:** Hardcoded HMAC keys in application manifests invalidate the intended request validation boundary.
2. **Deterministic Token Vulnerability:** `X-Client-Token` generation lacks server-side verification and entropy, permitting unauthorized guest session forgery.
3. **Transport Security Weaknesses:** Configuration files explicitly permit cleartext communication and certificate pinning overrides.
4. **Exported IPC Attack Surface:** Multiple services (`IpcMiniLauncherService`, `MiniAppProtocolMainService`) are marked `exported="true"` without caller permission requirements.
5. **Backend Emulation Feasibility:** The combination of exposed signing secrets, deterministic client tokens, and static REST endpoints allows full third-party replication of official client requests.
