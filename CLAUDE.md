# NovaGram — agent rules

Privacy-hardening fork of Telegram for Windows (C++/Qt 5.15.19, tdesktop) and Android
(Java/Gradle, Telegram Android). Two submodules; one release ships both, tagged
`v<PC base>/<Android base>`. Ships an Inno Setup `.exe` and a single fat `.apk`.

## Commands
| Task | Command | cwd |
|---|---|---|
| build desktop | `.\scripts\build-desktop.ps1 -Config Release` | repo root |
| build Android (release, R8, ~20 min) | `.\scripts\build-android.ps1` | repo root |
| build Android (iterate, debug, ~3.5 min) | `.\scripts\build-android.ps1 -Fast` | repo root |
| upstream gate (auto-run by both builds) | `.\scripts\check-upstream.ps1 -Project All -Force` | repo root |
| package + sign installer | `.\scripts\package-desktop-inno.ps1` | repo root |

PowerShell only. Secrets live in `.novagram.local.ps1` (gitignored); both build scripts
throw without `NOVA_TELEGRAM_API_ID` / `NOVA_TELEGRAM_API_HASH`.

## Never
- Never read, copy, print or edit anything under `keys/`, and never put a secret into
  `.novagram.local.example.ps1` or any tracked file.
- Never run `git submodule update` / `--remote` here: `.git/modules` does not exist, both
  submodule trees are standalone clones, and `.gitmodules` names branches that differ from
  the ones checked out. Work inside the submodule directories directly.
- Never read these whole — grep, then read the located range: `android-release.log`
  (620 KB), `docs/doh.md` and `.claude/kb/_legacy-roadmap.md` (~50 KB each), and the two
  submodule roadmaps `desktop/novagram-desktop/docs/NOVAGRAM_DESKTOP_ROADMAP.md` /
  `android/novagram-android/docs/NOVAGRAM_PRIVACY_ROADMAP.md` (~100 KB each, stale).
- Never bump the desktop version by editing `Telegram/build/version` alone — the version
  compiles from generated-but-committed `core/version.h`, and `set_version.py` corrupts the
  fourth digit. See G1.
- Never ship an Android build that was only built with `-Fast`: only R8 catches a class
  reachable solely through an upstream hook. Never let a desktop release link with MSVC
  `link.exe` instead of the pinned LLVM/LLD.
- Never mark a feature `ok`/`Проверено` because it compiled — that word means it was run on
  a real account or device.

## Context
`ROADMAP.md` is the project state — read it once before substantive work. Deep detail is in
`.claude/kb/`, indexed at the end of ROADMAP.md. Both are English and for agents only.

User-facing docs — `README.md`, `UPSTREAM_POLICY.md`, `docs/*.md` — are not duplicated into
the knowledge base. Most are Russian, but `UPSTREAM_POLICY.md`, `docs/build.md`,
`docs/privacy.md`, `docs/privacy-push.md` and `docs/upstream-sync.md` are written in English.
Keep each file in the language it is already in; do not translate in either direction.
