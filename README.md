# Engify macOS (MVP)

Native macOS menu bar app that rewrites selected text in any app.

## Flow

1. User highlights text in any app.
2. Press `Control + Shift + E`.
3. App copies selected text via Accessibility keyboard simulation.
4. App calls AI API to polish text.
5. App pastes rewritten text and restores clipboard.

## Requirements

- macOS 13+
- Xcode 15+ command line tools
- Accessibility permission enabled for the app
- AI API key saved in app settings

## Run

```bash
swift run EngifyApp
```

## Configure

Open the menu bar icon:

- Set AI endpoint (OpenAI compatible chat completions endpoint)
- Set model name
- Save API key to Keychain
- Request Accessibility permission

## Notes

- Some apps do not expose selection reliably to copy/paste simulation.
- First launch may require granting permission and relaunching app.
