# App Store Submission Checklist

## App Privacy questionnaire (PR-11, RR-5)

Answer **"Data Not Collected"** for every category. Rationale: the app has no
servers and no SDKs that collect data. User-initiated network actions (model
downloads from Hugging Face, opt-in search queries to the user's chosen
provider) are not collection by the developer; neither request carries user
identity or content beyond the search keywords the user's model produced.

## Export compliance (RR-6)

The app uses only standard, OS-provided encryption (Data Protection,
CryptoKit AES-GCM, HTTPS/ATS). In App Store Connect answer:

- "Does your app use encryption?" → **Yes**
- "Does your app qualify for any of the exemptions?" → **Yes** — it only
  uses encryption from iOS/standard algorithms (exempt under category 5D992
  mass-market provisions).
- Set `ITSAppUsesNonExemptEncryption = NO` in the Info.plist build settings
  before submission (`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`).
- France: standard-crypto self-classification; keep a copy of the annual
  self-classification report if distributing there.

## Review notes (RR-8)

> PrivacyLLM runs an open-weights language model entirely on-device. On first
> run the app downloads model weight files (data, not executable code) from
> huggingface.co, exactly like downloading any document. No code is
> downloaded or executed; inference uses Apple's Metal GPU via the MLX
> framework compiled into the app. Web search is OFF by default; when the
> user enables it, only short keyword queries go to the user's chosen search
> engine (DuckDuckGo by default), with a visible on-screen indicator.

Demo instructions for the reviewer: complete onboarding on Wi-Fi (downloads
~1 GB model), then chat. Airplane mode demonstrates full offline operation.

## Model licenses (MR-6, RR-10)

| Model | License | Redistribution notes |
|---|---|---|
| Qwen3 1.7B / 4B | Apache-2.0 | attribution in-app via license link |
| Llama 3.2 1B / 3B | Llama 3.2 Community License | requires "Built with Llama" attribution and license display — verify before enabling in a store build, or ship Qwen-only initially |

The app downloads weights from the public mlx-community repos; verify each
repo's license file at release time. License names + links are shown per
model in the Models screen.

## Metadata (RR-7)

- **Name:** PrivacyLLM — Private On-Device AI
- **Subtitle:** Private AI chat, no cloud
- **Keywords:** private ai, offline ai, local llm, on-device, chat, gpt
  alternative, document chat, no tracking
- **Privacy policy URL:** host `Docs/PRIVACY_POLICY.md` (e.g. GitHub Pages)
- **Screenshots:** chat with streamed markdown reply (light + dark), thinking
  disclosure open, model manager mid-download, document Q&A with citation
  chips, privacy explainer screen, egress banner during a search
- **Age rating:** standard questionnaire; unrestricted web access = No (the
  app fetches search results as data; no browser is exposed) — answer
  honestly based on final review guidance

## Pre-submission gates

- [ ] Egress audit passed (Docs/EGRESS_AUDIT.md) — release gate (TR-19)
- [ ] `ITSAppUsesNonExemptEncryption` set
- [ ] Model licenses verified for every catalog entry (RR-10)
- [ ] TestFlight beta across device matrix: 4 GB-class device (1B model
  only), 6 GB-class, current flagship (TR-17, TR-27); no jetsam on floor
- [ ] App icon + launch experience final
- [ ] Version/build numbers bumped; release notes written (RR-9)
