# Sync

[Home](../README.md) · [Development](development.md)

Phone HTTP sync and Mac-to-Mac iCloud sync are independent. System Universal Clipboard is a third mechanism: PasteHistory records supported content only after it reaches the Mac.

## Phone access

Click the permanent **Phone Sync** tree card and scan its QR code on a reachable local network. Keep the Mac awake and PasteHistory running. The URL is `http://<Mac-IP>:8377/#pair=<percent-encoded-code>`; the page decodes the fragment with `URLSearchParams` or reads `localStorage.phPair`, with no manual code-entry form. Refreshing the QR code rotates the code, token and key; reopening the card does not. Startup automatically replaces legacy six-digit or invalid saved codes; phones must rescan once after this upgrade.

The HTTP page uses a paste box to upload text. It can copy downloaded text/file paths and save images, but cannot transfer arbitrary Mac files. It searches at most 300 downloaded records. Clipboard/WebCrypto APIs may be unavailable on phone HTTP origins: preserve the paste-box, copy and pure-JS crypto fallbacks. A home-screen shortcut does not provide offline Service Worker support; localhost behavior is not evidence of phone capability.

## Security boundary

AES-256-GCM protects content payloads and image responses, **not the HTTP transport**. Record IDs, kinds, timestamps, pin state and image names are plaintext, as are `/api/info`, the page/scripts and authentication header. Local SQLite, originals and iCloud files have no application-level encryption; the browser stores the pairing code in localStorage.

Pairing codes use the OS cryptographic random generator: 16 characters sampled uniformly from 94 printable non-space ASCII characters, rejecting samples without uppercase, lowercase, digits or symbols. This provides about 104 bits of entropy against online and offline guessing. The existing online rate limit remains in place. HTTP still exposes the authentication token to capture/replay and does not protect page integrity. Use trusted local networks; do not describe this as encrypted storage or HTTPS-equivalent protection.

## Wire format

Sources: [WebSyncServer.swift](../Sources/PasteHistory/Infrastructure/Sync/WebSyncServer.swift) and [WebSyncPage.swift](../Sources/PasteHistory/Presentation/Sync/WebSyncPage.swift).

| Field | Contract |
| --- | --- |
| Pair code | 16 printable non-space ASCII characters; includes uppercase, lowercase, a digit and a symbol; percent-encoded in the URL fragment |
| `X-Pair-Token` | Lowercase hex SHA-256 of the UTF-8 code |
| Payload key | HKDF-SHA256 of the UTF-8 code, 32 bytes |
| HKDF salt / info | UTF-8 `PasteHistory-Pairing-v1` / `clip-payload` |
| Combined ciphertext | 12-byte nonce + ciphertext + 16-byte GCM tag |
| JSON `payload` | Base64 of the combined ciphertext |

| Route | Contract |
| --- | --- |
| `/`, `/index.html` | Public page; manifest/icons are public too |
| `GET /api/info` | Authenticated name, version, encryption marker and record count |
| `GET /api/clips` | Authenticated `{"clips":[...]}`, up to 300 entries with metadata and encrypted `payload` |
| `GET /api/image/<name>.png` | Authenticated combined ciphertext bytes, **without Base64** |
| `POST /api/clips` | Authenticated `{"payload":"<base64>"}`; page encrypts `{"text":"…","kind":"text","app":"…"}` |

Decrypted record fields may include `text`, `ocr`, `paths`, `app` and `thumb` (PNG Base64). Server-side upload parsing for other types is not a promise of corresponding phone UI support.

Routes run on `com.verdent.pastehistory.websync`, with a separate SQLite read connection. Uploads are decrypted there and queued to the main thread. **200 means accepted for processing, not persisted**; verify by reading the record back. Invalid authentication returns 401; ten failures within 60 seconds trigger shared service-wide 429 limiting, and successful authentication clears failures. Invalid upload JSON/ciphertext returns 400; missing routes/images return 404.

## iCloud files

[iCloudSync.swift](../Sources/PasteHistory/Infrastructure/Sync/iCloudSync.swift) exports records to `PasteHistory/clips/<uuid>.json`, deletions to `tombstones/` and originals to `images/`. Envelopes contain a source `machine` and `clip`, `deletedId` or `clearAll`. Deterministic filenames do not guarantee conflict-free concurrent edits.

Sync imports at startup, watches NSMetadataQuery changes, and reconciles every 60 seconds and when history opens. OCR travels with records; originals are separate files. It uses an available ubiquity container, falling back to `~/Library/Mobile Documents/com~apple~CloudDocs/PasteHistory/`. Default sync is enabled but inactive if no usable directory exists; the menu offers retry when inactive.

Deletion removes the record file and writes a tombstone. Remote cleanup and image restoration require active sync. File records contain paths only. iCloud is a synchronized copy, not an independent backup.

## Connection checks

1. Confirm the Mac is awake and the app running. Address discovery currently checks IPv4 on `en0` / `en1`.
2. Check network reachability, router client isolation, phone local-network permission and the Mac firewall.
3. Rescan the current QR code after rotation; allow the failure window to expire after 429 responses.
4. Check the local service, then test from the actual phone:

   ```sh
   curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8377/
   curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8377/apple-touch-icon.png
   ```

Local 200 responses do not prove phone access, valid pairing or successful ingestion. The pairing UI reports startup errors such as port conflicts; wake-from-sleep attempts to restart the listener.

## Crypto checks

Required after encryption changes. The pairing check uses isolated preferences and synthetic fixtures, extracts the actual page parser and pure-JS fallback, and compares them with Swift CryptoKit and Node crypto:

```sh
mkdir -p .build
swiftc Sources/PasteHistory/Infrastructure/Sync/WebSyncPairing.swift scripts/test_websync_pairing.swift -o .build/test-websync-pairing
.build/test-websync-pairing > .build/pairing-fixtures.json
node scripts/test_websync_pairing.mjs .build/pairing-fixtures.json
```

It covers generation, persistence, legacy migration, every printable symbol in a pairing URL, token/key agreement, payload interoperability and tampered tags. For broader encryption changes also check:

- Compare SHA-256, HMAC and HKDF with Node `crypto.createHash`, `createHmac` and `hkdfSync`; include leading-zero codes and Unicode.
- Check AES against FIPS-197 vectors and GCM against NIST vectors, then encrypt/decrypt both ways with Node AES-256-GCM.
- Include empty, 16-byte, 30-byte and large payloads; reject tampered ciphertext/tags. GHASH must pad ciphertext before appending the length block. Large Base64 conversions must remain chunked to avoid argument-count limits.
- With isolated test data, decrypt list/image responses, upload synthetic text, and poll until it is stored. A POST 200 alone is insufficient.
- Verify the pure-JS, paste-box, copy-failure and re-pairing paths on the actual phone HTTP origin.

For local diagnosis, `defaults read com.verdent.pastehistory webSyncPairCode` reveals a credential: keep it out of logs and PRs. Uploading to the real app creates history that may propagate to iCloud.
