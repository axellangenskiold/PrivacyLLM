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
the ~1.8 GB recommended model), then chat. Airplane mode demonstrates full
offline operation.

## Model licenses (MR-6, RR-10)

| Model | License | Redistribution notes |
|---|---|---|
| Qwen3.5 2B / 4B | Apache-2.0 | attribution in-app via license link |
| Qwen3 1.7B / 4B | Apache-2.0 | attribution in-app via license link |
| Gemma 4 E2B | Apache-2.0 | plain Apache-2.0 (Gemma 4 dropped the bespoke Gemma Terms) — no extra attribution gate |
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
- **Screenshots:** chat with streamed markdown reply (dark "Obsidian Vault"
  look + light), thinking disclosure open, model manager mid-download,
  document Q&A with citation chips and the attachment card, privacy
  explainer screen, egress banner during a search
- **Age rating:** standard questionnaire; unrestricted web access = No (the
  app fetches search results as data; no browser is exposed) — answer
  honestly based on final review guidance

## Monetization (OD-12)

The app is **free with no IAP**; a voluntary donations page (Settings →
Support) presents Apple Pay directly via PassKit. Before this can work or
ship:

- [ ] Create merchant ID `merchant.com.axellangenskiold.PrivacyLLM` in the
  developer portal and add the Apple Pay capability for it (Signing &
  Capabilities). Until then the buttons show an "Apple Pay isn't available"
  notice.
- [ ] Wire a payment processor (e.g. Stripe) into
  `ApplePayDonationCoordinator.didAuthorizePayment` — the raw PKPayment
  token charges nobody.
- [ ] **Review risk:** guideline 3.2.1 reserves Apple Pay donations for
  approved nonprofits; developer "tips" are normally required to be
  consumable IAP (3.1.1, Apple takes its commission). If review rejects the
  PassKit flow, swap `DonateView.swift`'s coordinator for StoreKit
  consumables ($0.99 / $1.99 / $2.99 tiers) — the page layout can stay.

## Pre-submission gates

- [ ] Egress audit passed (Docs/EGRESS_AUDIT.md) — release gate (TR-19)
- [ ] `ITSAppUsesNonExemptEncryption` set
- [ ] Model licenses verified for every catalog entry (RR-10)
- [ ] TestFlight beta across device matrix: 4 GB-class device (1B model
  only), 6 GB-class, current flagship (TR-17, TR-27); no jetsam on floor
- [ ] App icon + launch experience final
- [ ] Version/build numbers bumped; release notes written (RR-9)
