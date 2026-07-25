# BetterVolume — Feasibility & Implementation Plan

A menu-bar replacement for the macOS Sound control that lets you **rename**, **hide**, and
**one-click toggle** audio outputs.

Status: **Phases 0–3 built and verified; Phase 4 built ad-hoc.** Installed at
`/Applications/BetterVolume.app`. Build with [Scripts/build.sh](Scripts/build.sh);
[tools/audio-probe.swift](tools/audio-probe.swift) is the read-only Core Audio probe used to
gather the evidence below.

```
Scripts/build.sh test       # 18 unit tests
Scripts/build.sh run        # run the agent from the terminal
Scripts/build.sh install    # build, sign, copy to /Applications
```

The repo lives on an SMB share, which breaks SwiftPM's index store and corrupts the Clang module
cache, and attaches Finder metadata that `codesign` rejects. `Scripts/build.sh` therefore builds
into `~/Library/Caches/BetterVolume-build` and assembles the bundle there too. Always build
through the script.

---

## 1. Verdict

| # | What you want | Feasible? | Notes |
|---|---|---|---|
| 1 | Rename audio outputs | **Yes — inside our app.** System-wide rename: **no.** | `kAudioObjectPropertyName` is read-only on every device on this Mac. Aliases are display-only, which is fine because we draw the menu. |
| 2 | Hide devices you never use | **Yes, trivially.** | We render the list, so hiding is a filter. Bonus: all four AirPlay entries are *already* invisible to us (see §2). |
| 3 | Left-click toggles, right-click opens menu | **Yes.** | Standard `NSStatusItem` behaviour; ~15 lines. |

Overall: **this is a small, low-risk app.** No private APIs, no kernel/driver work, no
entitlements, no elevated privileges. The whole switching mechanism is two public Core Audio
calls. The hard parts are polish (identity stability, menu-bar UX), not capability.

The one thing you **cannot** have without a lot more work is a working volume slider/volume keys
for the INZONE Buds or the DELL — and macOS itself doesn't have that either today (§2.3), so
you lose nothing.

---

## 2. What was actually verified on this Mac

macOS 26.5 (25F84), Mac Studio, Xcode 26.5 / Swift 6.3. Reproduce with
`swift tools/audio-probe.swift`.

### 2.1 The real device list

| Name | Transport | UID | modelUID | Name settable | Volume settable |
|---|---|---|---|---|---|
| Mac Studio Speakers | `bltn` | `BuiltInSpeakerDevice` | `Speaker` | no | **yes** (0.71) |
| External Headphones | `bltn` | `BuiltInHeadphoneOutputDevice` | `Codec Output` | no | **yes** (0.50) |
| DELL U2722D | `hdmi` | `10AC2F42-…_FFFFFFFF` | – | no | no |
| INZONE Buds | `usb` | `AppleUSBAudioEngine:Sony:INZONE Buds:4100000:2,1` | `INZONE Buds:054C:0EC3` | no | no |

`kAudioHardwarePropertyDefaultOutputDevice` and `…DefaultSystemOutputDevice` are both
**settable** → switching outputs works, and is the same mechanism `SwitchAudioSource` has used
for 16 years.

### 2.2 Your AirPlay junk isn't even real (in Core Audio terms)

**Home Theater, Living Room, Master Bedroom and Q-Series Soundbar do not appear in the Core
Audio device list at all.** Control Center gets those from a separate, private AirPlay routing
layer. Consequence:

- Problem #2 solves itself. Our menu will show 4 items, not 8.
- Trade-off: **we cannot offer AirPlay targets either.** If you ever want to play to the Apple
  TV, you'd use Control Center / AirPlay in the app you're playing from. Worth confirming you're
  OK with that before we hide Apple's Sound item.
- Caveat to check later: an AirPlay route *may* materialise as a temporary Core Audio device
  while it is selected. Untested — it would only affect display, not function.

### 2.3 Volume: you're not losing anything

- Built-in speakers/headphones: full `VolumeScalar` + `VirtualMainVolume` + mute support.
- DELL (HDMI) and INZONE Buds (USB): **no volume property at all**, not even the virtual main
  volume fallback.
- Confirmed at the OS level: with INZONE Buds selected, `osascript -e 'get volume settings'`
  returns `output volume: missing value`. macOS has no software volume for it either — the
  Control Center slider in your screenshot is decorative for that device.
- Making volume keys work for USB/HDMI outputs requires shipping a virtual Core Audio driver
  that everything is routed through (this is literally SoundSource's "Super Volume Keys"
  feature). **Explicit non-goal.**

### 2.4 Device UIDs are not stable — this is the real gotcha

`/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist` contains your headset under
**two different UIDs**:

```
AppleUSBAudioEngine:Sony:INZONE Buds:2110000:2,1
AppleUSBAudioEngine:Sony:INZONE Buds:4100000:2,1
```

The middle field is a USB location/session token that changes across reconnects. If we key
aliases/hidden/toggle-pair on raw UID alone, your settings silently detach from the headset one
day. Mitigation in §4.2: match on `modelUID` (`INZONE Buds:054C:0EC3` — Sony VID 0x054C,
PID 0x0EC3, stable) with UID and name as secondary keys.

---

## 3. Does this already exist?

Nothing found does all three things. Closest options:

| Tool | Switch | Hide | Rename | L-click toggle | Notes |
|---|---|---|---|---|---|
| **macOS Control Center** | yes | no | no | no | The thing you're complaining about. |
| **SoundSource 6** (Rogue Amoeba, paid) | yes | partial | no | no | Excellent app, but it's a per-app mixer/EQ + "Super Volume Keys". Heavyweight for this. |
| **switchaudio-osx** (`brew install switchaudio-osx`, MIT) | yes (CLI) | n/a | n/a | n/a | `-c` current, `-n` cycle, `-u <uid>` set. Perfect **building block / oracle** for testing. |
| **Hammerspoon** (`hs.audiodevice` + `hs.menubar`) | yes | yes | yes | yes | You build the menu yourself, so all three are scriptable in ~60 lines. **The fastest path to relief today** — see §6. |
| **vigorX777/AudioSwitch**, **Serho-junior/audio-control-macos** (GitHub, Swift) | yes | ? | no | ? | Native menu-bar switchers worth reading for reference. |
| **ToothFairy** | Bluetooth only | – | yes (icon/label) | yes | Proves the one-click-toggle UX; wrong scope for a wired device. |
| Raycast / Alfred / Shortcuts | yes | n/a | n/a | no | Keyboard-driven, not menu-bar. |

So: the switching primitive is thoroughly solved, and **the differentiated bit is exactly the
three things you asked for** — a device list *you* curate, with a status item that treats
left-click as an action rather than as "open a menu".

---

## 4. Design

### 4.1 Interaction model

- **Left click** → immediately switch to the other output. No menu, no animation.
- **Right click** (and Control-click) → the full menu: device list with checkmark, aliases
  applied, hidden devices excluded, plus `Preferences…`, `Show Hidden Devices ▸`, `Quit`.
- **Icon** reflects the current output (headphones / speaker / display glyph), optionally with a
  short text label from your alias so you can tell state at a glance without clicking.
- Two candidate toggle semantics — **pick one** (§8):
  - **A. Pinned pair (recommended for you):** you designate INZONE Buds ⟷ External Headphones.
    Left click always flips between exactly those two. Utterly predictable.
  - **B. MRU:** left click returns to the most recently used *other* device. More general,
    slightly less predictable when a third device gets involved.
  - We can implement B as the storage layer and A as a setting on top; they share code.
- Edge cases to handle explicitly: target device unplugged (fall through to next candidate),
  only one device present (no-op + brief flash), macOS auto-switched for us (e.g. headset
  connects) — that must be recorded as a switch so the toggle target stays sane.

### 4.2 Device identity

```swift
struct DeviceIdentity: Codable, Hashable {
    var uid: String        // AppleUSBAudioEngine:Sony:INZONE Buds:4100000:2,1  (may change)
    var modelUID: String?  // INZONE Buds:054C:0EC3                             (stable)
    var name: String       // INZONE Buds
}
```

Resolution order when reconciling saved settings against live devices:
`uid` exact → `modelUID` + `name` → `name` → unmatched (keep the record, mark offline).
Records are never deleted on disconnect, so unplugging doesn't wipe your aliases.

### 4.3 Persisted state (`UserDefaults`, one JSON blob)

```
devices: [DeviceIdentity]        // known devices, in user-defined menu order
alias:   [DeviceKey: String]     // "INZONE Buds" -> "Buds"
hidden:  Set<DeviceKey>
togglePair: (DeviceKey, DeviceKey)?
recents: [DeviceKey]             // MRU, capped
```

### 4.4 Core Audio surface used

| Purpose | API |
|---|---|
| Enumerate | `kAudioHardwarePropertyDevices` + `kAudioDevicePropertyStreamConfiguration` (output scope, >0 channels) |
| Identify | `…DeviceUID`, `…ModelUID`, `kAudioObjectPropertyName`, `…TransportType` |
| Switch | set `kAudioHardwarePropertyDefaultOutputDevice` **and** `kAudioHardwarePropertyDefaultSystemOutputDevice` (so alert sounds follow — Apple's menu does both) |
| React | `AudioObjectAddPropertyListenerBlock` on device-list + default-output changes |
| Volume (where supported) | `kAudioDevicePropertyVolumeScalar` / `kAudioDevicePropertyMute`, output scope, main element |

Known traps: listener blocks fire on a HAL-chosen queue (hop to `@MainActor`); we get a
notification back for our own writes (dedupe by comparing to the value we just set); listeners
must be removed on teardown; a device that vanishes leaves a stale `AudioObjectID`, so always
re-resolve by UID rather than caching IDs.

### 4.5 Architecture (keeps logic testable without a UI)

```
BetterVolume/
├── Package.swift                    # SwiftPM, zero external dependencies
├── Sources/
│   ├── AudioRouting/                # pure logic, no AppKit, no CoreAudio
│   │   ├── DeviceIdentity.swift
│   │   ├── DeviceRegistry.swift     # merge live devices + saved settings
│   │   ├── ToggleResolver.swift     # "given state, what do I switch to?"
│   │   ├── Settings.swift
│   │   └── AudioSystem.swift        # protocol: list(), current(), setDefault(_:)
│   ├── CoreAudioSystem/             # the only file that touches the HAL
│   │   └── CoreAudioSystem.swift    # implements AudioSystem
│   └── BetterVolumeApp/             # AppKit agent (LSUIElement)
│       ├── main.swift
│       ├── StatusItemController.swift
│       ├── MenuBuilder.swift
│       └── PreferencesWindow.swift  # SwiftUI in an NSHostingView
├── Tests/AudioRoutingTests/         # swift-testing, drives a FakeAudioSystem
├── tools/audio-probe.swift
└── Scripts/bundle.sh                # assemble + ad-hoc sign BetterVolume.app
```

`ToggleResolver` and `DeviceRegistry` are pure functions over value types → every edge case in
§4.1 gets a unit test with no audio hardware involved. `Scripts/bundle.sh` is preferred over an
Xcode project because it makes `swift build && swift test && ./Scripts/bundle.sh && open …`
a one-liner; migrating to Xcode later for notarisation is easy.

The click split, for reference:

```swift
statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
statusItem.button?.action = #selector(handleClick)

@objc func handleClick() {
    let event = NSApp.currentEvent
    let wantsMenu = event?.type == .rightMouseUp
        || event?.modifierFlags.contains(.control) == true
    if wantsMenu {
        statusItem.menu = buildMenu()          // assign, click, unassign:
        statusItem.button?.performClick(nil)   // gives correct highlight + dismissal
        statusItem.menu = nil
    } else {
        controller.toggle()
    }
}
```

---

## 5. Implementation plan

Each phase ends with something runnable and a stated verification. No phase depends on
guesswork from a later one.

### Phase 0 — Switching spike (proves the premise) — **done**
- Minimal executable: list output devices, switch to a device by UID, print before/after.
- **Verified:** switched INZONE Buds → DELL U2722D → back, both `DefaultOutputDevice` and
  `DefaultSystemOutputDevice` returned `noErr`, and `system_profiler SPAudioDataType`
  independently confirmed the restore.

### Phase 1 — Status item + toggle — **done**
- `LSUIElement` agent, status item with a per-device SF Symbol, left-click toggle, right-click
  menu listing output devices with a checkmark on the current one, tooltip naming the toggle
  target.
- HAL listeners for device-list and default-output changes; recents updated on *any* change,
  including ones macOS makes for us.
- **Verified:** unit tests for `ToggleResolver`; live confirmation that the icon renders and
  both click behaviours work.

### Phase 2 — Rename + hide + order — **done**
- Settings window (SwiftUI in an `NSHostingView`): per-device alias field, show/hide checkbox,
  drag to reorder, toggle-mode radio group, and the two pinned-pair pickers.
- Menu renders aliases, skips hidden devices, respects order.
- **Verified:** registry tests including the exact UID-churn scenario from §2.4; settings view
  lays out at its intended size.

### Phase 3 — Volume + login — **done**
- Volume slider at the top of the menu, enabled only when the current device reports a settable
  volume; shown maxed and disabled otherwise (matching macOS) with a tooltip explaining why.
  Needed because you chose to replace Apple's Sound item, and your desk speakers *do* have
  volume control.
- Start-at-login via `SMAppService`, disabled unless running from an app bundle.

### Phase 4 — Ship it — **ad-hoc done, Developer ID pending**
- `Scripts/build.sh app` produces a signed `BetterVolume.app` (`LSUIElement`, hardened runtime
  when a real identity is used). `install` copies it to `/Applications`.
- **Blocker for sharing:** `security find-identity -v -p codesigning` reports 0 valid
  identities on this Mac. Create a *Developer ID Application* certificate (Xcode → Settings →
  Accounts → Manage Certificates → +), then:
  ```
  BETTERVOLUME_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/build.sh app
  ditto -c -k --keepParent <app> BetterVolume.zip
  xcrun notarytool submit BetterVolume.zip --keychain-profile <profile> --wait
  xcrun stapler staple <app>
  ```
  Also change `BUNDLE_ID` in the script and `AppInfo.bundleIdentifier` to your team's prefix
  before signing.
- Optionally hide Apple's item: System Settings → Control Center → Sound → *Don't Show in Menu
  Bar*, then ⌘-drag ours into position.

---

## 6. Zero-build escape hatch (if you want relief today)

Hammerspoon gives you all three behaviours because you build the menu yourself:
`hs.audiodevice.allOutputDevices()`, `:setDefaultOutputDevice()`, `hs.audiodevice.watcher`, and
`hs.menubar` (whose click callback receives the modifier table, so left vs. right is
distinguishable). Roughly 60 lines of Lua: a table mapping UID → display name, a hidden set, and
a two-element toggle. **Not written or tested here** — call it out if you want me to build and
verify it as a stopgap while the native app gets written.

---

## 7. Risks & open questions

| Risk | Severity | Mitigation |
|---|---|---|
| UID churn detaches settings (§2.4) | **High — the main one** | modelUID-first identity matching, plus a test that simulates the churn |
| Hiding Apple's Sound item loses AirPlay access | Medium | Decide in §8; or keep Apple's item until Phase 3 |
| Volume slider unavailable for USB/HDMI | Low | macOS has the same limitation; grey out |
| HAL listener threading / re-entrancy | Low | `@MainActor` hop + dedupe our own writes |
| Menu-bar changes in a future macOS | Low | `NSStatusItem` is ancient and stable |
| Doesn't survive sleep / device re-enumeration | Medium | Re-resolve by identity on every device-list notification; test with sleep-wake |

---

## 8. Decisions (locked)

1. **Toggle semantics:** pinned pair, with most-recently-used available as a setting. A
   half-configured pair falls back to most-recently-used rather than dead-ending.
2. **Replace** Apple's Sound menu item — hence the volume slider in Phase 3. Trade-off
   accepted: AirPlay targets are unreachable from our menu (§2.2).
3. **Output only.** Inputs are not shown or switched.
4. **Hidden means "not in the menu"** only. Hidden devices are still switchable from Settings
   and are still honoured if pinned; macOS auto-switching is not fought.
5. **Distribution:** shareable — Developer ID + notarisation. Currently ad-hoc signed because no
   signing identity is installed yet (see Phase 4).
6. **No global hotkey.** The menu-bar click is enough.
