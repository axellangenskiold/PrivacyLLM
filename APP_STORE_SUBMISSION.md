# App Store Connect — New Version Submission (v1.2)

Copy-paste blocks for submitting the update in App Store Connect
(App Store → your app → **(+) Version or Platform**). Char limits are ASC's.
Fields marked **⟨fill in⟩** are personal to you and can't be prefilled.

Shipped so far: **1.0**, then **1.1**. This update: **1.2 (build 3)**.

---

## 0. Before you touch ASC

Already done in the repo (commit on `main`):

- [x] `MARKETING_VERSION` → **1.2** on the app **and** the widget target.
- [x] `CURRENT_PROJECT_VERSION` → **3** on both. Deliberately skipping 2 in case
      1.1 shipped as build 2 — build numbers must increase, not be contiguous.
      **Check ASC's build list first**; if 3 is taken, go higher.

New this version and worth knowing before you archive:

- **New target: `PrivacyLLMWidgets`** (bundle id `com.axellangenskiold.PrivacyLLM.Widgets`).
  First archive registers the App ID under automatic signing. If it fails,
  Xcode → Settings → Accounts → Download Manual Profiles, then retry.
- **Four new permission prompts**: Calendar (write-only), Reminders, Face ID,
  Notifications. Usage strings for the first three are in the build settings;
  notifications need none.
- **No new entitlements.** Background downloads use a background `URLSession`,
  which needs no `UIBackgroundModes`. Only the existing increased-memory-limit
  entitlement is present.

---

## 1. Version Information

### What's New in This Version  (≤4000)

```
NEW: Your assistant can do things now
Ask it to add a calendar event, set a reminder, or start a call or text. Everything happens on your iPhone, and iOS still asks you before anything is dialled or sent. Off by default — turn it on in Settings.

NEW: It remembers you
The assistant can save a handful of short facts about you and use them in every chat. You can read them, delete them, or switch the whole thing off in Settings.

NEW: More models, always current
The model list now updates itself from Hugging Face, so new models appear without waiting for an app update.

NEW: Home screen widget, Face ID, and search
Add a widget for one-tap access. Lock the app behind Face ID. Search across every chat you've had.

Cooler and faster
The app now frees the model when you stop chatting and eases off when your iPhone gets warm — less heat, better battery. Downloads keep going after you close the app, and replies can finish in the background and notify you.

Shorter answers, cleaner chats
Replies are much more concise. You can clear a chat's context without losing the conversation, and delete several chats at once.

Fixed: imported PDFs are now actually used when answering. Sorry about that one.

As always: no cloud, no accounts, no tracking.
```

### Promotional Text  (≤170, editable anytime without review)

```
New: your assistant can add calendar events, set reminders and start calls — all on your iPhone. Plus a widget, Face ID, chat search, and a model list that stays current.
```

### Keywords  (≤100, comma-separated, no spaces)

```
offline,local,llm,on-device,assistant,pdf,calendar,reminders,widget,faceid,secure,notracking,voice
```

> Words already in the app name/subtitle (private, ai, chat) are indexed for
> free — don't repeat them.

### Description  (≤4000 — full replacement)

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
• Gets things done: add a calendar event, set a reminder, or start a call or text, just by asking. Off by default, and iOS confirms before anything is dialled or sent.
• Remembers you: a few short facts, used in every chat, visible and deletable in Settings.
• Chat with your PDFs: import a document and ask questions about it. The text is extracted and indexed on-device, and the answer tells you which section it came from.
• Voice Memos & podcasts: turn any text, a PDF, or a whole conversation into audio and listen on-device, with playback that resumes where you left off.
• Optional web search: when you turn it on, only short keyword queries go to a privacy-respecting search engine (DuckDuckGo by default) — never your conversation. Search is OFF by default.
• Voice input: dictate messages using Apple's on-device speech recognition. No audio ever leaves your phone.
• Search every chat, clear a chat's context without losing it, and see your context and token usage any time.

YOU'RE IN CONTROL
• Choose your model and download it once, directly to your device. The list stays current, and you can bring your own.
• Lock the app behind Face ID. Add a home screen widget for one tap in.
• Everything is stored locally and encrypted, readable only on your iPhone.
• Open and inspectable — you don't have to take our word for any of this.

PrivacyLLM is free, with no ads and no subscriptions.

Your AI assistant belongs where your data does: on your device, in your hands.

REQUIREMENTS
A recent iPhone with enough memory is recommended for the larger models. A network connection is needed only for the one-time model download and for optional web search.
```

### Screenshots / Preview

- Existing 6.5" (1242×2688) screenshots stay valid — **do not** upload 6.9"
  1320×2868; ASC rejected those for this app.
- Recommended but optional: regenerate with `Scripts/screenshots.sh` and add
  shots of the widget and Device Actions.

### Support / Marketing / Privacy URLs  (carry over)

- Support URL: **⟨fill in — same as 1.1⟩**
- Marketing URL (optional): **⟨fill in or leave blank⟩**
- Privacy Policy URL: **⟨fill in — same as 1.1⟩**

### Version Release

- [ ] **Automatically release after approval** (recommended), with **Phased
      Release on** — 7-day rollout, pausable.

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
PrivacyLLM is a private AI assistant that runs entirely on the user's iPhone. No account or login is required. All AI inference happens on-device; there is no third-party AI service, no analytics, and no backend.

WHAT CHANGED IN 1.2

1) DEVICE ACTIONS (new permissions). The assistant can add a calendar event, add a reminder, or open the dialler/Messages with a number the user asked for. This is OFF by default and must be enabled in Settings > Device > Device Actions. Calendar access is WRITE-ONLY (the app never reads existing events). Calls and texts are handed to iOS via tel: and sms: URLs, so the system asks the user to confirm before anything is dialled or sent — the app cannot place a call on its own.

2) USER MEMORY. The assistant can save up to 12 short facts about the user (max 140 characters each) and include them in later chats. Stored on-device only, listed in Settings > Memory, individually deletable, and switchable off.

3) MODEL LIST FROM HUGGING FACE. The model catalog can be refreshed from Hugging Face's public listing (Models > ... > Refresh from Hugging Face). This only ever happens when the user taps it. Only model metadata is requested; no user data is sent. The list is filtered to quantized text-generation models that fit a phone, and repos whose names indicate safety-stripped conversions (uncensored, abliterated, unfiltered, NSFW) are excluded. Downloaded files are model weights — data, not executable code — as in 1.0 and 1.1.

4) HOME SCREEN WIDGET (new app extension, com.axellangenskiold.PrivacyLLM.Widgets). It deliberately displays no conversation content, since widgets render on the lock screen. It is a launcher.

5) FACE ID (new permission). Optional app lock with the device passcode as fallback. Nothing biometric is stored or transmitted; it uses LocalAuthentication only.

6) NOTIFICATIONS (new permission). A local notification when a reply finishes while the user is out of the app. Local only — the app never registers with APNs and has no push server.

7) BACKGROUND DOWNLOADS. Model weights now transfer on a background URLSession so a large download survives leaving the app. No new background modes were added.

HOW TO REACH THE NEW FEATURES
1. Complete the brief onboarding (it is skippable) and download the recommended model over Wi-Fi (one-time, ~1.8 GB) — required before chatting.
2. Device actions: Settings > Device > turn on Device Actions. Then in a chat ask "add a dentist appointment tomorrow at 3pm". iOS will prompt for calendar permission the first time.
3. Memory: tell the assistant something about yourself ("I live in Stockholm"), then open Settings > Memory to see and delete what it saved.
4. Model list: Models > "..." > Refresh from Hugging Face.
5. Widget: long-press the home screen > add PrivacyLLM.
6. Face ID: Settings > Device > Require Face ID.

PRIVACY / EXTERNAL SERVICES
The only network activity is: (a) model file downloads and the model-list refresh from huggingface.co (no user data sent), and (b) optional, user-initiated web search via DuckDuckGo, which receives short keyword queries only — never conversation or document content. Search is OFF by default and shows an on-screen indicator when used. In-app feedback opens a prefilled GitHub issue or a prefilled email in the user's own apps; the app sends nothing itself.

This build contains NO in-app purchases.

Enabling Airplane Mode after the model is downloaded demonstrates that chat, document Q&A, voice memos, and dictation all work fully offline.
```

---

## 3. Declarations to re-confirm

- **Export Compliance:** `ITSAppUsesNonExemptEncryption = NO` is set, so ASC
  should not prompt. If it does: uses encryption = **Yes**, qualifies for
  **exemption** = **Yes** (Apple CryptoKit + HTTPS only).
- **App Privacy label:** unchanged — **Data Not Collected**. Nothing new
  collects anything. Feedback hands text to GitHub or Mail on a user tap; the
  model-list refresh sends no user data.
- **Content Rights:** the binary contains no third-party content. Model weights
  download at runtime under permissive licences, attributed in-app.
- **IDFA:** No.
- **Age Rating:** unchanged from 1.1. Only revisit if ASC flags it.

---

## 4. Submit checklist

- [ ] Build number is higher than anything already in ASC.
- [ ] Archive uploaded and processed, then selected for the version.
- [ ] What's New pasted.
- [ ] Promotional Text / Keywords / Description updated.
- [ ] Support & Privacy Policy URLs present.
- [ ] Review contact filled in; Notes for Review pasted.
- [ ] Export compliance, content rights, IDFA answered.
- [ ] Release option chosen (automatic + phased).
- [ ] **Add for Review → Submit.**
