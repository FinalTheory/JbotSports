# JbotSports (watchOS)

Apple Watch controller for the tennis launcher (V6 protocol branch), implemented with SwiftUI + CoreBluetooth.

## Current Features
- BLE pairing and reconnect flow
  - Scan / rescan
  - Connect to target peripheral
  - Resume connection on app foreground
- 4-page control UI
  - Page 1: Start / Stop / Frequency +/-
  - Page 2: Speed / Height / Spin adjustments
  - Page 3: Random-run controller (auto shuffle loop)
  - Page 4: Preset list + editor + settings
- Preset management (local persistence)
  - Create / edit / delete (cannot delete last preset)
  - Ball order editor (max 28 positions)
  - Per-preset fields: order, random/sequential, shuffle, interval, top/bottom speed, frequency, height
- Random-run mode
  - Uses presets with `shuffle = true`
  - Shuffles once per round (no duplicates inside a round)
  - Supports global interval and per-preset interval override
  - Supports configurable initial machine start delay
- Language setting
  - `System` / `English` / `Chinese (Simplified)`
  - Language choice is persisted
  - Full language switch is applied after app restart
- Optional debug overlay
  - Flash hints for outgoing command and preset switching

## Protocol and BLE
- Target protocol branch: **V6**
- BLE constants and command encoding are centralized in:
  - `BLE/BLEManager.swift`
  - `BLE/ProtocolEncoder.swift`
- Implemented command categories:
  - Start/stop
  - Frequency
  - Height (`shortAngle`)
  - Top/bottom speed (via start-preview/full start path)
  - Fine tune left/right

## Parameter Ranges
- Top speed: `30...100`
- Bottom speed: `30...100`
- Spin delta (`top - bottom`): clamped within `-50...50`
- Frequency: `1...9`
- Height (`shortAngle`, V6): `12...60`
- Random-run interval: `10...120` (step 5)
- Random-run start delay: `5...15` (step 1)

## Data Persistence
- Presets: `UserDefaults` JSON
- Random-run settings: `UserDefaults`
- Debug switch: `UserDefaults`
- App language selection: `UserDefaults` + `AppleLanguages`

## Run / Build
1. Install XcodeGen (if not installed):
   - `brew install xcodegen`
2. Generate project from spec:
   - `cd JbotSports && xcodegen generate`
3. Open `JbotSports.xcodeproj` in Xcode.
4. Select target `JbotSports Watch App`.
5. Set signing/team.
6. Run on paired Apple Watch (recommended) or watch simulator.

## Notes
- Source of truth for product behavior and UX decisions is `features.md`.
- Reverse/protocol notes are tracked in `reverse.md`.
- Language selection is persisted; full UI language change applies after app restart.
- If you choose to version only `project.yml`, collaborators must run `xcodegen generate` before building.
