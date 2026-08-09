# NovaGram upstream policy

Every distributable NovaGram build MUST be based on the newest source published
by the official Telegram repositories.

## Required upstreams

- Desktop: `https://github.com/telegramdesktop/tdesktop.git`; the highest
  semantic `vX.Y.Z` tag (including the current public beta/release line).
- Android: `https://github.com/DrKLO/Telegram.git`; the current
  `refs/heads/master` commit, which is the latest officially published Android
  source snapshot.

`scripts/check-upstream.ps1` is a mandatory pre-build gate. Each build script
calls it before configuration or compilation. It fetches the relevant official
upstream at least once every 24 hours and verifies that the selected upstream
commit is an ancestor of the local NovaGram base.

If upstream is newer, the build MUST stop. Upstream updates are integrated and
reviewed explicitly; build scripts MUST NOT automatically merge or rebase a
dirty privacy fork. After integration, run:

```powershell
.\scripts\check-upstream.ps1 -Project All -Force
```

The transient check timestamp is stored in `.analysis/upstream-check.json`.
Deleting it forces a fresh network check on the next build.

Desktop release builds also require the pinned local LLVM/LLD toolchain from
`scripts/build-desktop.ps1`; silently falling back to Microsoft's `link.exe` is
not allowed because its peak memory use is unsuitable for this workstation.
