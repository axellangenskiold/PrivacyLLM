# Privacy Policy — PrivacyLLM

_Last updated: 2026-06-11_

## The short version

We collect nothing. PrivacyLLM has no servers, no accounts, no analytics, and
no telemetry. Everything you type, every reply the model writes, and every
document you import stays on your device, stored encrypted.

## What the app does with your data

- **Conversations and documents** are processed by an AI model running
  entirely on your iPhone and stored locally using iOS Data Protection plus
  app-level encryption (keys live in your device's Keychain).
- **Voice input** is transcribed by iOS on-device speech recognition. Audio
  never leaves the phone.
- **Document indexing** uses Apple's on-device language tools. Your documents
  are never uploaded.

## The only network activity

1. **Model downloads.** When you choose to download a model, the app fetches
   weight files from huggingface.co. This is a plain file download; nothing
   about you or your usage is sent.
2. **Web search (off by default).** If you turn search on, the assistant may
   send short keyword queries to the search provider you select (DuckDuckGo
   by default). A visible indicator appears whenever this happens, and every
   query is listed in Settings → Privacy Activity. Your conversation text is
   never sent — only the distilled keywords.
3. **Apple system assets.** iOS may download Apple's language assets the
   first time you use dictation or document indexing. This is an operating
   system download from Apple and involves none of your content.

## What we collect

Nothing. We have no analytics SDKs, no advertising identifiers, no crash
reporting service, and no backend. Crash diagnostics collected by Apple's
MetricKit remain on your device and are never transmitted to us.

## Data retention and deletion

All data lives on your device. Delete any conversation or document in-app,
or use Settings → Data to clear everything. Deleting the app removes all of
its data.

## Contact

Questions: open an issue at https://github.com/axellangenskiold/PrivacyLLM
