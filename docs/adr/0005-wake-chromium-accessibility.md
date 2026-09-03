# Parrot asks apps to switch their accessibility tree on

The focus probe from #16 (`FocusedTextTarget`) reads `kAXFocusedUIElementAttribute`
off the system-wide element and asks whether what it finds can take text. In a
browser it found nothing, every time, and the transcript went to the fallback
popover while the user was looking straight at a focused text field.

The cause is not in the probe. **Chromium apps (Chrome, Arc, Brave, Edge) and
Electron apps (Slack, VS Code, Notion) ship with their accessibility tree switched
off** and only build it once an assistive technology announces itself — the tree
for every tab is expensive, so it is not paid for until something needs it. Until
then a focused `<input>` is invisible over the accessibility API. The browser's
own chrome — the address bar, the find bar — is native AppKit and stays visible
throughout, which is what made the failure look intermittent rather than total.

The two families watch different attributes: Chromium wakes on
`AXEnhancedUserInterface`, the flag VoiceOver sets, and Electron wakes on
`AXManualAccessibility`. Neither is declared in a header.

**Parrot sets both, on the app owning the focused element, as each dictation
starts.** `AccessibilityOptIn.wakeFocusedApp()` runs from `beginRecording()`, which
buys the tree the whole recording-plus-transcription window — a second at minimum —
to finish building before the probe looks. Setting an attribute an app does not use
fails with `kAXErrorAttributeUnsupported` and costs nothing, so no app detection is
needed.

Two alternatives were on the table. **`AXManualAccessibility` alone** has no side
effects at all, but Chromium the browser does not watch it — it would have fixed
Slack and left Arc broken, which is the case that prompted this. **A bundle-id
allow-list** would confine the wake to apps known to need it, at the cost of a list
to maintain and of every unrecognised Electron app staying broken; the failure mode
of guessing wrong is silent, and the thing being guessed at is an implementation
detail of other people's apps.

## Consequences

- **Parrot now presents as an assistive technology.** `AXEnhancedUserInterface` is
  how a screen reader announces itself, and apps are entitled to behave differently
  when one is present. The known cost is window geometry: some apps re-lay-out or
  resize on that transition, which is the long-standing friction between Chromium
  and tiling window managers. This is a real behaviour change to other people's
  apps, taken deliberately.
- **Chromium builds a full accessibility tree for its tabs**, with the CPU and
  memory that implies on heavy pages. That is the cost the browser was avoiding.
- **`--no-wake-accessibility` turns it off.** The escape hatch exists because the
  consequences above land outside parrot and cannot be predicted per app. With it,
  behaviour returns to what shipped before this: browsers fall back to the popover.
- **The probe retries once behind a second wake.** A tree woken moments ago may
  still be building, and Chromium lets its own lapse after a spell with no
  assistive technology about, so a first empty answer is not taken as final —
  except for a secure field, where the refusal is the whole point of #16's check.
- **The wake is keyed on pid, not on bundle id**, and pids are forgotten as their
  apps quit, so an app relaunched under a recycled pid is asked again.
- Nothing here weakens the secure-field refusal. Waking a tree only makes elements
  visible; `FocusRules.isSecure` still turns a password box away, now at every rung
  of the walk and under test.
