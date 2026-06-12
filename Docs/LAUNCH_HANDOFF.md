# Launch Handoff — PrivacyLLM → App Store

Everything between today's repo state and a live App Store listing, in
order. Detailed procedures live in the docs this file links to; this is
the master checklist. Audience: Axel (or anyone with access to the Apple
Developer account, team `5QWX246F7X`).

## Where things stand (2026-06-12, `463f3cd`)

**Done and verified:** feature-complete v1 + three iterations. 94 unit
tests, 13 UI tests, iOS 18.6 floor build, and iPhone 17/iOS 26.2 builds
all green. On-device inference proven on real hardware
(Docs/PERF_BASELINES.md). `ITSAppUsesNonExemptEncryption = NO` already
set. Mic + speech-recognition purpose strings written. Donations are
StoreKit consumables (3.1.1-compliant tip jar) behind main menu → Donate.

**Never exercised yet:** CI on a hosted runner, the Qwen3.5/Gemma 4
catalog entries on real hardware, the egress audit, TestFlight, and the
App Store Connect record itself.

## Blockers at a glance

| # | Blocker | Effort |
|---|---|---|
| 1 | App icon — `Assets.xcassets/AppIcon.appiconset` contains **no images** | design time + 5 min to drop in |
| 2 | Llama 3.2 license decision (ship with attribution, or cut) | 1 h |
| 3 | Five tip consumables created in App Store Connect | 30 min |
| 4 | Privacy policy hosted at a public URL | 30 min |
| 5 | Egress audit signed off (release gate, TR-19) | half a day |
| 6 | TestFlight pass on the device matrix | 2–3 days elapsed |

---

## Step 0 — Decisions before anything else

- [ ] **Llama 3.2 stays or goes.** The catalog ships `llama-3.2-1b-4bit`
  and `llama-3.2-3b-4bit` under the *Llama 3.2 Community License*, which
  requires "Built with Llama" attribution and license display.
  *Recommendation:* cut them from `PrivacyLLM/Config/ModelCatalog.json`
  for v1 — every remaining model (Qwen3.5 2B/4B, Qwen3 1.7B/4B,
  Gemma 4 E2B) is plain Apache-2.0, which removes the question entirely.
  Re-add Llama in 1.1 with proper attribution if wanted.
- [ ] **iPhone-only or iPhone+iPad.** `TARGETED_DEVICE_FAMILY` is
  currently `1,2`, which obligates iPad screenshots and iPad QA — and
  nothing has ever been tested on an iPad. *Recommendation:* set it to
  `1` (iPhone) for v1; iPads can still run the app in compatibility mode
  and no iPad assets are required.
- [ ] **Age rating stance.** Apps exposing an unfiltered generative model
  have been pushed to higher age ratings in review. Decide what to answer
  honestly in the questionnaire and don't argue the first rejection —
  similar local-LLM clients commonly land at the highest tier.

## Step 1 — Close the project gaps

- [ ] **App icon.** Produce a 1024×1024 master (Xcode only needs the
  single size now). The vault identity: charcoal `#0E1113` ground,
  emerald `#34D399` mark. Drop into
  `PrivacyLLM/Assets.xcassets/AppIcon.appiconset`. Verify on a device in
  both light/dark and tinted home-screen modes.
- [ ] If Llama was cut: run the full test suite once
  (`xcodebuild test … -skipMacroValidation`, see Step 2) since
  ModelManager tests touch the catalog.
- [ ] Version stays `1.0 (1)` for the first upload; bump
  `CURRENT_PROJECT_VERSION` on every subsequent TestFlight build.

## Step 2 — Repo + CI (optional but recommended before beta)

- [ ] Push to GitHub (`https://github.com/axellangenskiold/PrivacyLLM` is
  already referenced from the Settings About screen — make it real or
  change the link).
- [ ] CI has never run on a hosted runner. Quirks a runner must satisfy:
  `-skipMacroValidation` on every `xcodebuild` invocation, the **Metal
  Toolchain** component installed (mlx-swift), iOS 26.2 + 18.6
  simulators. Reference invocation:

  ```sh
  xcodebuild test -project PrivacyLLM.xcodeproj -scheme PrivacyLLM \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -skipMacroValidation
  ```

## Step 3 — Real-device verification

MLX does not run on the simulator, so this is the only place inference is
truly tested. On the iPhone 17 (destination id
`00008150-0015146C2146401C`, unlock first; add
`-allowProvisioningUpdates` once after entitlement changes):

- [ ] Fresh install → onboarding → download **Qwen3.5 2B** (the
  RECOMMENDED default; ~1.8 GB — this exact flow is what the reviewer
  will do). The new catalog entries (Qwen3.5, Gemma 4 E2B) have never
  been downloaded on hardware.
- [ ] Chat in Fast and Thinking, regenerate, edit-and-rerun, stop
  mid-stream, PDF Q&A, dictation, model switch from the chat toolbar.
- [ ] Compare tok/s and first-token latency against
  Docs/PERF_BASELINES.md; append the new model's numbers.
- [ ] Device integration test suite auto-runs on device destinations:
  `xcodebuild test … -destination 'platform=iOS,id=00008150-0015146C2146401C' -skipMacroValidation`.

## Step 4 — App Store Connect setup

- [ ] Create the app record: bundle ID `com.axellangenskiold.PrivacyLLM`,
  name **PrivacyLLM — Private On-Device AI** (fallbacks if taken: see
  Docs/APP_STORE.md metadata section).
- [ ] **Create the five tip consumables** with exactly these product IDs
  and flat price points (whole-dollar tiers exist since 2023):

  | Product ID | Price | Display name |
  |---|---|---|
  | `com.axellangenskiold.PrivacyLLM.tip.small` | $1 | Small Tip |
  | `com.axellangenskiold.PrivacyLLM.tip.medium` | $2 | Medium Tip |
  | `com.axellangenskiold.PrivacyLLM.tip.large` | $3 | Large Tip |
  | `com.axellangenskiold.PrivacyLLM.tip.big` | $5 | Big Tip |
  | `com.axellangenskiold.PrivacyLLM.tip.huge` | $10 | Huge Tip |

  Descriptions must say nothing is unlocked. **Attach all five to the
  1.0 version submission** — first-time IAPs are reviewed with the app
  and the Donate page shows placeholders until they're approved. Enroll
  in the Small Business Program (15% commission) if eligible.
- [ ] Host Docs/PRIVACY_POLICY.md at a public URL (GitHub Pages is fine)
  and set it as the privacy policy URL.
- [ ] App Privacy questionnaire: **Data Not Collected** for every
  category (rationale in Docs/APP_STORE.md).
- [ ] Export compliance: answer Yes / exempt (standard OS crypto only) —
  the Info.plist key is already set. France note in Docs/APP_STORE.md.
- [ ] Age rating questionnaire per the Step 0 decision.

## Step 5 — Metadata + screenshots

Name, subtitle, keywords, and the screenshot shot-list are specified in
Docs/APP_STORE.md → Metadata. Capture trick that's already proven: run a
UI test non-parallel on a booted simulator and burst
`xcrun simctl io booted screenshot` (the sim inherits dark/light
appearance; `-parallel-testing-enabled NO`). Shots wanted: streamed
markdown chat (dark + light), thinking disclosure, model manager
mid-download, document Q&A with citation chips, privacy explainer, the
egress banner, and the Donate page.

## Step 6 — Egress audit (release gate)

Run all four passes of Docs/EGRESS_AUDIT.md (mitmproxy; search OFF, search
ON, airplane mode, data-at-rest) against a **Release** build on the
device and sign the table at the bottom. Zero unexpected hosts is the
pass bar. This is the one promise the whole app stands on — do it last,
on the build you intend to ship.

## Step 7 — TestFlight

- [ ] Archive in Xcode (Product → Archive; automatic signing, team
  `5QWX246F7X`) and upload. First upload triggers a processing +
  beta-review delay.
- [ ] Device matrix from SPECS (TR-17/27): a 4 GB-class device (1B-class
  model only — also confirms the RAM-triangle popup and download gate), a
  6 GB-class device, and a current flagship. Watch for: jetsam during
  generation on the floor device, download pause/resume + integrity
  verification over flaky Wi-Fi, thermal banner behavior, and the
  Donate purchase sheet end-to-end (TestFlight uses the sandbox — tips
  are not charged).
- [ ] At least one full install→onboard→download→chat run per device.

## Step 8 — Submit for review

- [ ] Review notes: paste the model-download explanation from
  Docs/APP_STORE.md → Review notes (weights are data, not code; MLX is
  compiled in; search is off by default), plus one line on donations:
  *"The Donate page sells consumable tips that unlock nothing; the app is
  fully functional without them."*
- [ ] Likely review questions, with answers ready:
  - **2.5.2 (downloaded code):** weights are inert data; inference runs
    on Apple's Metal via MLX compiled into the binary.
  - **3.1.1 (payments):** tips are consumable IAPs — compliant by
    construction.
  - **Age rating / generative content:** answer per Step 0; accept the
    higher tier rather than fight it on v1.
  - Reviewer needs Wi-Fi good enough for a ~1.8 GB download; the notes
    say so.
- [ ] Release option: manual release after approval is safer for a first
  launch (lets you re-run a smoke test on the production IAPs before
  going visible).

## Post-launch

- No analytics exist by design — the only signals are App Store reviews,
  crash reports users choose to share via Apple, and the GitHub issue
  tracker once the repo is public. Check App Store Connect's crash
  organizer weekly at first.
- Production smoke test on day one: download a model on cellular-off
  Wi-Fi, one chat, one $1 tip (it's live money now — refund yourself via
  reportaproblem.apple.com if desired).
- Known deferrals, candidates for 1.1: Llama with attribution, FR-9
  branching, FR-24 per-message search consent, FR-36 hands-free, OD-8
  Face ID lock, OD-10 custom model import.
