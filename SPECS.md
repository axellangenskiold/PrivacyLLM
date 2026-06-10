# Local LLM — Product & Engineering Specification

**Version:** 1.0 (draft for build)
**Platform:** iOS (iPhone)
**Document purpose:** Complete, build-ready specification for an AI coding agent or engineering team to implement a privacy-first, on-device LLM chat application. Requirements are tagged with stable IDs and MoSCoW priority (**MUST** / **SHOULD** / **COULD**). Items needing a human decision are collected in §15 (Open Decisions) and cross-referenced inline as `[see OD-n]`.

---

## 1. Product Overview

### 1.1 Vision
A native iOS chat app that runs a small language model entirely on the device's GPU. Everything the user types, the model's reasoning, and any documents the user adds stay on the device. The only data that ever leaves the phone is an optional, user-toggled web-search query (keywords only), and only when search is explicitly enabled.

### 1.2 Core Principles (non-negotiable)
1. **On-device by default.** Inference, embeddings, speech-to-text, and storage are all local. No conversation content is transmitted to any server, ever.
2. **No third-party AI vendors.** No OpenAI, Google, Anthropic, or other hosted-model APIs.
3. **No backend owned by us.** No servers to host, no recurring infrastructure cost. Model weights are pulled directly from a public model host (e.g. Hugging Face) on first run.
4. **Transparent egress.** Any time data leaves the device (web search only), the UI visibly signals it. Nothing leaves silently.
5. **No telemetry.** No analytics SDKs, no remote crash reporting, no tracking.

### 1.3 Goals
- Fluid local chat with token streaming on modern iPhones.
- Toggle between a "fast" model and a "thinking" model `[see OD-2]`.
- Optional web search via the on-device browser engine, fully under user control.
- Add PDFs and ask questions against them (lightweight on-device retrieval).
- Voice input via on-device speech recognition.

### 1.4 Non-Goals (v1)
- Images/video as input or in documents (PDF text only).
- Multi-device sync / accounts / cloud backup of chats.
- Android, iPad-optimized, or macOS builds (iPhone-first; iPad may run unmodified).
- Image generation.
- A custom-hosted search backend.

### 1.5 Target Audience
Both privacy-conscious technical users (who value open source, configurability, and the "nothing leaves the device" guarantee) and general users who simply want a private assistant. The UI must be approachable by default while exposing depth in settings.

---

## 2. Glossary

| Term | Meaning |
|---|---|
| **Inference** | Running the LLM to generate tokens from a prompt. |
| **GGUF** | Quantized model file format used by llama.cpp. |
| **MLX** | Apple's array/ML framework optimized for Apple Silicon. |
| **Quantization** | Compressing model weights (e.g. 4-bit) to reduce size/memory. |
| **RAG** | Retrieval-Augmented Generation: fetch relevant text chunks and add them to the prompt. |
| **Chunk** | A segment of a document used for retrieval. |
| **Embedding** | A numeric vector representing text meaning, used for similarity search. |
| **Tool call** | A structured request emitted by the model to invoke a capability (e.g. web search). |
| **Jetsam** | iOS's mechanism for terminating apps that exceed memory limits. |
| **Fast model** | A small, low-latency model for quick replies. |
| **Thinking model** | A model (or mode) that produces longer, more deliberate reasoning. |

---

## 3. System Architecture

### 3.1 Architectural Style
Native Swift, SwiftUI, **MVVM** for the presentation layer, with a clean separation between UI, orchestration, capability services, and data. All capability services sit behind protocols so implementations can be swapped (e.g. inference backend) and unit-tested with mocks.

### 3.2 Layers

```
┌─────────────────────────────────────────────────────────────┐
│  Presentation Layer (SwiftUI Views + ViewModels, MVVM)       │
│  Chat · Conversation List · Model Manager · Documents ·      │
│  Settings · Onboarding                                       │
├─────────────────────────────────────────────────────────────┤
│  Orchestration Layer                                         │
│  ChatOrchestrator · AgentLoop · ToolRouter · PromptBuilder   │
├─────────────────────────────────────────────────────────────┤
│  Capability Services (protocol-backed)                       │
│  InferenceService · ModelManager · SearchService ·           │
│  DocumentService(RAG) · VoiceService                         │
├─────────────────────────────────────────────────────────────┤
│  Data Layer                                                  │
│  PersistenceStore · EncryptionManager · SettingsStore ·      │
│  ModelStore (weights on disk)                                │
├─────────────────────────────────────────────────────────────┤
│  OS / Platform Integrations                                  │
│  MLX (or llama.cpp+Metal) · PDFKit · NLContextualEmbedding · │
│  SFSpeechRecognizer · WKWebView/URLSession · CryptoKit       │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Module Responsibilities

- **ChatOrchestrator** — Owns a conversation's lifecycle. Assembles the prompt (system prompt + history + retrieved context + tool results), drives the inference stream, and persists messages.
- **AgentLoop / ToolRouter** — Detects tool calls in model output, dispatches them (currently: web search, plus simple local tools), injects results back into the context, and resumes generation. Bounded by a max-iterations guard.
- **PromptBuilder** — Applies the correct chat template per model, manages context-window budgeting (truncation/summarization of old turns), and injects retrieved document chunks and search results.
- **InferenceService** (protocol) — Loads a model, streams tokens, supports stop/cancel, exposes sampling params (temperature, top-p, max tokens). Default implementation: MLX Swift `[see OD-1]`.
- **ModelManager** — Lists catalog models, downloads weights with progress + resume, verifies integrity (checksum), stores/deletes them, tracks the active "fast" and "thinking" selections, and reports on-disk/in-memory footprint.
- **SearchService** — Gated by the search toggle. Builds a query string, fetches results from a privacy search engine via URLSession (HTML endpoint) or WKWebView fallback, parses results into title/snippet/URL, returns top-N. Emits an egress event for the UI indicator.
- **DocumentService (RAG)** — Imports PDFs (PDFKit text extraction), chunks text, generates embeddings (NLContextualEmbedding), stores vectors, and retrieves top-k chunks for a query via cosine similarity.
- **VoiceService** — On-device speech-to-text via SFSpeechRecognizer (`requiresOnDeviceRecognition = true`); streams partial transcripts; returns final text.
- **PersistenceStore / EncryptionManager** — Local encrypted storage of conversations, messages, document index, and settings. Data Protection (`NSFileProtectionComplete`) + Keychain-held keys.

### 3.4 Key Data Flows

**Standard chat turn**
1. User submits text (typed, or voice → text via VoiceService).
2. ChatOrchestrator → PromptBuilder assembles context (system prompt + recent history + any retrieved doc chunks).
3. InferenceService streams tokens → UI renders incrementally.
4. Message pair persisted to encrypted store.

**Search-augmented turn** (only if search toggle ON)
1. Model emits a search tool call → ToolRouter validates the toggle.
2. SearchService fires the query → **egress indicator activates** → results parsed.
3. Results injected into context → InferenceService resumes generation, citing sources.
4. If search fails (network/CAPTCHA/parse error), model is told retrieval failed and answers from its own knowledge with a visible "couldn't fetch live results" note.

**Document Q&A (RAG)**
1. User imports a PDF → DocumentService extracts + chunks + embeds + stores.
2. On a query, the query is embedded → cosine similarity → top-k chunks → injected into context (or, for a short doc that fits the context window, the whole text is injected and retrieval is skipped).

### 3.5 Tech Stack
- **Language:** Swift 5.9+ (Swift 6 concurrency where practical).
- **UI:** SwiftUI; Combine/async-await for streaming.
- **Inference:** MLX Swift (primary) `[see OD-1]`; abstracted behind `InferenceService` so llama.cpp/Metal can be substituted.
- **PDF:** PDFKit (built-in).
- **Embeddings:** NLContextualEmbedding (iOS 17+, built-in, 0 MB) `[see OD-3]`.
- **Speech:** Speech framework / SFSpeechRecognizer (built-in).
- **Search fetch/parse:** URLSession + SwiftSoup (HTML parsing); WKWebView fallback.
- **Persistence:** SQLite via GRDB **or** SwiftData `[see OD-4]`; CryptoKit + Data Protection for encryption.
- **Crash/metrics:** MetricKit (on-device only).

---

## 4. Functional Requirements

### 4.1 Chat
- **FR-1 (MUST)** Send a text message and receive a streamed token-by-token response.
- **FR-2 (MUST)** Stop/cancel an in-progress generation immediately.
- **FR-3 (MUST)** Regenerate the last response.
- **FR-4 (SHOULD)** Edit a previous user message and re-run from that point.
- **FR-5 (MUST)** Render Markdown in responses (headings, lists, bold, links) and syntax-highlighted code blocks with a copy button.
- **FR-6 (MUST)** Maintain multiple independent conversations: create, rename, delete.
- **FR-7 (MUST)** Persist conversations across app launches (encrypted, local).
- **FR-8 (SHOULD)** Per-conversation and global system-prompt/persona customization.
- **FR-9 (COULD)** Branch a conversation from any message.
- **FR-10 (MUST)** Copy any message to clipboard; share/export a conversation (e.g. Markdown/plain text) via the share sheet.

### 4.2 Model Management
- **FR-11 (MUST)** Display a catalog of supported models with size, parameter count, quantization, RAM requirement, and license.
- **FR-12 (MUST)** Download a model with visible progress, pause/resume, and cancel.
- **FR-13 (MUST)** Verify downloaded model integrity (checksum/hash) and surface corruption.
- **FR-14 (MUST)** Delete a downloaded model to reclaim space.
- **FR-15 (MUST)** Switch the active model. Provide distinct **Fast** and **Thinking** selections and a one-tap toggle between them in the chat view `[see OD-2]`.
- **FR-16 (SHOULD)** Warn before loading a model the current device can't comfortably fit (RAM check).
- **FR-17 (SHOULD)** Show live memory footprint of the loaded model.

### 4.3 Web Search
- **FR-18 (MUST)** Global on/off toggle for web search. Default **OFF** (opt-in).
- **FR-19 (MUST)** When ON, the model can request a search; the app constructs the query, fetches, parses, and feeds results back for the model to answer from.
- **FR-20 (MUST)** Display source attributions (title + link) for any search-derived answer.
- **FR-21 (MUST)** A visible, unmistakable indicator whenever a query leaves the device.
- **FR-22 (MUST)** Graceful failure: on any search error, fall back to local-only answer with a clear notice.
- **FR-23 (SHOULD)** User-selectable search provider (default: DuckDuckGo HTML endpoint) `[see OD-5]`.
- **FR-24 (COULD)** Per-message "search this" override even when the global toggle is off (explicit one-time consent).

### 4.4 Documents (Lightweight RAG)
- **FR-25 (MUST)** Import a PDF via Files/share sheet.
- **FR-26 (MUST)** Extract text (PDFKit), chunk, embed, and index locally.
- **FR-27 (MUST)** Ask questions answered from imported documents; cite which document/section was used.
- **FR-28 (MUST)** List, and delete, imported documents (deleting also purges its index).
- **FR-29 (SHOULD)** Enforce a per-document and total-corpus size/page cap with a clear message when exceeded.
- **FR-30 (SHOULD)** Attach a document to a specific conversation or make it globally available `[see OD-6]`.
- **FR-31 (MUST)** Reject non-PDF and image-only/scanned PDFs gracefully (no OCR in v1) with an explanatory message.

### 4.5 Voice Input
- **FR-32 (MUST)** Mic button that captures speech and transcribes to text on-device.
- **FR-33 (MUST)** Show a live partial transcript while speaking.
- **FR-34 (MUST)** Place final transcript into the input field for review/edit before sending (do not auto-send by default).
- **FR-35 (MUST)** Handle microphone/speech permission states (request, denied, restricted) with clear guidance.
- **FR-36 (COULD)** Hands-free mode: auto-send on end-of-speech detection (user-enabled).

### 4.6 Settings
- **FR-37 (MUST)** Privacy controls: search toggle, search provider, "what leaves the device" explainer.
- **FR-38 (MUST)** Model controls: active fast/thinking models, sampling params (temperature, top-p, max tokens), context length.
- **FR-39 (SHOULD)** Appearance: light/dark/system, text size respecting Dynamic Type.
- **FR-40 (SHOULD)** Data controls: clear all conversations, clear document index, reset app.
- **FR-41 (MUST)** About: version, licenses, link to source repo `[see OD-7]`, privacy statement.

---

## 5. Non-Functional Requirements

### 5.1 Performance
- **NFR-1 (MUST)** First token latency for the Fast model ≤ ~1.5 s on the reference device after the model is loaded.
- **NFR-2 (SHOULD)** Sustained generation ≥ 8–15 tokens/sec for a ~1–3B 4-bit model on the reference device (device-dependent; treat as a target, validate empirically).
- **NFR-3 (MUST)** UI remains responsive (no main-thread blocking) during inference; streaming renders at a steady cadence.
- **NFR-4 (MUST)** Cold app launch to interactive chat ≤ 2 s (excluding first-ever model download).
- **NFR-5 (SHOULD)** Model load (disk → memory) progress is shown if it exceeds ~500 ms.

### 5.2 Memory & Resources
- **NFR-6 (MUST)** Stay within device memory limits; never crash from jetsam under normal use. Request the increased-memory-limit entitlement.
- **NFR-7 (MUST)** Unload the model from memory when appropriate (e.g. sustained background, memory-pressure warnings) and reload on demand.
- **NFR-8 (MUST)** Respond to `didReceiveMemoryWarning` / memory-pressure events by freeing caches.
- **NFR-9 (SHOULD)** Monitor thermal state; if `ProcessInfo.thermalState` is serious/critical, reduce load (e.g. throttle, suggest the Fast model) and inform the user.

### 5.3 Reliability
- **NFR-10 (MUST)** Fully functional offline for all non-search features (airplane mode).
- **NFR-11 (MUST)** Crash-free session rate ≥ 99.5% (measured locally via MetricKit; not transmitted).
- **NFR-12 (MUST)** Interrupted model downloads resume rather than restart.
- **NFR-13 (MUST)** Corrupt/partial model files are detected and re-downloadable.

### 5.4 Accessibility & UX Quality
- **NFR-14 (MUST)** Full VoiceOver support with sensible labels and reading order.
- **NFR-15 (MUST)** Dynamic Type support across all text.
- **NFR-16 (MUST)** Meet WCAG AA contrast in both light and dark themes.
- **NFR-17 (SHOULD)** Respect Reduce Motion.

### 5.5 Battery
- **NFR-18 (SHOULD)** Inference does not run in the background; generation pauses/cancels on backgrounding per iOS task rules.
- **NFR-19 (SHOULD)** Surface a subtle hint when heavy/long generations are likely to drain battery or heat the device.

### 5.6 Maintainability
- **NFR-20 (MUST)** Capability services behind protocols with mockable interfaces.
- **NFR-21 (SHOULD)** No business logic in views; ViewModels are independently testable.
- **NFR-22 (SHOULD)** Centralized configuration for model catalog and search providers (data-driven, not hardcoded throughout).

---

## 6. Privacy & Security Requirements

> This section is the heart of the product. Treat every item as load-bearing.

### 6.1 Data Handling
- **PR-1 (MUST)** No conversation content, document content, or derived embeddings are ever transmitted off-device.
- **PR-2 (MUST)** The **only** permitted outbound network traffic is: (a) web-search queries when the toggle is ON, and (b) model-weight downloads from the configured model host. Nothing else.
- **PR-3 (MUST)** Search queries contain only the model-distilled keywords, never the raw conversation or document text.
- **PR-4 (MUST)** Maintain a network egress allowlist; block/deny anything outside the search-provider domain(s) and the model-host domain(s). Verifiable in testing (§11.6).

### 6.2 Storage Security
- **PR-5 (MUST)** All persisted user data (conversations, messages, document index, settings) encrypted at rest using Data Protection (`NSFileProtectionComplete` or `CompleteUnlessOpen` as appropriate).
- **PR-6 (MUST)** Any encryption keys stored in the Keychain with appropriate accessibility (e.g. `WhenUnlockedThisDeviceOnly`); never in plaintext or UserDefaults.
- **PR-7 (SHOULD)** Exclude large model files from iCloud backup (set `isExcludedFromBackup`) to save user iCloud space; user data may be backed up per OS defaults but remains encrypted.
- **PR-8 (COULD)** Optional app-level lock (Face ID/Touch ID) to open the app `[see OD-8]`.

### 6.3 No Tracking
- **PR-9 (MUST)** No third-party analytics, advertising, attribution, or tracking SDKs of any kind.
- **PR-10 (MUST)** No remote crash reporting. Use MetricKit (on-device) only; reports are never auto-transmitted.
- **PR-11 (MUST)** App Privacy "nutrition label" reflects reality: no data collected/linked/tracked (aside from the user-initiated network actions, which are not collection by us).

### 6.4 Transparency
- **PR-12 (MUST)** A persistent, discoverable explanation of exactly what leaves the device and when.
- **PR-13 (MUST)** Real-time egress indicator (FR-21) any time a search fires.
- **PR-14 (SHOULD)** A simple "privacy activity" view listing recent outbound search events (local only).

### 6.5 Platform Security
- **PR-15 (MUST)** App Transport Security enforced (HTTPS only) for search and model downloads.
- **PR-16 (MUST)** Validate/parse all fetched HTML defensively; never execute fetched script in app context; WKWebView (if used for scraping) is isolated, non-persistent, and not exposed to the user as a browser.
- **PR-17 (MUST)** Request only the permissions actually needed (microphone/speech). No contacts, photos, location, etc. in v1.
- **PR-18 (MUST)** Verify integrity of downloaded model weights (hash) before loading (also a safety measure).

---

## 7. Model Requirements

- **MR-1 (MUST)** Support small instruction-tuned models in the chosen runtime format (MLX-converted, and/or GGUF) `[see OD-1]`.
- **MR-2 (MUST)** Ship with a curated catalog; do **not** bundle weights in the binary — download on first run `[see OD-9]`.
- **MR-3 (MUST)** Apply each model's correct chat/prompt template (templates differ per family).
- **MR-4 (MUST)** Default quantization 4-bit (quality/size sweet spot); expose alternatives where available.
- **MR-5 (MUST)** Define "Fast" vs "Thinking" behavior `[see OD-2]`. Until resolved, the spec assumes: **Fast** = a ~1B 4-bit model; **Thinking** = a larger ~3B (or reasoning-capable) model and/or a chain-of-thought prompt scaffold, selectable per message.
- **MR-6 (MUST)** Respect each model's license for redistribution/use and surface it to the user (FR-11). Llama/Gemma carry specific license terms; Qwen/others are typically Apache-2.0 — verify per model.
- **MR-7 (SHOULD)** Manage the context window: budget tokens, truncate or summarize old turns, reserve room for retrieved context and the response.
- **MR-8 (COULD)** Allow advanced users to import their own compatible model file `[see OD-10]`.

**Candidate models** (validate licenses and on-device performance before shipping each):

| Role | Candidates | ~Size (4-bit) | Min RAM (guide) |
|---|---|---|---|
| Fast | Llama 3.2 1B, Qwen2.5 0.5B/1.5B, SmolLM2 1.7B | ~0.4–1.1 GB | 4 GB |
| Thinking | Llama 3.2 3B, Qwen2.5 3B, Gemma 2 2B, Phi-3.5-mini | ~1.6–2.4 GB | 6 GB |

---

## 8. UI/UX Requirements

- **UX-1 (MUST)** Screens: Onboarding, Chat, Conversation List, Model Manager, Documents, Settings.
- **UX-2 (MUST)** Onboarding covers: privacy promise, first model download (with size + Wi-Fi recommendation), and permission priming for the mic (explain before the system prompt).
- **UX-3 (MUST)** Chat view: streaming responses, stop button, model/mode switcher, mic button, search toggle status, attach-document affordance.
- **UX-4 (MUST)** Clear visual states: empty, loading (model load / generating / searching / indexing), and error states for every async operation.
- **UX-5 (MUST)** The egress/search indicator is prominent and legible (e.g. an animated badge while a query is in flight).
- **UX-6 (SHOULD)** Distinct visual treatment for "thinking" output if a reasoning scaffold is shown (e.g. collapsible reasoning) `[see OD-2]`.
- **UX-7 (MUST)** Design works on the smallest supported iPhone screen and the largest, in light and dark.
- **UX-8 (SHOULD)** Approachable defaults with progressive disclosure of advanced settings.
- **UX-9 (SHOULD)** Haptics for key events (generation complete, error) respecting system settings.

*(When implementing the UI, follow the project's frontend-design guidance for typography, color, and a non-templated visual identity.)*

---

## 9. Data & Storage Requirements

- **DR-1 (MUST)** Schema (logical): Conversations, Messages (role, content, timestamp, model used, token counts, sources), Documents (metadata), DocumentChunks (text + embedding vector + ref), Settings.
- **DR-2 (MUST)** Store embedding vectors efficiently; for personal corpus sizes, brute-force cosine over in-memory/SQLite vectors is acceptable (no heavyweight vector DB) `[see OD-3]`.
- **DR-3 (MUST)** Model weights stored in app support/caches directory (not the binary), excluded from iCloud backup (PR-7).
- **DR-4 (MUST)** Migrations handled cleanly across app versions (no data loss on update).
- **DR-5 (SHOULD)** Enforce sane caps (max conversations retained, max document corpus) with user-facing controls to prune.

---

## 10. Tooling / Agent Layer Requirements

- **TL-1 (MUST)** A structured tool-call mechanism the model uses to request web search (and future tools). Parse tool calls reliably from model output; handle malformed calls.
- **TL-2 (MUST)** Bound the agent loop (max tool iterations per turn) to prevent runaway loops.
- **TL-3 (SHOULD)** Local-only utility tools (no egress): current date/time, simple calculator, unit conversion — useful and a safe pattern to validate tool-calling before search.
- **TL-4 (MUST)** Every tool that causes egress (search) re-checks the global toggle at call time, not just at prompt-build time.

---

## 11. Testing Requirements

### 11.1 Unit Tests
- **TR-1 (MUST)** PDF text extraction and chunking (boundaries, empty/short docs, very long docs).
- **TR-2 (MUST)** Embedding + cosine similarity ranking returns expected top-k on fixtures.
- **TR-3 (MUST)** Search-result HTML parsing against saved fixture pages (title/snippet/URL extraction), including malformed/empty results.
- **TR-4 (MUST)** Tool-call parsing: valid, malformed, and partial tool calls.
- **TR-5 (MUST)** Prompt construction / context budgeting / truncation logic.
- **TR-6 (MUST)** Encryption manager: data written is unreadable without keys; round-trip integrity.

### 11.2 Integration Tests
- **TR-7 (MUST)** End-to-end inference with a small test model: prompt in → tokens streamed → persisted.
- **TR-8 (MUST)** Full search pipeline with mocked network (fixture HTML) → results injected → answer with citations.
- **TR-9 (MUST)** Full RAG pipeline: import → index → query → correct chunk retrieved → answer cites source.
- **TR-10 (MUST)** Voice: mocked recognizer → transcript flows into input.

### 11.3 UI Tests (XCUITest)
- **TR-11 (MUST)** Core flows: onboarding + first model download (mocked), send a message, stop generation, switch model/mode, add a PDF and ask about it, toggle search, use the mic.
- **TR-12 (SHOULD)** Permission-denied paths (mic) show correct guidance.
- **TR-13 (SHOULD)** Empty/error/loading states render correctly.

### 11.4 Performance Tests
- **TR-14 (MUST)** Measure first-token latency and tokens/sec on the device matrix; assert against NFR targets (or record baselines and gate regressions).
- **TR-15 (MUST)** Measure peak memory during load + generation on the lowest-supported device; assert no jetsam.
- **TR-16 (SHOULD)** Model load time and app cold-start time baselines.

### 11.5 Device Matrix
- **TR-17 (MUST)** Test on at least: the lowest-supported device (RAM floor), a mid device, and a current flagship `[see OD-11]`. Real devices required for memory/perf/thermal — not just the simulator (the simulator does not represent Metal/GPU or memory limits accurately).
- **TR-18 (SHOULD)** Test under low-storage and low-memory conditions, and while thermally throttled.

### 11.6 Privacy & Security Tests (critical)
- **TR-19 (MUST)** **Network egress audit:** with a proxy/network monitor, exercise the full app with search OFF and confirm **zero** outbound traffic except model download. With search ON, confirm traffic goes only to the search-provider domain and contains only keywords (no conversation/document text). This is a release gate.
- **TR-20 (MUST)** Verify offline mode: all non-search features work in airplane mode.
- **TR-21 (MUST)** Verify data-at-rest encryption (inspect on-disk files; confirm not human-readable).
- **TR-22 (MUST)** Verify the egress indicator fires for, and only for, real search events.
- **TR-23 (SHOULD)** Static check: dependency manifest contains no analytics/tracking SDKs.

### 11.7 Accessibility Tests
- **TR-24 (MUST)** VoiceOver walkthrough of all core flows.
- **TR-25 (MUST)** Largest Dynamic Type size has no clipping/overlap; AA contrast verified.

### 11.8 Coverage & Beta
- **TR-26 (SHOULD)** Unit/integration coverage target ≥ 70% on non-UI logic.
- **TR-27 (MUST)** TestFlight beta across the device matrix before App Store submission.

---

## 12. Release & App Store Requirements

- **RR-1 (MUST)** Set deployment target and device floor `[see OD-11]` (note: NLContextualEmbedding requires iOS 17+; on-device LLM realistically needs a recent chip and ≥ 4–6 GB RAM).
- **RR-2 (MUST)** Add the increased-memory-limit entitlement (`com.apple.developer.kernel.increased-memory-limit`).
- **RR-3 (MUST)** Provide `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` purpose strings.
- **RR-4 (MUST)** Keep app binary small; models download post-install (RR via custom downloader; avoid shipping multi-hundred-MB binaries).
- **RR-5 (MUST)** Complete the App Privacy questionnaire accurately (no data collected by us; explain user-initiated network actions).
- **RR-6 (MUST)** **Export-compliance / encryption declaration:** the app uses encryption (Data Protection / CryptoKit / HTTPS). Provide the correct ITSAppUsesNonExemptEncryption value and any required documentation. (Standard OS crypto is typically exempt, but the declaration is mandatory — confirm classification.)
- **RR-7 (MUST)** App Store metadata: description, keywords, screenshots (light/dark), privacy policy URL `[see OD-12]`.
- **RR-8 (SHOULD)** Justify model-download-on-launch in review notes to avoid confusion (downloading data/weights, not executable code, is permitted).
- **RR-9 (SHOULD)** Versioning + release notes; semantic version scheme.
- **RR-10 (MUST)** Verify each shipped model's license permits redistribution/use in a published app (MR-6).

---

## 13. Build / DevOps Requirements

- **DO-1 (MUST)** Source control with a clear branching strategy; reproducible builds.
- **DO-2 (SHOULD)** CI (e.g. GitHub Actions) running unit/integration tests and a build on each PR.
- **DO-3 (SHOULD)** fastlane (or equivalent) for signing, TestFlight, and App Store deployment.
- **DO-4 (MUST)** Dependency manifest (Swift Package Manager) pinned to specific versions; license audit of every dependency.
- **DO-5 (SHOULD)** Linting/formatting (SwiftLint/SwiftFormat) in CI.
- **DO-6 (MUST)** No CI step that injects analytics/tracking; secrets (if any) never embedded in the app.

---

## 14. Dependencies & Licensing

- **Runtime:** MLX Swift (MIT) or llama.cpp (MIT) `[see OD-1]`.
- **HTML parsing:** SwiftSoup (MIT).
- **Persistence:** GRDB (MIT) or SwiftData (system) `[see OD-4]`.
- **System frameworks (no license concern):** PDFKit, NaturalLanguage (NLContextualEmbedding), Speech, WebKit, CryptoKit, MetricKit.
- **Models:** licensed individually — Llama (Llama Community License), Gemma (Gemma Terms), Qwen/SmolLM/Phi (commonly Apache-2.0/MIT) — **must be verified per model and surfaced in-app**.
- **App license:** `[see OD-7]` (open-source recommended; Apache-2.0 or MIT).

---

## 15. Open Decisions (need your input)

These genuinely change the build. I've stated a recommended default for each so work can proceed if you don't want to decide now — just confirm or redirect.

- **OD-1 — Inference engine.** *Recommend: MLX Swift* (Apple-native, clean Swift, great on Apple Silicon), abstracted so llama.cpp/GGUF can swap in later. Alternative: llama.cpp first for the widest model selection. **Which do you want as primary?**
- **OD-2 — "Fast" vs "Thinking" definition.** *Recommend:* two models (small fast + larger reasoning-capable), AND a chain-of-thought prompt mode you can toggle. Alternatives: (a) a single model with a reasoning-mode prompt only; (b) a single model that natively supports a thinking toggle. **Which model strategy?** This drives Model Manager and prompt design.
- **OD-3 — Embeddings approach.** *Recommend:* built-in NLContextualEmbedding (0 MB, iOS 17+). Alternative: a small bundled embedding model (~30–90 MB) for older iOS or higher quality. **Built-in only, or bundle a fallback?**
- **OD-4 — Persistence layer.** *Recommend:* GRDB + SQLite (control, easy encryption + vector storage). Alternative: SwiftData (simpler, less control). **Preference?**
- **OD-5 — Default search provider.** *Recommend:* DuckDuckGo HTML endpoint (most scrape-tolerant, no key, no cost). Note the ToS/fragility caveats. **OK as default? Want others selectable?**
- **OD-6 — Document scope.** Per-conversation documents, a global library, or both? *Recommend: both* (attach to a chat or mark global).
- **OD-7 — Open source & license.** Open-source the app? If so, which license (MIT vs Apache-2.0)? *Recommend: yes, Apache-2.0.*
- **OD-8 — App lock.** Include optional Face ID/Touch ID to open the app? *Recommend: yes, as an opt-in setting (COULD for v1).*
- **OD-9 — First-run model.** Download-on-first-run keeps the binary tiny but needs network at setup. *Recommend: download-on-first-run with a Wi-Fi prompt.* Alternative: bundle a tiny model for instant offline use at the cost of app size. **Which?**
- **OD-10 — Custom model import.** Allow advanced users to side-load their own compatible model file? *Recommend: yes, post-v1.*
- **OD-11 — Minimum iOS + device floor.** *Recommend:* iOS 17+ and a 6 GB-RAM-class device (e.g. iPhone 13 Pro / 14 Pro / 15-class A16+) for the Thinking model, with 1B-only support on 4 GB devices. **Confirm your minimum supported device/OS** — this sets the test matrix and who can install.
- **OD-12 — Distribution & monetization.** Free, free-and-open-source, or paid? Any in-app purchase? (You said no cost/hosting for *you* — this is about whether *users* pay.) *Recommend: free; optional paid tier only if you later add cost-bearing features.*

---

## 16. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Search scraping breaks (layout change, CAPTCHA, rate limit) | Search feature degrades | Robust parser + fixtures; graceful local-only fallback; selectable provider; consider Brave API as paid fallback. |
| Memory/jetsam on smaller devices | Crashes | RAM-gated model choices; increased-memory entitlement; unload on pressure; real-device testing. |
| Performance below expectation on older chips | Poor UX | Default to Fast/1B model; benchmark on the device floor; set expectations in onboarding. |
| Model license restricts redistribution | Legal/store risk | Verify each model's license; download from official host; surface license in-app. |
| App Review confusion over model download | Rejection/delay | Review notes clarifying weights are data, not code; nutrition label accurate. |
| Thermal throttling on long generations | Slowdown/heat | Monitor thermalState; throttle/suggest Fast model; warn user. |
| Search ToS concerns | Provider blocks/policy | Use scrape-tolerant provider; respect robots/rate; keep paid-API fallback option. |
| Scope creep (RAG/vision/voice all heavy) | Bloat, delay | v1 scope locked (PDF text only, light RAG, on-device STT); defer the rest. |

---

## 17. Build Checklist

### Phase 0 — Foundation
- [ ] Confirm Open Decisions §15 (at minimum OD-1, OD-2, OD-11).
- [ ] Create project; set deployment target + device floor (OD-11).
- [ ] Add increased-memory entitlement; mic/speech purpose strings.
- [ ] Set up SPM dependencies; license audit; SwiftLint/SwiftFormat; CI build.
- [ ] Define `InferenceService`, `SearchService`, `DocumentService`, `VoiceService`, `ModelManager` protocols + mocks.
- [ ] Establish encrypted persistence layer (PR-5/6) and data schema (DR-1).

### Phase 1 — MVP (local chat)
- [ ] Integrate inference engine (OD-1); load a model from disk; stream tokens (FR-1).
- [ ] Stop/cancel generation (FR-2); regenerate (FR-3).
- [ ] Markdown + code rendering with copy (FR-5).
- [ ] Conversations CRUD + encrypted persistence (FR-6/7).
- [ ] Model Manager: catalog, download w/ progress + resume + checksum, delete, switch (FR-11–15).
- [ ] Onboarding + first-run model download (UX-2, OD-9).
- [ ] Memory pressure handling + model unload (NFR-6/7/8).
- [ ] Unit tests for persistence, prompt building (TR-5/6).

### Phase 2 — Capabilities
- [ ] Fast/Thinking toggle wired to model strategy (FR-15, OD-2).
- [ ] Tool-call mechanism + bounded agent loop (TL-1/2); local utility tools (TL-3).
- [ ] Web search: query build → fetch → parse → inject → cite (FR-19/20); toggle default OFF (FR-18).
- [ ] Egress indicator + transparency view (FR-21, PR-12/13).
- [ ] Graceful search failure (FR-22).
- [ ] PDF import → extract → chunk → embed → index (FR-25/26, OD-3).
- [ ] Document Q&A with citations; document management (FR-27/28); size caps (FR-29).
- [ ] Voice input with on-device STT + permissions (FR-32–35).
- [ ] Settings screen (FR-37–41).

### Phase 3 — Hardening
- [ ] Integration tests: inference, search, RAG, voice (TR-7–10).
- [ ] UI tests for core flows (TR-11).
- [ ] **Network egress audit with search ON/OFF (TR-19) — release gate.**
- [ ] Offline-mode verification (TR-20); at-rest encryption verification (TR-21).
- [ ] Performance + memory tests across device matrix (TR-14/15/17); no jetsam on floor device.
- [ ] Accessibility pass: VoiceOver, Dynamic Type, contrast (TR-24/25).
- [ ] Thermal/low-memory/low-storage testing (TR-18).
- [ ] Confirm no tracking SDKs (TR-23).

### Phase 4 — Release
- [ ] App Privacy nutrition label accurate (PR-11, RR-5).
- [ ] Export-compliance/encryption declaration (RR-6).
- [ ] Verify every shipped model's license (MR-6, RR-10).
- [ ] App Store metadata, screenshots, privacy policy URL (RR-7, OD-12).
- [ ] Review notes re: model download (RR-8).
- [ ] TestFlight beta across device matrix (TR-27).
- [ ] Submit.

---

*End of specification. Confirm or adjust the Open Decisions in §15 and this becomes a locked build plan.*
