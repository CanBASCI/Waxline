# Waxline

Native iOS paper strategy game. Cream washi board, red and indigo wax seals, 3D SceneKit table, Game Center turn-based 1v1.

## Requirements

- Xcode 16 or later (this project was created with Xcode 26)
- iOS 18.0+
- Apple ID signed into Xcode (team `39UPTB46U5` is already set)
- Game Center 1v1 needs Game Center enabled on the App ID in the Apple Developer portal and on a real device or the Simulator with a sandbox Game Center account

## Run

1. Open `Waxline.xcodeproj` in Xcode.
2. Select an iPhone simulator or a device.
3. Press Run (⌘R).

Command line:

```bash
xcodebuild -scheme Waxline -destination 'platform=iOS Simulator,name=iPhone 16' test
```

If no simulator named iPhone 16 exists, list destinations with `xcodebuild -scheme Waxline -showdestinations`.

## Modes

- **Pass & Play** — two players on one device
- **Play vs AI** — Easy / Medium / Hard (set the default in Settings)
- **Game Center 1v1** — turn-based matchmaking; Red is participant 0, Indigo is participant 1

## Localization

User-facing copy lives in a string catalog:

- File: `Waxline/Localizable.xcstrings`
- Source language: English (`en`)
- Shipped language: Turkish (`tr`)
- Runtime default: system locale
- In-app override: Settings → Language → System / English / Turkish

Keys are stable identifiers such as `onboarding_place`, `turn_red`, `you_win`, `draw`, `rotate_hint`, `settings_title`. Views look them up with `String(localized:)` (via `L10n.text`) and never hardcode UI copy.

### Add a language

1. Open `Waxline/Localizable.xcstrings` in Xcode.
2. Select the catalog, click **+** under Localizations, and add the language (for example `de`).
3. Fill in every key. Keep `extractionState` as `manual` for existing entries.
4. Add the language code to `knownRegions` in the Xcode project if Xcode does not do it automatically.
5. Optionally extend `LanguageOverride` in `Waxline/Models/GameTypes.swift` if the new language should appear in Settings.

## Tests

Unit tests live in `WaxlineTests/GameRulesTests.swift` and cover:

- 90° rotation of each quadrant, both directions
- Wins that span two quadrants (row, column, diagonal)
- Double five-in-a-row after a rotation → draw
- Full board with no five-in-a-row → draw

```bash
xcodebuild -scheme Waxline -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Bundle

- Bundle ID: `com.api.Waxline`
- Display name: Waxline

## Android

Not in this first slice. iOS, 3D board, and Game Center 1v1 ship first. The board model (`BoardModel`, `WinChecker`, rotation) is the shared rules surface to port later.
