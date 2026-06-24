# App Store Listing — copy to paste into App Store Connect

Char limits are App Store Connect's; counts below are approximate — ASC shows
the live count as you paste.

## App Name (≤30)

```
PrivacyLLM: On-Device AI
```

> The draft in APP_STORE.md ("PrivacyLLM — Private On-Device AI") is 33 chars —
> over the 30 limit. Use the above (24), or just `PrivacyLLM` and let the
> subtitle carry the pitch.

## Subtitle (≤30)

```
Private AI chat, on-device
```

## Promotional text (≤170, editable anytime without review)

```
Your AI assistant, running entirely on your iPhone. No cloud, no accounts, no tracking — your chats, files, and the model's reasoning never leave your device.
```

## Keywords (≤100, comma-separated, no spaces)

Default (no third-party trademarks — safest for review):

```
offline,local,llm,on-device,assistant,chatbot,pdf,document,secure,encrypted,notracking,smart,notes
```

Words already in the name/subtitle (private, ai, chat) are indexed for free —
don't repeat them here.

Aggressive variant (adds model/competitor terms — higher install intent, but
Apple can reject keywords that reference third-party trademarks; "Llama" and
"Gemma" are defensible since the app actually runs them, "gpt" is borderline):

```
offline,local,llm,on-device,gpt,llama,gemma,assistant,pdf,document,secure,encrypted,notracking
```

## Description (≤4000)

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
• Chat with your PDFs: import a document and ask questions about it. The text is extracted and indexed on-device, and the answer tells you which section it came from.
• Optional web search: when you turn it on, only short keyword queries go to a privacy-respecting search engine (DuckDuckGo by default) — never your conversation. A clear indicator shows whenever a search goes out, and search is OFF by default.
• Voice input: dictate messages using Apple's on-device speech recognition. No audio ever leaves your phone.
• Multiple conversations, encrypted on disk with iOS Data Protection.

YOU'RE IN CONTROL
• Choose your model and download it once, directly to your device. You can even bring your own.
• Everything is stored locally and encrypted, readable only on your iPhone.
• Open and inspectable — you don't have to take our word for any of this.

PrivacyLLM is free, with no ads and no subscriptions. If you'd like to support development there's an optional tip jar, but every feature is available to everyone, always.

Your AI assistant belongs where your data does: on your device, in your hands.

REQUIREMENTS
A recent iPhone with enough memory is recommended for the larger models. A network connection is needed only for the one-time model download and for optional web search.
```

## What's New (release notes, ≤4000) — for 1.0

```
The first release of PrivacyLLM. A private AI assistant that runs entirely on your iPhone — chat, document Q&A, optional web search, and voice input, all on-device. Nothing leaves your phone.
```

## Notes / review risks

- "Open and inspectable" assumes the source stays public (Apache-2.0). Drop the
  line if the repo goes private before launch.
- Avoided naming competitor apps in the description (says "a cloud AI provider").
  Keep it that way to dodge guideline 2.3.7 metadata rejections.
- Privacy policy URL still needs hosting (Docs/PRIVACY_POLICY.md) — required field.
