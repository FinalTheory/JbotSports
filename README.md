# tennis_ctl (watchOS)

This folder contains a watchOS SwiftUI implementation scaffold for the features in `features.md`.

## Included
- BLE pairing screen (scan + connect)
- 3-page operation UI
  - Page 1: Start / Stop / Frequency +/-
  - Page 2: Top/Bottom speed +/- , Height +/- , Spin slider (0 centered)
  - Page 3: Preset list (single active), apply on tap, edit with pencil
- Preset editor
  - Edit ball order as space-separated numbers
  - Random vs Sequential toggle
  - Validation for invalid tokens / out-of-range numbers

## Protocol
- Implemented for confirmed device branch: **V6**
- Uses FF10/FF11/FF12 BLE UUIDs
- Command builder supports: `START6`, `STOP`, `FREQUENCY`, `SHORT_ANGLE`

## How to use in Xcode
1. Create a new watchOS App project in Xcode (`tennis_ctl`).
2. Remove default Swift files.
3. Drag all `.swift` files from this folder into the watch target.
4. Add `Privacy - Bluetooth Always Usage Description` in target Info.
5. Run on Apple Watch or paired simulator.

## Notes
- Presets are local in-memory seed data for now.
- Selecting a preset sends full `START6` packet immediately.
- Spin slider range auto-limits so resulting wheel speeds stay in `0...100`.
