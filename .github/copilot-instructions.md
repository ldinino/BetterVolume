# BetterVolume — working context

A macOS menu bar app that replaces Apple's Sound control: **left click toggles** between two
audio outputs, **right click** opens the device menu, and devices can be **renamed** and
**hidden**. Agent app (`LSUIElement`), Swift 6 / SwiftPM, no third-party dependencies.

See [PLAN.md](../PLAN.md) for the full feasibility analysis, evidence and phase plan.

## Building — read this first

Always build through `Scripts/build.sh`:

```
Scripts/build.sh test       # 26 unit tests
Scripts/build.sh run        # run the agent from the terminal
Scripts/build.sh app        # assemble + sign BetterVolume.app
Scripts/build.sh install    # app + copy to /Applications
Scripts/build.sh clean
```

It builds into `~/Library/Caches/BetterVolume-build` with `--disable-index-store` and assembles
the `.app` there too. This was originally required because the repo lived on an SMB share, which
corrupted the Clang module cache, broke the index store's atomic renames, and attached Finder
metadata that `codesign` rejects. The repo now lives on local disk (`~/Developer/BetterVolume`)
and plain `swift build` works again, but keep using the script — it is also where signing and
bundling live. If you ever work from a copy on the `Mass Sync` SMB share, the script is the only
thing that will build.

## Architecture

| Target | Rule |
|---|---|
| `Sources/AudioRouting` | **Pure logic.** No AppKit, no CoreAudio. All unit tests point here. |
| `Sources/AudioHAL` | The **only** code that touches Core Audio (`HALAudioSystem`). |
| `Sources/BetterVolumeApp` | AppKit status item + SwiftUI settings window. |

`AppModel` is the single `@Observable` source of truth. SwiftUI observes it directly; the AppKit
status item redraws via the `onChange` callback. All settings mutations call `refresh()`, which
re-reads the HAL and reconciles, so state is never partially updated.

Device identity: `DeviceRecord.id` (a `UUID` we mint) is the stable key for pins, recents and
aliases. Core Audio identity is reconciled separately by `DeviceRegistry` — never key anything
off a UID or `AudioObjectID`.

Renames and icons are ours: `alias` and `symbolName` on `DeviceRecord`, resolved by
`displayName` and `DeviceIcons.symbolName(for:)`. Both survive disconnects and UID churn.

## Verified platform facts (macOS 26.5, Mac Studio)

Re-check with `swift tools/audio-probe.swift`.

- `kAudioHardwarePropertyDefaultOutputDevice` **is** settable. Set both it and
  `...DefaultSystemOutputDevice` so alert sounds follow the music.
- `kAudioObjectPropertyName` is **not** settable on any device → renames are display-only
  aliases stored by us.
- AirPlay targets shown in Control Center are **not** Core Audio devices. They are invisible to
  this app, which is why hiding them was free — and why we can't offer them either.
- USB and HDMI outputs expose **no** volume control (no `VolumeScalar`, no `VirtualMainVolume`).
  macOS has none either — `osascript -e 'get volume settings'` returns `output volume: missing
  value` with the USB headset active. The slider is shown maxed and disabled for those, matching
  system behaviour. Do not fake it.
- **Device UIDs churn across reconnects.** The same headset appears in macOS's own settings as
  both `…INZONE Buds:2110000:2,1` and `…:4100000:2,1`. `DeviceRegistry` matches
  uid → modelUID+name → modelUID → name, greedily strongest-first, and refreshes the stored
  identity in place. There is a regression test for exactly this.

## Locked product decisions

1. Toggle = **pinned pair**, with most-recently-used as a setting. A half-configured pair falls
   back to most-recently-used rather than dead-ending.
2. **Replaces** Apple's Sound menu item (hence the volume slider). AirPlay is knowingly given up.
3. **Output devices only.** No inputs.
4. **Hidden means "not in the menu"** only — still switchable from Settings, still honoured if
   pinned. macOS auto-switching is not fought.
5. Distribution: **Developer ID + notarisation**. Signed with Developer ID; not notarised.
6. No global hotkey.

## Status

Phases 0–4 complete. `/Applications/BetterVolume.app` is signed with **Developer ID Application:
Luciano DiNino (TW9Z5U2FJ9)**, hardened runtime, secure timestamp.

`build_app` auto-detects the Developer ID certificate from the keychain, so plain
`Scripts/build.sh app` stays correctly signed. Ad-hoc is only the fallback when no cert exists.

Open items:
- **Not notarised.** Irrelevant for local use (a locally built app is never quarantined, so
  `spctl` reporting `rejected — Unnotarized Developer ID` does not block launch). Required only
  before sending the app to anyone else; commands are in PLAN.md.
- `BUNDLE_ID` in `Scripts/build.sh` and `AppInfo.bundleIdentifier` are still
  `com.bettervolume.BetterVolume`. Deliberately left alone: Developer ID signing does not
  require a team-prefixed bundle ID, and changing it resets settings (they live in that defaults
  domain).

## Conventions

- Keep logic out of the UI so it stays testable without audio hardware or a run loop.
- Verify with `Scripts/build.sh test` after every change.
- Language gotchas already hit: swift-testing's `#expect` rejects `allSatisfy(\.foo)` (rethrows);
  `item.state = cond ? .on : .off` needs an explicit `NSControl.StateValue`; `NSView.fittingSize`
  is zero for manually-framed views.
- **Never commit a SwiftUI `TextField` on `onSubmit` / `@FocusState` loss inside a macOS `List`** —
  that focus transition is unreliable and silently drops typed text. Bind straight to the model,
  and don't trim in the setter: it eats the space the user just typed.
- Menu bar glyphs go through `DeviceSymbol.statusItemImage`, which centres them on a fixed canvas.
  SF Symbols differ in width by up to 15pt, and `variableLength` would make the item jump.
