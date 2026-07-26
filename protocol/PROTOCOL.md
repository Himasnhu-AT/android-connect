# AndroidConnect wire protocol — v1

The single source of truth for how the macOS app and the Android app talk. Both sides implement
this exactly. If you change anything here, bump `PROTOCOL_VERSION` and update
[`messages.schema.json`](./messages.schema.json) and both implementations.

```
PROTOCOL_VERSION = 1
SERVICE_TYPE     = "_androidconnect._tcp"   (mDNS/Bonjour, local. domain)
DEFAULT_PORT     = 0 (ephemeral; the real port is advertised in the mDNS SRV record)
```

## 1. Discovery

Each device **advertises** an mDNS service of type `_androidconnect._tcp` and **browses** for the
same. The TXT record carries:

| key   | value                                             |
|-------|---------------------------------------------------|
| `id`  | device UUID (stable per install)                  |
| `name`| human device name (e.g. "Himanshu's MacBook")     |
| `plat`| `macos` \| `android`                              |
| `fp`  | SHA-256 fingerprint of the device's TLS cert (hex)|
| `pv`  | protocol version (int)                            |

`fp` lets a browser recognise an **already-paired** peer before connecting, so reconnects are silent.

## 2. Transport & framing

One persistent **TLS 1.3** TCP connection per paired peer (the "control connection"). **The Android
device is always the TLS client (it dials); the Mac is always the TLS server (it advertises + listens).**
The Mac is authenticated by its **server certificate** (fingerprint-pinned by the phone, see §4). The
phone is **not** authenticated by a client certificate — Apple's Network.framework can't verify a peer
client cert as a TLS server — so the phone proves its identity at the **app layer** with a signed
challenge (`authChallenge`/`authResponse`, §3 & §4). This also means only phone→Mac connectivity is
required, which survives Wi-Fi client-isolation.

All bytes after the TLS handshake are **frames**:

```
┌────────────┬────────┬─────────────────────────────┐
│ length     │ type   │ payload                      │
│ uint32 BE  │ uint8  │ (length − 1) bytes           │
└────────────┴────────┴─────────────────────────────┘
  length counts (type + payload). Max frame = 1 MiB. Big-endian.
```

`type`:
- `0x00` **JSON control message** — payload is UTF-8 JSON, one object with a `t` discriminator (§3).
- `0x01` **Binary chunk** — payload is `[16-byte transferId][chunk bytes]`. Chunks are ≤ **64 KiB**
  so control messages interleave between them (no head-of-line blocking). Used for file transfer.

Bulk data is multiplexed on the *same* connection via `0x01` frames — no second socket, no base64.

## 3. Control messages (`type 0x00`)

Every JSON object has a string field `t` (the type tag). Fields marked `?` are optional.
See `messages.schema.json` for the authoritative schema.

### Session
- `hello` — `{ t, pv, id, name, plat, appVersion, caps }` — sent by **both** sides immediately after
  the connection is authenticated. `caps` is a string array of supported features, e.g.
  `["clipboard","files","notifications","calls"]`. Enables clean v2 negotiation (e.g. `"screen"`).
- `ping` / `pong` — `{ t, nonce }` — keepalive + RTT. Send `ping` every 20 s; reply `pong` echoing
  `nonce`. Two missed pongs ⇒ treat peer as offline and reconnect.

### Pairing  (exchanged on a not-yet-trusted but TLS-encrypted connection — see §4)
- `pairResponse` — `{ t, accepted, id, name, plat, fp, reason? }` — Mac → phone, sent after the phone
  passes the identity challenge, to confirm (or refuse) the pairing.
- `pairRequest`  — `{ t, id, name, plat, fp, token? }` — reserved; superseded by `authResponse` below.

### Identity proof  (replaces TLS client-cert auth, which macOS servers can't do)
- `authChallenge` — `{ t, nonce }` — **Mac → phone**, immediately after the connection is ready.
  `nonce` is base64 of 32 random bytes.
- `authResponse`  — `{ t, cert, sig }` — **phone → Mac**. `cert` = base64 DER of the phone's TLS
  certificate; `sig` = base64 **ECDSA-SHA256** signature over the `nonce`'s UTF-8 bytes. The Mac
  verifies `sig` against `cert`'s public key and pins `SHA-256(cert)` as the phone's fingerprint.

### Clipboard
- `clipboard` — `{ t, contentType: "text", text }` — sent when the local clipboard changes.

### Notifications  (Android → Mac, plus Mac → Android actions)
- `notifPosted`  — `{ t, key, appName, pkg, title, text, when, actions? }`
  where `actions` = `[{ id, title, remoteInput }]`.
- `notifRemoved` — `{ t, key }`
- `notifAction`  — `{ t, key, actionId, reply? }`  (Mac → Android)
- `notifDismiss` — `{ t, key }`                     (Mac → Android)

### File transfer
- `fileOffer`    — `{ t, transferId, name, size, mime }`  (sender → receiver)
- `fileAccept`   — `{ t, transferId }`                     (receiver → sender) ⇒ sender streams
  `0x01` chunks tagged with `transferId`, then `fileComplete`.
- `fileReject`   — `{ t, transferId, reason? }`
- `fileComplete` — `{ t, transferId, sha256? }`
- `fileError`    — `{ t, transferId, message }`

### Calls  (Android → Mac state, Mac → Android control)
- `callState`  — `{ t, callId, state: "ringing"|"active"|"dialing"|"disconnected",
  direction: "incoming"|"outgoing", number?, contactName? }`
- `callAction` — `{ t, callId, action: "answer"|"decline"|"end"|"mute"|"unmute" }`  (Mac → Android)

> **Call audio stays on the phone.** Over LAN we can only mirror state and control the call; Android
> blocks call-audio capture for non-system apps. The Mac UI must say so.

## 4. Pairing & trust (TOFU + fingerprint pinning)

1. On first launch each device generates a persistent **P-256 keypair + self-signed cert**
   (macOS: CryptoKit/Security + **Keychain**; Android: **Android Keystore**). `fp` = SHA-256 of the
   cert's DER encoding, hex, lowercase, colon-free.
2. **QR pairing (primary, "effortless"):** the Mac shows a QR encoding
   `ac://pair?host=<ip>&port=<p>&fp=<macFp>&token=<oneTime>`. The phone scans it, connects (as the TLS
   **client**), and **verifies the Mac's server-cert fingerprint equals `fp` from the QR** (defeats
   MITM). The Mac sends `authChallenge{nonce}`; the phone replies `authResponse{cert,sig}`. The Mac
   verifies the signature and **pins `SHA-256(cert)` as the phone's fingerprint**, then (if it is in
   pairing mode) replies `pairResponse{ accepted:true, fp:<macFp> }`. The phone pins the Mac's `fp`.
   Both persist the peer `{id,name,plat,fp}` in their trust store.
3. **Numeric SAS fallback (no camera):** derive a 6-digit code from the TLS exporter secret
   (`TLS-Exporter`, label `"ac-pair"`, 4 bytes → decimal mod 1e6) on both sides; the user confirms
   the codes match, then the same `pairRequest`/`pairResponse` exchange runs.
4. **Reconnect:** the phone auto-dials any browsed Mac whose TXT `fp` it has already pinned — it
   verifies the Mac's server cert matches the pinned `fp`, answers the `authChallenge`, exchanges
   `hello`, done. No prompts.
5. **Unpair:** drop the peer from the trust store; the next connection attempt from it is refused.

Any cert-fingerprint mismatch (pinned ≠ presented) ⇒ **abort the connection** and surface a warning.

## 5. Versioning

`pv` (protocol version) is exchanged in discovery TXT and in `hello`. If the peer's `pv` is greater
than ours, negotiate down to the lower of the two and ignore unknown message types / caps. Unknown
`t` values are logged and skipped, never fatal.
