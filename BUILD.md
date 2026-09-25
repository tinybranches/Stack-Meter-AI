# Building Stack Meter AI (DMG)

How to produce a distributable `.dmg` from this repository on a Mac.

## Prerequisites

| Tool | Notes |
|------|--------|
| **macOS 14+** | Deployment target of the app |
| **Xcode 16+** | Command Line Tools must work (`xcodebuild`) |
| **XcodeGen** | `brew install xcodegen` |
| **Python 3** | For icon generation (`scripts/generate_icons.py`) |
| **Pillow** | `pip3 install pillow` (needed by the icon script) |

Optional:

- **SetFile** (Xcode CLT / legacy) — used to set the DMG volume custom-icon bit; if missing, the script falls back to Python/`xattr` when available.

Accept the Xcode license once if needed:

```bash
sudo xcodebuild -license accept
xcode-select -p   # should point at Xcode.app
```

## One-command DMG (recommended)

From the repo root:

```bash
chmod +x scripts/package.sh   # once
./scripts/package.sh
```

Result:

```text
dist/Stack-Meter-AI-<MARKETING_VERSION>.dmg
```

Example for `1.6.5`: `dist/Stack-Meter-AI-1.6.5.dmg`

Open the DMG and drag **Stack Meter AI** into **Applications**.

### What `package.sh` does

1. Regenerates app + volume icons (`scripts/generate_icons.py`)
2. Runs `xcodegen generate` from `project.yml`
3. Builds scheme **Package** / configuration **Release** via `xcodebuild`
4. Ensures `AppIcon.icns` is inside the `.app` bundle
5. Stages the app + `/Applications` symlink
6. Creates a compressed UDZO DMG with volume name `Stack Meter AI <version>`
7. Sets the volume icon and the Finder icon on the `.dmg` file

Build artifacts go under `build/` (gitignored). The final installer is `dist/Stack-Meter-AI-<version>.dmg` — **only the latest** DMG is kept (older ones are deleted by `package.sh`).

## Version number

Edit [`project.yml`](project.yml) before packaging:

```yaml
CURRENT_PROJECT_VERSION: 12    # integer build (CFBundleVersion)
MARKETING_VERSION: "1.6.5"     # user-facing (CFBundleShortVersionString)
```

Then:

1. Add a section at the top of [`CHANGELOG.md`](CHANGELOG.md)
2. Run `./scripts/package.sh`

The DMG filename always uses `MARKETING_VERSION`.

## Dev build (no DMG)

Run / debug from Xcode without packaging:

```bash
xcodegen generate
open AIBar.xcodeproj
```

- Scheme **AIBar** → Debug (day-to-day)
- Scheme **Package** → Release (same config the DMG script uses)

Or from the terminal:

```bash
xcodegen generate
xcodebuild \
  -project AIBar.xcodeproj \
  -scheme AIBar \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  build
```

The Debug app lands in `build/DerivedData/Build/Products/Debug/Stack Meter AI.app`.

## Signing

`package.sh` signs with **Sign to Run Locally** (`CODE_SIGN_IDENTITY="-"`). That is enough to run on your Mac after dragging to Applications.

For distribution outside your machine (Gatekeeper / notarization), you need an Apple Developer ID and extra steps (not covered by the script yet):

1. Sign with your **Developer ID Application** certificate  
2. Notarize with `notarytool`  
3. Staple the ticket to the app or DMG  

Until then, other users may need **Right-click → Open** the first time, or you ship a notarized build separately.

## Icons only

```bash
python3 scripts/generate_icons.py
```

Writes:

- `Branding/AppIcon.icns` + `Branding/Assets.xcassets`
- `Design/icons/VolumeIcon.icns` (+ PNG masters)

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `xcodegen: command not found` | `brew install xcodegen` |
| `pillow` / PIL import error | `pip3 install pillow` |
| `xcodebuild` fails on license / SDK | Install Xcode from the App Store; run `sudo xcodebuild -license` |
| App has no icon in Notifications | Confirm the app has `Contents/Resources/Assets.car` + `AppIcon.icns`, and Info.plist does **not** set `LSUIElement` (Dock is hidden at runtime). Reinstall from a fresh DMG, then reset the stale Notifications row: `tccutil reset Notifications com.stackmeter.ai`, quit System Settings, relaunch the app and allow notifications again. |
| DMG mounts but Applications link is wrong | Staging must contain only the `.app` and an `Applications` **symlink** — re-run the script from a clean tree (`rm -rf build/dmg-staging`) |
| Gatekeeper blocks the app | Expected for ad-hoc signed builds; use Right-click → Open, or notarize |

## Layout reference

```text
project.yml              # version + XcodeGen project definition
scripts/package.sh       # Release build → DMG
scripts/generate_icons.py
Branding/AppIcon.icns    # embedded in the .app
Design/icons/VolumeIcon.icns
dist/                    # latest release DMG only (older versions removed by package.sh)
build/                   # DerivedData + staging (gitignored)
CHANGELOG.md             # note each release here
```
