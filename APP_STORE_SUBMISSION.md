# App Store Connect — New Version Submission (v1.1)

Copy-paste blocks for submitting the **update** in App Store Connect
(App Store → your app → **(+) Version or Platform**). Char limits are ASC's;
it shows a live counter as you paste. Fields marked **⟨fill in⟩** are personal
to you and can't be prefilled.

Current shipped version: **1.0 (build 1)**. This update: **1.1**.

---

## 0. Before you touch ASC (in Xcode)

- [ ] Bump **MARKETING_VERSION** `1.0` → **`1.1`** (target → General → Version).
- [ ] Bump **build number** `1` → **`2`** (CURRENT_PROJECT_VERSION / Build).
- [ ] Archive (Product → Archive, Release) and upload with the Organizer or
      `xcrun altool`/Transporter.
- [ ] Wait for the build to finish processing in ASC, then select it in the
      new version (below).

Nothing else in the project needs to change — no new permissions, no new
entitlements. (Dictation already declares mic + speech usage strings;
text-to-speech playback needs no permission.)

---

## 1. Version Information

### What's New in This Version  (≤4000)

```
NEW: Voice Memos & Podcasts
Turn any text, a PDF, or a whole conversation into audio you can listen to — generated entirely on your iPhone. Choose a voice quality, then play it back like a podcast, and it picks up right where you left off. Forwarded conversations are read back as a natural, two-voice exchange.

Better voice dictation
Dictation now stops on its own when you finish speaking, then shows what it heard with a Send button so you can review before sending.

NEW: Session Info
Open the ⋯ menu in any chat to see how much of the context window you're using, how many tokens you've used and generated, and how many web searches were made.

Smarter context
Each chat now sizes its memory to the model you're running, so longer conversations stay coherent.

As always: no cloud, no accounts, no tracking. Everything runs on your device.
```

### Promotional Text  (≤170, editable anytime without review)

```
New: turn any text, PDF, or conversation into podcast-style audio, generated entirely on your iPhone. Still no cloud, no accounts, no tracking — nothing leaves your device.
```

### Keywords  (≤100, comma-separated, no spaces)

```
offline,local,llm,on-device,assistant,pdf,tts,audio,voice,podcast,secure,encrypted,notracking
```

> Words already in the app name/subtitle (private, ai, chat) are indexed for
> free — don't repeat them.

### Description  (≤4000 — updated to include Voice Memos; paste the whole block)

```
PrivacyLLM is a complete AI assistant that runs entirely on your iPhone. No cloud. No accounts. No tracking. Your conversations, your documents, and the model's reasoning never leave your device — because there's no server for them to go to.

Most AI apps send everything you type to someone else's computers. PrivacyLLM is built on the opposite idea: a genuinely capable assistant can live in your pocket, with your data staying yours.

PRIVATE BY DESIGN
• The language model runs on your device's GPU. Your prompts are never sent to a cloud AI provider.
• Nothing to breach: we run no servers and store none of your data. There is no database of your conversations to be hacked, leaked, or subpoenaed — it doesn't exist.
• Works fully offline. Apart from optional web search, every feature works in airplane mode.
• No analytics, no ads, no telemetry of any kind. Our App Privacy label says it plainly: Data Not Collected.

WHAT IT DOES
• Chat with a fast, modern assistant — replies stream in token by token, with full Markdown and syntax-highlighted code.
• Fast and Thinking modes: switch between a quick model and a more deliberate one that shows its reasoning before it answers.
• Voice Memos & podcasts: turn any text, a PDF, or a whole conversation into audio and listen on-device — with playback that resumes right where you left off, and conversations read back in two voices.
• Chat with your PDFs: import a document and ask questions about it. The text is extracted and indexed on-device, and the answer tells you which section it came from.
• Optional web search: when you turn it on, only short keyword queries go to a privacy-respecting search engine (DuckDuckGo by default) — never your conversation. A clear indicator shows whenever a search goes out, and search is OFF by default.
• Voice input: dictate messages using Apple's on-device speech recognition. Dictation stops automatically when you finish, so you can review before sending. No audio ever leaves your phone.
• Session info: see your context-window usage, token counts, and web-search count for any chat.
• Multiple conversations, encrypted on disk with iOS Data Protection.

YOU'RE IN CONTROL
• Choose your model and download it once, directly to your device. You can even bring your own.
• Everything is stored locally and encrypted, readable only on your iPhone.
• Open and inspectable — you don't have to take our word for any of this.

PrivacyLLM is free, with no ads and no subscriptions.

Your AI assistant belongs where your data does: on your device, in your hands.

REQUIREMENTS
A recent iPhone with enough memory is recommended for the larger models. A network connection is needed only for the one-time model download and for optional web search.
```

> The description carries over from 1.0 with a Voice Memos bullet, an updated
> voice-input line, and a session-info line added. If you'd rather not
> re-submit the description for review, you can leave it unchanged — only
> **What's New** is required for an update.

### Screenshots / Preview

- [ ] Optional but recommended: add 1–2 screenshots showing **Voice Memos** and
      the **Session Info** sheet so the headline features are visible on the
      product page. Existing 6.5" (1242×2688) screenshots remain valid; you can
      regenerate with `Scripts/screenshots.sh`.
- Not required to change if you're happy with the current set.

### Support / Marketing / Privacy URLs  (carry over from 1.0)

- Support URL: **⟨fill in — same as 1.0⟩**
- Marketing URL (optional): **⟨fill in or leave blank⟩**
- Privacy Policy URL: **⟨fill in — host Docs/PRIVACY_POLICY.md; same as 1.0⟩**

### Version Release

- [ ] **Automatically release this version** after approval (recommended), or
      choose **Manually release** if you want to control the moment it goes live.
- [ ] Phased Release for automatic updates: **on** (recommended — rolls out over
      7 days, easy to pause if something's wrong).

---

## 2. App Review Information

### Sign-in required?

```
No — the app has no accounts, login, or credentials.
```

### Contact Information

- First / Last name: **⟨fill in⟩**
- Phone: **⟨fill in⟩**
- Email: **⟨fill in — e.g. axel@langenskiold.se⟩**

### Notes for Review  (paste)

```
PrivacyLLM is a private AI assistant that runs entirely on the user's iPhone. No account or login is required.

WHAT CHANGED IN THIS VERSION (1.1)
- New "Voice Memos" feature: the user can turn pasted text, an imported PDF, or a whole conversation into an audio file. All text-to-speech is generated on-device using Apple's AVSpeechSynthesizer; nothing is uploaded. Audio is stored locally and protected with iOS Data Protection.
- Voice dictation now auto-stops on a pause in speech and lets the user review the transcript before sending.
- A new "Session Info" sheet shows on-device context-window usage and token/web-search counts.
No new network access and no new permissions were added.

HOW TO REACH THE NEW FEATURE
1. Complete the brief onboarding and, on the model screen, download the recommended model over Wi-Fi (one-time, ~1.8 GB) — required before chatting.
2. On the main screen, tap the waveform button (next to New Chat) to open Voice Memos, then "+" to create one. Paste any text (or import a PDF), pick a voice quality, and tap Generate. The audio plays back in-app.
3. You can also open any chat's "..." menu → "Convert to Voice Memo".
4. Session Info: open any chat → "..." menu → "Session Info".

PRIVACY / EXTERNAL SERVICES (unchanged from 1.0)
- All AI inference and text-to-speech happen on-device. There is no third-party AI/LLM service, analytics, or backend.
- The only network activity is: (a) a one-time model-file download from Hugging Face (data, not code; no user data sent), and (b) optional, user-initiated web search via DuckDuckGo, which receives short keyword queries only — never conversation or document content. Web search is OFF by default and shows an on-screen indicator when used.
- This build contains NO in-app purchases.

Enabling Airplane Mode after the model is downloaded demonstrates that chat, document Q&A, voice memos, and dictation all work fully offline.
```

> Full background (devices tested, model licenses) is in
> `Docs/APP_REVIEW_NOTES.txt` if the reviewer asks — but note that file
> mentions optional tips; this build ships with **no in-app purchases**
> (`FeatureFlags.json → donations: false`), so don't reference tips in the
> notes above.

### Attachment (optional)

- Not needed. (Only add one if a reviewer specifically requests a demo video.)

---

## 3. Declarations you'll re-confirm each submission

- **Export Compliance / Encryption:** already answered by the build —
  `ITSAppUsesNonExemptEncryption = NO` is set in Info.plist, so ASC should not
  prompt. If it does: the app uses encryption = **Yes**; it qualifies for the
  **exemption** = **Yes** (only Apple CryptoKit + HTTPS/TLS — standard,
  exempt). No CCATS/year-end report needed.
- **Content Rights:** the app does **not** contain, show, or access
  third-party content in the binary. (Open-weights models are downloaded at
  runtime under permissive licenses, with attribution shown in-app — same as
  1.0.)
- **Advertising Identifier (IDFA):** **No** — the app does not use the
  advertising identifier.
- **Age Rating:** unchanged from 1.0 (no new content that affects it). Only
  revisit if ASC flags it.

---

## 4. Final submit checklist

- [ ] Build 1.1 (2) uploaded and selected for the version.
- [ ] What's New pasted.
- [ ] Promotional Text / Keywords / Description updated (or intentionally left
      as-is).
- [ ] Support & Privacy Policy URLs present.
- [ ] Review contact info filled in; Notes for Review pasted.
- [ ] Export compliance, content rights, IDFA answered.
- [ ] Release option chosen (automatic + phased recommended).
- [ ] **Add for Review → Submit.**
