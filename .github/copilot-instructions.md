# PrivacyLLM

A SwiftUI iOS app that runs an LLM entirely on-device. No servers, no accounts,
no analytics. Review with that in mind.

## What matters most here

- **Egress.** Search and device actions are opt-in and off by default. Their
  gate is re-checked in `ToolRouter` at call time, not just when the prompt is
  built. Anything that widens what leaves the device, or moves a check earlier,
  is a bug.
- **The lazy transcript.** Nothing that updates continuously may live inside the
  chat's `LazyVStack` — it has twice caused an unrecoverable main-thread render
  loop. See `PVActivityDots` for the rule and the two reproductions.
- **Model lifecycle.** Weights are ~2 GB. Flag anything that keeps them
  resident, blocks the main thread, or raises sustained GPU load.
- **Concurrency.** Swift 6: actor isolation, `Sendable`, and unstructured
  `Task`s that outlive their owner.
- **Crash paths.** Model output is untrusted input. No force unwraps on it.

## What to skip

Formatting and style — SwiftLint (`--strict`, blocking) and SwiftFormat run in
`.github/workflows/ci.yml`.
