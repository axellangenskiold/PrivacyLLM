# Network Egress Audit Runbook (TR-19/20/21) — Release Gate

Run this before every release. The result must be: **zero unexpected
outbound traffic**.

## Setup

1. Install [mitmproxy](https://mitmproxy.org) (`brew install mitmproxy`) and
   run `mitmweb` on the Mac.
2. On the iPhone: Settings → Wi-Fi → your network → Configure Proxy → Manual,
   host = Mac's IP, port = 8080. Install the mitmproxy CA via http://mitm.it
   and trust it (Settings → General → About → Certificate Trust Settings).
   - Note: HTTPS bodies for hosts using certificate pinning won't decrypt;
     hostnames are still visible, which is what this audit needs.
3. Build and install a Release configuration of the app on the device.

## Pass 1 — search OFF (default state)

Exercise everything: onboarding, download a model, chat (several turns, both
Fast and Thinking), regenerate, edit-and-rerun, import a PDF and ask about
it, dictate a message, open every settings screen.

**Expected traffic — nothing else is acceptable:**

| Host pattern | Cause | When |
|---|---|---|
| `huggingface.co`, `cdn-lfs*.huggingface.co`, `*.hf.co` CDN hosts | model weight download | only during a user-initiated download |
| `*.apple.com` / `*.aaplimg.com` / Apple CDN | OS asset downloads (speech/embedding models), OS background services | OS-initiated; not app content |

Anything containing conversation text, document text, or identifiers beyond
the plain file-download requests is a release blocker (PR-1/2/4).

## Pass 2 — search ON

Turn the search toggle on, ask something that triggers a search.

- Confirm traffic goes **only** to the selected provider
  (`html.duckduckgo.com` or `www.mojeek.com`).
- Inspect the request: the query string must contain **only the model's
  keywords** (PR-3) — never message or document text verbatim beyond those
  keywords.
- Confirm the in-app orange egress banner appeared during the request
  (TR-22) and the query is listed in Settings → Privacy Activity.

## Pass 3 — offline (TR-20, NFR-10)

Airplane mode on. Verify: chat with a downloaded model, stop/regenerate,
PDF import + document Q&A (assets already downloaded), dictation, settings,
export. All must work. Search must fail gracefully with the local-fallback
notice (FR-22).

## Pass 4 — data at rest (TR-21)

1. With Xcode: Window → Devices → app → Download Container.
2. Inspect `AppSupport/Database/app.sqlite` with `strings` / a hex viewer:
   conversation text, document text, titles, and egress-log details must NOT
   be readable (they are AES-GCM blobs). Structural metadata (timestamps,
   UUIDs, role names) being visible is expected.
3. Confirm model weights live under `Models/` and the directory is excluded
   from backup (`xattr` shows no backup flag is not inspectable directly;
   verify via an encrypted iTunes/Finder backup not containing the weights).

## Sign-off

| Date | Build | Pass 1 | Pass 2 | Pass 3 | Pass 4 | Auditor |
|---|---|---|---|---|---|---|
| | | | | | | |
