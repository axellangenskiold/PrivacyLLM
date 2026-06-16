# Launch Plan — PrivacyLLM → App Store

The bare-essential path from here to a live listing. Detail lives in the
linked docs. Apple team `5QWX246F7X`, bundle ID
`com.axellangenskiold.PrivacyLLM`, version `1.0 (1)`.

## Already done
Feature-complete v1; 94 unit + 13 UI tests green; on-device inference
proven. **App icon**, **iPhone-only** target, and **"Built with Llama"**
attribution are all shipped — the old design/license blockers are closed.

## Remaining steps, in order

**1 · Host the privacy policy.** Publish `Docs/PRIVACY_POLICY.md` at a
public URL (GitHub Pages is fine). You paste it into App Store Connect.

**2 · Smoke-test on device.** MLX runs only on hardware. On the iPhone
(`id=00008150-0015146C2146401C`): fresh install → onboard → download
**Qwen3.5 2B** (~1.8 GB) → chat in Fast + Thinking, PDF Q&A, dictation.
This is the reviewer's exact flow.

**3 · App Store Connect setup.** (detail: `Docs/APP_STORE.md`)
- [ ] **Agreements, Tax, and Banking** → sign the **Paid Applications**
  agreement *first* — IAPs cannot be created without it.
- [ ] Create the app: **PrivacyLLM — Private On-Device AI**.
- [ ] Create the five **consumable** tips (prefix
  `com.axellangenskiold.PrivacyLLM.`; descriptions must say nothing is
  unlocked):

  | Product ID suffix | Price |
  |---|---|
  | `tip.small` | $1 |
  | `tip.medium` | $2 |
  | `tip.large` | $3 |
  | `tip.big` | $5 |
  | `tip.huge` | $10 |

- [ ] App Privacy → **Data Not Collected** for every category.
- [ ] Privacy-policy URL (step 1); Export compliance → **Yes / exempt**
  (Info.plist key already set); Age rating → answer honestly, accept the
  higher tier rather than fight it.
- [ ] Metadata + iPhone screenshots (name/subtitle/keywords in
  `APP_STORE.md`).

**4 · Egress audit — release gate.** (detail: `Docs/EGRESS_AUDIT.md`) Run
all four passes against a **Release** build on device; pass bar is **zero
unexpected hosts**; sign the table. Do this on the exact build you ship.

**5 · TestFlight.** Archive in Xcode (automatic signing) → upload; bump
`CURRENT_PROJECT_VERSION` each upload. Beta across a 4 GB device (1B model
only), a 6 GB device, and a current flagship — one full
install→onboard→download→chat per device.

**6 · Submit.** Attach all five IAPs to the 1.0 version. Paste the review
notes (weights are data not code, MLX compiled in, search off by default,
tips unlock nothing — full text in `APP_STORE.md`). Choose **manual
release**, then submit.

## After approval
Run one production-IAP smoke test, then release. No analytics by design —
watch App Store reviews and the crash organizer.
