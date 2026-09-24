# Changelog

All notable changes to **Stack Meter AI** are documented in this file.  
Add a new section at the top for every release.

Format: version, date, then **Added** / **Changed** / **Fixed** / **Removed**.

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
