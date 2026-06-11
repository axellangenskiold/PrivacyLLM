# Performance Baselines (TR-14/15/16)

Measured via `MLXDeviceIntegrationTests` (prints `PERF[...]` lines) run on a
physical device:

```
xcodebuild test -project PrivacyLLM.xcodeproj -scheme PrivacyLLM \
  -destination 'platform=iOS,id=<device-udid>' \
  -only-testing PrivacyLLMTests/MLXDeviceIntegrationTests -skipMacroValidation
```

## Recorded baselines

| Date | Device | Model | First token | Tokens/sec | Notes |
|---|---|---|---|---|---|
| 2026-06-11 | iPhone 17 (A19, 8 GB, iOS 26.2) | SmolLM-135M-Instruct-4bit | 0.081 s | 30.8 | 16 prompt / 24 completion tokens, debug build |

Targets (spec): first token ≤ ~1.5 s (NFR-1), sustained ≥ 8–15 tok/s for a
1–3B 4-bit model (NFR-2). The 135M test model validates pipeline overhead;
record the shipping models below as they're exercised on hardware.

| Date | Device | Model | First token | Tokens/sec | Peak memory | Notes |
|---|---|---|---|---|---|---|
| _todo_ | iPhone 17 | Qwen3-1.7B-4bit | | | | measure via in-chat stats |
| _todo_ | iPhone 17 | Qwen3-4B-4bit | | | | |
| _todo_ | 4 GB-class device | Llama-3.2-1B-4bit | | | | TestFlight matrix (TR-17) |

## How to measure the shipping models

1. Download the model in-app on the device; send a few prompts.
2. Each persisted assistant message stores `GenerationStats` (first-token
   seconds, tok/s, token counts) — visible in the database or by logging.
3. Peak memory during load + generation: profile with Instruments
   (Allocations/VM Tracker) or watch `MLX.GPU.activeMemory` (FR-17 surface).
4. Jetsam check (TR-15): run a long generation with the Thinking model,
   background and foreground the app, repeat under Low Power Mode. The app
   must degrade (unload/reload) rather than crash.
5. Cold start (NFR-4): `PrivacyLLMUITestsLaunchTests` measures app launch;
   keep p90 ≤ 2 s on the floor device.

Real-device matrix beyond the iPhone 17 (mid + floor devices, thermal
throttling, low storage — TR-17/18) is a TestFlight activity; record results
here as they come in.
