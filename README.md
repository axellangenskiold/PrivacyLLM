# Local LLM

**A private AI assistant that runs entirely on your iPhone.**

Local LLM is a chat app powered by a small language model that runs directly on your device's GPU. There are no accounts, no cloud servers, and no third-party AI vendors. Your conversations, your documents, and the model's reasoning never leave your phone. The goal is simple: a genuinely private assistant that you fully own and control.

---

## The Goal

Most AI chat apps send everything you type to someone else's servers. Local LLM is built on the opposite premise — that a capable assistant can run on the phone in your pocket, with your data staying yours. It's designed for anyone who wants the usefulness of a modern chat assistant without handing their private thoughts, questions, and files to a company in the cloud.

---

## How It Works

**On-device inference.** A small, quantized model (in the 1–3B parameter range) runs locally on Apple Silicon using the GPU. Responses stream in token by token, just like a cloud assistant — except the computation happens entirely on your device.

**Fast and Thinking modes.** Switch between a lightweight model for quick replies and a larger, more deliberate model for harder questions — a single toggle, much like turning extended reasoning on and off.

**Optional web search.** Sometimes an answer needs current information. When you explicitly enable search, the app uses the device's built-in browser engine to fetch results from a privacy-respecting search engine (DuckDuckGo by default). Only a short search query — keywords, never your conversation — leaves the device. The local model reads the results and writes the answer. A clear indicator appears whenever a search goes out, so nothing ever leaves silently. Search is **off by default**.

**Chat with your documents.** Import a PDF and ask questions about it. The text is extracted, broken into sections, and indexed entirely on-device using Apple's built-in language tools — so your documents are never uploaded anywhere. The model answers from the relevant sections and tells you which part it drew from.

**Voice input.** Tap the mic and speak. Your speech is transcribed to text on-device using Apple's on-device speech recognition, then sent as your message — no audio is sent to any server.

---

## Why It's Secure

Local LLM's privacy isn't a setting you trust us to honor — it's a consequence of how the app is built.

- **There's nothing to breach.** We run no servers and store none of your data. There is no central database of conversations to be hacked, leaked, or subpoenaed, because it doesn't exist. Your data lives only on your device.

- **No AI vendors in the loop.** The model runs locally. Your prompts are never sent to OpenAI, Google, or any other provider. No one on the outside ever sees what you ask.

- **Minimal, visible egress.** The only things that ever leave your device are (1) optional web-search keywords, and only when *you* turn search on, and (2) the one-time download of the model itself. Everything else — your messages, your documents, the model's thinking, and the embeddings derived from your files — stays on the phone. When a search does go out, you see it happen.

- **Encrypted at rest.** Conversations, imported documents, and settings are stored using iOS Data Protection, encrypted on disk and tied to your device.

- **No tracking, ever.** No analytics, no advertising SDKs, no remote crash reporting, no telemetry of any kind. The app's privacy disclosure reflects this honestly: we collect nothing.

- **Works fully offline.** Apart from optional search, every feature works in airplane mode — proof that your data has nowhere to go.

- **Open and inspectable.** The source is open, so you don't have to take any of this on faith. You can read exactly what the app does.

---

## Features

- On-device LLM chat with streaming responses
- Fast / Thinking model toggle
- Optional, user-controlled web search with source citations
- PDF import and on-device document Q&A
- On-device voice-to-text input
- Multiple conversations, locally and securely stored
- Fully functional offline
- Zero telemetry

---

## Requirements

- iPhone with Apple Silicon (recent device with sufficient RAM recommended for the larger model)
- iOS 17 or later
- A network connection is needed only for the initial model download and for optional web search

---

## Built With

Swift · SwiftUI · on-device LLM runtime (Metal-accelerated) · PDFKit · NaturalLanguage (on-device embeddings) · Speech (on-device recognition) · CryptoKit & iOS Data Protection

---

## License

Apache-2.0 *(intended; subject to confirmation)*

---

*Local LLM keeps your AI assistant where it belongs — in your hands, on your device.*
