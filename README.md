# Engify macOS (MVP)

Native macOS menu bar app that rewrites selected text in any app.

## Flow

1. User highlights text in any app.
2. Press `Command + E` (or `Shift + Command + E`).
3. App copies selected text via Accessibility keyboard simulation.
4. App calls AI API to polish text (input is limited to 500 characters).
5. App pastes rewritten text and restores clipboard.

## Requirements

- macOS 13+
- Xcode 15+ command line tools
- Accessibility permission enabled for the app

## Run

```bash
swift run Engify
```

## Build

```bash
swift build
```

Production build:

```bash
swift build -c release
```

## Release Script

Use `scripts/release.sh` to package the app into `.app` and `.dmg`.

The generated DMG includes `Engify.app` and an `Applications` shortcut so users can drag-and-drop install in Finder.

Show all options:

```bash
zsh scripts/release.sh --help
```

Main options:

- `--version <value>`: Set app version in Info.plist
- `--bundle-id <value>`: Set bundle identifier
- `--app-name <value>`: Set app name and DMG volume name
- `--binary-name <value>`: Override release binary name
- `--output-dir <path>`: Set output folder
- `--sign-identity <value>`: Use Developer ID signing instead of ad-hoc signing
- `--notary-profile <value>`: Notarize and staple DMG (requires `--sign-identity`)

## Accessibility Setup

Open the menu bar icon:

- Request Accessibility permission

## Create Installable App (Local)

This creates a `.app` bundle and a `.dmg` for local install/testing.

Recommended one-command flow:

```bash
zsh scripts/release.sh
```

Custom version:

```bash
zsh scripts/release.sh --version 1.0.1
```

Output artifacts:

- `dist/Engify.app`
- `dist/Engify.dmg`

## Release App (Production)

For public distribution (without Gatekeeper warnings), use Developer ID signing and notarization.

Recommended one-command flow:

```bash
zsh scripts/release.sh \
	--version 1.0.0 \
	--bundle-id dev.lupmit.engify \
	--sign-identity "Developer ID Application: YOUR NAME (TEAMID)" \
	--notary-profile "YOUR_NOTARY_PROFILE"
```

## Notes

- Some apps do not expose selection reliably to copy/paste simulation.
- First launch may require granting permission and relaunching app.
