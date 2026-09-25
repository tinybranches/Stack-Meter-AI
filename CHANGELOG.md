# Changelog

All notable changes to **Stack Meter AI** are documented in this file.  
Add a new section at the top for every release.

Format: version, date, then **Added** / **Changed** / **Fixed** / **Removed**.

---

## 1.8.8 — 2026-09-25

### Fixed

- Claude usage could show ~1% as 100%: web `/usage` returns percents (0–100), and treating `utilization <= 1` as a fraction turned `1` into a full bar. Also show extra weekly windows when present (OAuth/Code, Cowork).

---

## 1.8.7 — 2026-09-24

### Fixed

- Removed the blank Claude WKWebView entirely (Claude.ai/Cloudflare blocks embedded browsers). Login is now Claude Desktop import or paste `sessionKey` from Safari.

---

## 1.8.6 — 2026-09-24

### Fixed

- Claude in-app browser login hanging on a blank white page: stop spoofing Safari’s user-agent, add load watchdog / reload, and surface Claude Desktop + Safari + paste-sessionKey fallbacks in the login window.

---

## 1.8.5 — 2026-09-24

### Added

- Quit confirmation: closing via Quit / ⌘Q asks “Quit Stack Meter AI?” before exiting (uninstall and single-instance exits skip the prompt).

---

## 1.8.4 — 2026-09-24

### Added

- Claude Desktop auto-import: when Claude.app is signed in on this Mac, Stack Meter reads its local session cookies (with a one-time Keychain Allow prompt for “Claude Safe Storage”) — no separate browser login required.

---

## 1.8.3 — 2026-09-24

### Fixed

- Claude authorize could show “authorized” then immediately “session expired”: the app picked the first organization (often the API console org without `chat`) and treated the resulting 403 as an expired session.
- Claude now selects the org with `chat` capability, retries other orgs on permission errors, sends `lastActiveOrg`, and only marks success after a successful usage fetch.

---

## 1.8.2 — 2026-09-24

### Fixed

- Cursor authorize looked successful but usage stayed “session expired”: the dashboard cookie must be `userId%3A%3AJWT` (from the JWT `sub`), not the raw access token alone.
- Cleared the stale “Cursor authorized” status when Keychain session is removed after a failed API check.

---

## 1.8.1 — 2026-09-24

### Added

- Auto-import local sessions on launch: Codex CLI (`~/.codex/auth.json`) and Cursor IDE login are copied into Keychain when Stack Meter has no session yet — so you don’t re-login if those Mac apps are already signed in.
- Clearer auth hints: Safari/Chrome cookies are never shared; use CLI / Cursor IDE / in-app login instead.

---

## 1.8.0 — 2026-09-24

### Removed

- **ChatGPT** provider tab and all GPT-specific usage code (`GPTProvider` / `GPTAPIClient`). Chat and Codex quotas are no longer separate in the API we can call; Codex remains (authorized via ChatGPT login or Codex CLI).

### Changed

- Default providers: Codex, Cursor, Claude. Existing installs drop `gpt` from the enabled list automatically.
- Settings / copy updated: ChatGPT login is only for Codex authorization.

---

## 1.7.1 — 2026-09-24

### Fixed

- ChatGPT tab showing `HTTP 404 Not Found` after login: `conversation/limits` is gone; fall back to `/wham/usage` (same plan windows ChatGPT exposes today, often shared with Codex) and stop duplicating error text in the popover.

---

## 1.7.0 — 2026-09-24

### Added

- Single-instance guard: launching a second copy shows an alert instead of a duplicate menu-bar icon. Same version → “already running”; older version still open → prompt to quit it (or quit from the dialog) before the update continues; newer already running → this older copy exits.

---

## 1.6.9 — 2026-09-24

### Fixed

- Blank placeholder icon in **System Settings → Notifications**: removed `LSUIElement` from Info.plist (Dock still hidden via `setActivationPolicy(.accessory)`), apply `AppIcon.icns` to `NSApp.applicationIconImage` before notification auth, register with Launch Services, and stamp the Finder icon onto the `.app` during packaging.

---

## 1.6.8 — 2026-09-24

### Fixed

- ChatGPT login window hanging on a blank white page during Google OAuth: stop spoofing Safari UA / stuffing popups into the same view; show load spinner + timeout; open real popup windows; promote **Codex CLI** (`codex login` → import) as the reliable path.

---

## 1.6.7 — 2026-09-24

### Fixed

- ChatGPT Google sign-in failing on Passkey / Bluetooth (“devices nearby”) inside the in-app browser: use a persistent web data store, Safari user-agent, handle OAuth popups, and show a hint to use **Another way → password** (or Codex CLI import).

### Changed

- Claude login web view uses the same persistent store + Safari UA for more reliable OAuth.

---

## 1.6.6 — 2026-09-24

### Fixed

- App icon missing in **System Settings → Notifications** (and related system lists): the App Icon asset catalog was never compiled into `Assets.car` because XcodeGen ignored `Branding/Assets.xcassets`. The catalog now lives under `AIBar/Assets.xcassets` and the package script fails if `Assets.car` is missing.

---

## 1.6.5 — 2026-09-24

### Added

- Settings button to allow notifications after declining the first-launch prompt (“Not Now”)
- Network request timeouts (20s) on all provider APIs

### Changed

- Provider refreshes run off the main thread so the menu bar stays responsive
- Overlapping refreshes are queued instead of racing
- Notification evaluation uses cached permission (no Notification Center hit every poll)
- Uninstall only removes known Library paths (no full `~/Library` walk)
- Packaging guards staging so the Applications symlink cannot create nested junk copies
- Icon pipeline writes only to `Branding/` (dropped unused `AIBar/Resources` / mirrored asset duplicates)

### Fixed

- Cursor authorize no longer blocks the UI while reading `state.vscdb` via `sqlite3`
- ChatGPT / Claude login wait loops can stack and keep running after sign-out — now a single cancellable task
- Claude cookie polling could retain the login coordinator after the window closed
- API clients treated the first `401` as fatal before trying alternate endpoints
- GPT unauthorized responses no longer wipe the shared ChatGPT Keychain session when Codex may still be valid
- Codex local rollout/token scan capped to avoid long hangs on huge `~/.codex/sessions` trees
- `tccutil` during uninstall no longer runs synchronously on the UI thread

---

## 1.6.4 — 2026-09-24

### Added

- In-app path to re-enable notifications from Settings when the user previously chose “Not Now”

---

## 1.6.3 — 2026-09-24

### Added

- First-launch notification consent dialog (no silent registration with Notification Center)

---

## 1.6.2 — 2026-09-24

### Changed

- Replaced overflowing orange auth badge with green / orange / red status dots on provider tabs and the tray icon

---

## 1.6.1 — 2026-09-24

### Fixed

- App icon visibility in System Settings → Notifications
- Full uninstall wipe of Library leftovers and best-effort notification TCC reset

---

## 1.6.0 — 2026-09-24

### Added

- ChatGPT (GPT) provider sharing the Codex/ChatGPT login session
- Codex browser login + CLI `auth.json` import
- Claude and Cursor authorization flows
- App and DMG volume icons

### Changed

- Product branding toward **Stack Meter AI** (bundle `com.stackmeter.ai`)
- Installer flow simplified to DMG → drag to Applications

---

## Earlier

Internal builds under the previous **AI Bar** name; superseded by Stack Meter AI 1.6.x. Prefer a clean install / in-app Uninstall if old leftovers appear in Notifications.
