# BetterVolume — working context

A macOS menu bar app that replaces Apple's Sound control: **left click toggles** between two
audio outputs, **right click** opens the device menu, and devices can be **renamed** and
**hidden**. Agent app (`LSUIElement`), Swift 6 / SwiftPM, no third-party dependencies.

See [PLAN.md](../PLAN.md) for the full feasibility analysis, evidence and phase plan.

## Building — read this first

Always build through `Scripts/build.sh`:

```
Scripts/build.sh test       # 18 unit tests
Scripts/build.sh run        # run the agent from the terminal
Scripts/build.sh app        # assemble + sign BetterVolume.app
Scripts/build.sh install    # app + copy to /Applications
Scripts/build.sh clean
```

It builds into `~/Library/Caches/BetterVolume-build` with `--disable-index-store` and assembles
the `.app` there too. This was originally required because the repo lived on an SMB share, which
corrupted the Clang module cache, broke the index store's atomic renames, and attached Finder
metadata that `codesign` rejects. Keep using the script even on local disk — it is also where
signing and bundling live.

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
5. Distribution: **Developer ID + notarisation**. Currently ad-hoc signed.
6. No global hotkey.

## Status

Phases 0–3 complete and verified; Phase 4 ad-hoc signed and installed to
`/Applications/BetterVolume.app`.

Open items:
- No signing identity is installed (`security find-identity -v -p codesigning` → 0 valid).
  Create a *Developer ID Application* cert, then
  `BETTERVOLUME_SIGN_IDENTITY="Developer ID Application: … (TEAMID)" Scripts/build.sh app`.
  Notarisation commands are in PLAN.md.
- `BUNDLE_ID` in `Scripts/build.sh` and `AppInfo.bundleIdentifier` are placeholders
  (`com.bettervolume.BetterVolume`) — change to the real team prefix before signing.
- Settings live in the `com.bettervolume.BetterVolume` defaults domain; changing the bundle ID
  resets them.

## Conventions

- Keep logic out of the UI so it stays testable without audio hardware or a run loop.
- Verify with `Scripts/build.sh test` after every change.
- Language gotchas already hit: swift-testing's `#expect` rejects `allSatisfy(\.foo)` (rethrows);
  `item.state = cond ? .on : .off` needs an explicit `NSControl.StateValue`; `NSView.fittingSize`
  is zero for manually-framed views.
