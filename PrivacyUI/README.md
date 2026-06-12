# PrivacyUI

PrivacyLLM's design system — the "Obsidian Vault" identity — as a standalone
Swift package with zero dependencies beyond SwiftUI.

- **Tokens:** `Color.pv*` semantic palette (dark-first, AA in both schemes),
  `PVFont` type ramp (rounded display, monospaced meta), `PVRadius`/`PVSpacing`.
- **Components:** screen background, cards, chat bubbles, buttons, status
  badges, chips, banners, disclosures, attachment cards, segmented pill,
  empty states, stat lines. Every component has a `#Preview` in light + dark.
- **Accessibility:** Dynamic Type-relative fonts, Reduce Motion respected on
  every glow/pulse, selection traits on custom controls.

Import with `import PrivacyUI`. Nothing in here knows about the app's domain —
it can be reused as-is in any SwiftUI project.
