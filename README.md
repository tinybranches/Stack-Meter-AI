# Stack Meter AI

Menu-bar utility for macOS that shows how much of your AI plan you have left — for **Codex**, **Cursor**, and **Claude** — without opening each product’s dashboard.

## How it works

1. **Lives in the menu bar**  
   No Dock icon. A sparkle icon shows a status dot (green / orange / red) and optionally the used % for the selected provider.

2. **You authorize each account once**  
   Credentials are stored in the macOS Keychain (not in the app folder).  
   - **Codex** — ChatGPT account login (in-app browser) or import from Codex CLI `~/.codex/auth.json`  
   - **Cursor** — reads the local Cursor IDE session (`state.vscdb`) and copies the token into Keychain  
   - **Claude** — sign in via Claude.ai in an in-app browser; the `sessionKey` cookie is saved  

3. **It polls usage APIs on a timer** (default every 60s, adjustable in Settings)  
   Each enabled provider is fetched in the background so the menu bar stays responsive.  
   - Codex → ChatGPT backend usage (`/wham/usage`)  
   - Cursor → `cursor.com` usage summary  
   - Claude → organization usage windows (5h / weekly / model caps)  

4. **Popover shows the details**  
   Click the menu-bar icon to see rate-limit windows, remaining %, reset times, credits/spend, and tokens when available. Switch providers with the tabs.

5. **Optional notifications**  
   On first launch the app asks permission (no silent registration). If you choose “Not Now”, you can enable later in **Settings → Notifications**.

6. **Settings**  
   Poll interval, tray %, language (System / English / Українська), providers on/off, account sign-out, and full uninstall.

```
┌─────────────┐     authorize      ┌──────────┐
│  Menu bar   │ ─────────────────► │ Keychain │
│  sparkle +% │                    └──────────┘
└──────┬──────┘                          │
       │ poll (background)               │ tokens
       ▼                                 ▼
┌─────────────┐   HTTPS / local DB   ┌──────────────┐
│  Providers  │ ◄──────────────────► │ Codex/Cursor │
│  registry   │                      │ /Claude      │
└──────┬──────┘                      └──────────────┘
       │ snapshots
       ▼
┌─────────────┐     optional      ┌──────────────┐
│   Popover   │ ───────────────► │ Notifications│
│  + Settings │                  └──────────────┘
└─────────────┘
```

## Features

- Menu bar only — lightweight, always visible  
- Per-provider usage % with color thresholds  
- Codex via ChatGPT account session  
- Auto-refresh, UK/EN localization  
- Explicit first-launch notification consent  
- Clean uninstall from Settings  

## Requirements

- macOS 14+  
- To build from source: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Install

### From DMG (recommended)

1. Open `dist/Stack-Meter-AI-<version>.dmg` (or build one — see [`BUILD.md`](BUILD.md))  
2. Drag **Stack Meter AI** into **Applications**  
3. Launch from Applications  

To update later: drag the new app over the old one and replace. Settings and Keychain credentials stay.

### Build a DMG

Full guide: **[`BUILD.md`](BUILD.md)**.

```bash
./scripts/package.sh
```

### Dev run

```bash
xcodegen generate
open AIBar.xcodeproj
```

Scheme **AIBar** → Run.

## Authorize

| Provider | How |
|----------|-----|
| **Codex** | ChatGPT login (browser), or import Codex CLI `~/.codex/auth.json` |
| **Cursor** | Local Cursor IDE login → Keychain |
| **Claude** | Sign in at Claude.ai in the app browser |

**Sign out** is in Settings per account.

## Uninstall

**Settings → Danger zone → Uninstall** clears Keychain + preferences and removes the app from `/Applications` if present.

## Version & changelog

- Version numbers live in [`project.yml`](project.yml)  
- Release notes: **[`CHANGELOG.md`](CHANGELOG.md)**  
- How to build the DMG: **[`BUILD.md`](BUILD.md)**  

## Icons

```bash
python3 scripts/generate_icons.py
```

- App: `Branding/AppIcon.icns`  
- DMG volume: `Design/icons/VolumeIcon.icns`  

## License

See repository for license terms.
