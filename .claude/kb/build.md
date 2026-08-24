# Build, toolchain, packaging, release
Expands G1-G8, I9-I11, M5, M23-M28, S18. Read before touching a build script, a version
number, or shipping a release.

The repo's own build notes are `docs/build.md` — layout, package name, keystore path, Qt
pinning, decoy testing with `-workdir`, PIN state files. It is written in **English**, not
Russian, despite D11 (G26): the only Cyrillic in its 6.7 KB is the cross-reference to the
heading "Версия Qt". P9 edits this file — do not translate it while doing so. This file
holds what is NOT there: the release procedure, measurements, and the traps that cost
shipped builds.

## Invocation

```powershell
.\scripts\build-desktop.ps1 -Config Release      # PC
.\scripts\build-android.ps1                      # Android release (R8, ~20 min)
.\scripts\build-android.ps1 -Fast                # Android debug, no R8, ~3.5 min
.\scripts\check-upstream.ps1 -Project All -Force # force a fresh upstream check
.\scripts\package-desktop-inno.ps1               # installer, signing mandatory
.\scripts\build-desktop.ps1 -Prepare -PrepareOnly # first dependency bootstrap
```

Secrets come from `.novagram.local.ps1` (gitignored; template in
`.novagram.local.example.ps1`): `NOVA_TELEGRAM_API_ID`, `NOVA_TELEGRAM_API_HASH`,
`NOVAGRAM_ANDROID_KEYSTORE`, `NOVAGRAM_PFX`, `NOVAGRAM_PFX_PASSWORD`. Both build scripts
dot-source it and throw if the api id/hash are missing. `build-android.ps1` writes them
into `android/novagram-android/local.properties` on every run.

Both build scripts call `scripts/check-upstream.ps1` as their first statement. It fetches
the official upstream at most once per 24 h (state in `.analysis/upstream-check.json`;
delete the file to force a network check) and fails the build if the official commit is not
an ancestor of the local base. Desktop picks the highest semantic `vX.Y.Z` tag by parsed
numbers, not string order, so `v7.0.10` is not treated as older than `v7.0.9`. Android
takes the current `upstream/master`. No automatic merge or rebase — `UPSTREAM_POLICY.md`
forbids scripts touching a dirty privacy fork.

## Pinned toolchain (desktop)

```
Visual Studio 2026 Build Tools, MSVC 14.44, Windows SDK 10.0.26100.0
Python 3.10.11 · CMake 3.31.12 · Ninja 1.13.1 · NASM 3.01 · YASM 1.3.0
Qt 5.15.19, built by Telegram's own prepare script — same as the official client
LLVM/LLD 22.1.7 at D:\Programs\LLVM-22.1.7 (hardcoded in build-desktop.ps1)
Toolchain root D:\Programs\BuildTools
```

CMake 4.4.0 is installed on this machine but must not be used for tdesktop: it trips
upstream's `-Werror=dev` policy checks.

`UPSTREAM_POLICY.md` makes the pinned LLVM/LLD mandatory for release builds — silently
falling back to Microsoft's `link.exe` is not allowed, its peak memory is unsuitable for
this workstation. `-MsvcLink` exists as a deliberate escape hatch only.

## Measurements

- Desktop, one file changed plus link: **4 min 34 s**.
- Android `-Fast` (debug, no R8): **3 min 29 s**.
- Android release (with R8): **20 min 33 s**. The root `android-release.log` records one
  full-from-scratch release at **47 min 54 s**, `BUILD SUCCESSFUL`.
- The desktop link holds **16-18 GB** of RAM. Nothing heavy may run alongside it.
- `MaxParallelJobs` / `MaxWorkers` default to 6 of the 8 cores; the final link is
  single-threaded, so a higher number shortens compilation without raising link peak.

### G6 — the linker was never actually LLD

`-DCMAKE_LINKER=lld-link` does **nothing** on its own. It sat in the script for a long time
while MSVC `link.exe` did the linking, with no mention of lld anywhere in `build.ninja`.
The knob CMake actually reads is `CMAKE_LINKER_TYPE=LLD` (CMake 3.29+). Setting it dropped
the link pass from ~15 minutes to ~4.5. Who is linking is visible in the error line prefix
(`lld-link:` vs `LINK :`), **not** by searching `build.ninja`.

## Release procedure

1. `scripts/check-upstream.ps1 -Force` (the check is cached for 24 h).
2. Raise versions. On desktop that is **three** files — see G1.
3. Build the **release** Android APK (only that runs R8), package, sign, publish. The
   release description is short and carries **no heading in the body** — GitHub draws it.
4. While Android is still manifest-driven, trigger the manifest workflow by hand:
   `gh workflow run "Publish NovaGram update manifests" -R confeden/nova_updates`
   (`gh` is not on PATH; it lives at `C:\Program Files\GitHub CLI\gh.exe`). The workflow
   runs every six hours and skips drafts; until it has run, Android honestly reports "you
   have the latest version". **Desktop no longer needs this step** — it reads GitHub
   releases directly.

### Release/tag scheme

The fork has no version numbering of its own: each platform's version *is* the Telegram
version it was built from. One release covers both platforms and the tag carries both
bases: `v<PC base>/<Android base>`, e.g. `v7.0.9.3/12.9.2.3`. Each client compares **only
its own half**, so a release that only moved one base is not an update for the other. A
release containing only NovaGram-side changes is visible to clients only if the fourth
digit is incremented.

A slash in a tag is legal for both git and GitHub and is escaped as `%2F` in URLs; both
clients do this. The full tag is written by hand in exactly two places:
`kReleaseTag` in `novagram/nova_branding.cpp` and `NovaUpdateChecker.RELEASE_TAG`. The tag
is not validated by the program: forget to bump it and the About window shows the old one.

`packaging/updates/*.json` in this repo are **placeholders** (`"version": "0.0"`). The live
manifests are in `confeden/nova_updates`; this directory version-controls the format, the
workflow and the generator script only. `packaging/updates/README.md` documents the format.

## G1 — desktop version does not reach the binary (cost one release)

Editing `Telegram/build/version` is **not enough**. The version is compiled from
`core/version.h`, a generated file that is committed and does not regenerate itself. The
build called itself `7.0.9.1` while the manifest said `7.0.9.2`, so the update prompt
looped forever.

`build/set_version.py` is **unusable** for this fork's scheme: it reads the fourth digit as
a closed alpha, resets `AppVersionStr` to `7.0.9` and writes
`TDESKTOP_REQUESTED_ALPHA_VERSION`. Run it only to regenerate the `.rc`, then fix
`version.h` and `build/version` by hand.

**One-line pre-release check:** the log must contain
`NovaGram update: release says X, installed X, not newer`
(`novagram/nova_update.cpp:411`). The key word is **`release`**, not `manifest`: desktop
stopped reading the update manifest and now queries
`api.github.com/repos/confeden/Novagram/releases/latest` (`nova_update.cpp:46-47`, S11,
release-procedure step 4), and the log line moved with it. Grepping the old wording finds
nothing, which makes a good release look unverifiable and a bad one look fine — the whole
point of this gate is that it is one grep. Android has no equivalent trap.

## G2 — `ANDROID_PLATFORM` != `minSdkVersion` (cost three shipped builds)

`TMessagesProj/build.gradle` had `android-34` where upstream has `android-21`. From API 29
clang emits `R_AARCH64_TLSDESC` relocations for `thread_local`, and bionic only learned to
resolve them in Android 12. On anything older the descriptor stays zero and the first read
of such a variable jumps to address 0.

Symptom: `SIGSEGV, pc=0` on `Thread-19` about a second after start, no Java exception, a
one-frame backtrace. **arm64 only** — clang does not enable TLSDESC for 32-bit ARM or x86,
which is why it looked like "some people". The manifest still honestly said `minSdk 23`,
the APK installed, and nothing warned.

Rule: `ANDROID_PLATFORM` moves only together with `minSdkVersion` and never above it.
One-command check: `llvm-readelf -r libtmessages.*.so | grep TLSDESC` must print nothing.

Fixed in release `v7.0.9.3/12.9.2.3`. Affected users cannot self-update — the client dies
before the update check runs; the APK must be reinstalled by hand, and the release
description says so.

## G3 — R8 strips classes reachable only from an upstream hook

`NovaUpdateLayout` is constructed exclusively through `takeUpdateLayout`; nothing inside the
library references it, and the release fails at `minifyAfatReleaseWithR8` with
"Missing class". Cured by a `-keep` line in `TMessagesProj/proguard-rules.pro`. A debug
build never catches this — which is why a release build stays mandatory before shipping.

## G4 — link cannot write `NovaGram.exe`

`LNK1104` under MSVC, `permission denied` under lld
(`lld-link: error: failed to write output 'NovaGram.exe': permission denied`) means a client
started from `out/` is still running. The *installed* copy does not interfere; only
`out/*.lnk` needs closing. This has cost three runs — clients stay open after testing.
The same running client also holds `out/log.txt`, so configure fails too.

## G5 — a failed build reported success

The generated `.cmd` ended with `exit /b %errorlevel%`, but the batch file is the top level
of `cmd /c`: with `/b` the code never reached PowerShell, ninja stopped on a link error and
the script reported success. Replaced with plain `exit`. Lesson: trust an exit code only
after you have seen it be non-zero at least once.

## G7 — interrupted desktop link leaves a truncated binary

An aborted link leaves a ~2 MB `out/NovaGram.exe` that will not start until rebuilt. The
usual cause is memory pressure (see the 16-18 GB figure above).

## G8 — other desktop build traps

- Always build through `scripts/build-desktop.ps1`. A direct `ninja -C out` fails: the
  CMake cache stores `CMAKE_C_COMPILER=cl`, which only resolves inside the `vcvars64.bat`
  environment the script sets up. A direct call makes CMake re-run, fail to find `cl` and
  Ninja, and truncate `out/CMakeCache.txt`, after which the next configure rebuilds
  everything.
- Switching Qt version needs a clean `out/`. Generated `moc_*.cpp` carry the version of the
  moc that produced them; mixing gives
  `fatal error C1189: "This file was generated using the moc from 5.15.19."`.
  Find stale ones with `grep -rl "5\.15\.19" --include="moc_*.cpp" out`.
- Clear `out/` **by hand** and keep `tdata`. Do **not** use `-ForceConfigure` for this:
  `cmake/run_cmake.py` deletes everything in the build directory except entries starting
  with `debug` or `release`, taking the working profile `out/tdata` with the signed-in
  account with it.
- `vcvars64.bat` calls `vswhere.exe` by bare name. A tooling-started shell does not have
  `C:\Program Files (x86)\Microsoft Visual Studio\Installer` on PATH and vcvars fails with
  `'vswhere.exe' is not recognized`. `build-desktop.ps1` prepends that directory itself.
- Do not pass `-Qt6` for released builds — see N10 in ROADMAP.

## Signing and outputs

`package-desktop-inno.ps1` throws before it ever calls ISCC unless `NOVAGRAM_PFX` points at
an existing file and `NOVAGRAM_PFX_PASSWORD` is non-empty: without both, no installer is
produced at all. It then signs with `signtool sign /fd SHA256`. ISCC lives at
`D:\Programs\Inno Setup 6\ISCC.exe`, the script is
`desktop/novagram-desktop/packaging/novagram.iss`, output goes to `dist/`.

Artifacts in `dist/` (gitignored): `NovaGramSetup-<ver>-x64.exe` ~51 MB,
`NovaGram-<ver>-release.apk` ~143 MB (one APK for arm64/arm32/x86/x86_64), plus
`release-notes-*.md` per release.

## Testing without destroying the working profile

`out/NovaGram.exe` accepts `-workdir`, so the decoy can be exercised against a throwaway
profile while `out/tdata` with the signed-in account stays put. A directory whose `tdata`
contains a `novagram_decoy` file is enough — an empty file works, the client generates the
seed and time anchor on first start.

```bash
mkdir -p out/decoytest/tdata && touch out/decoytest/tdata/novagram_decoy
```

Do not swap `out/tdata` aside instead: a half-finished swap loses the signed-in account.

Entering the emergency PIN on a locked cold start erases everything in that `tdata` except
`temp` and `tdummy`, so back the directory up before testing it.

Desktop PIN state lives in `tdata/novagram_pin` next to `tdata/key_data`. Deleting that
file removes the emergency PIN and the persistent lockout counter, but not the primary PIN
— the primary PIN is upstream's local passcode and lives in `tdata/key_data`.

## Stale root logs

`android-release.log`, `desktop-build.log` and `desktop-build.err` at the repo root are from
the `v7.0.9` build (2026-08-09), not the current release. `android-release.log` ends
`BUILD SUCCESSFUL in 47m 54s`; `desktop-build.log` ends at `[74/75] Linking CXX executable
NovaGram.exe`; `desktop-build.err` contains only a harmless CMake extra-path warning and
`Version: 7.0.9`. All three are gitignored (`/*.log`, `/*.err`). Triage them with `tail` and
`grep -E "BUILD (SUCCESSFUL|FAILED)|FAILURE:|error"`, never read whole —
`android-release.log` is 620 KB / 5400 lines.

## G28 — an upstream merge leaves work the merge itself does not do

A merge commit records new submodule pins and new project references. It does not check
anything out and does not declare anything. Both platforms failed on this, and both failures
point at code that looks like a bad conflict resolution but is not.

### Desktop — every gitlink must be checked out to what HEAD records

Symptom, in the style codegen, long before any of the merged files compile:

```
calls/calls.style(28): error 805: struct 'CallButton' already defined
```

Then, once that is fixed, `error C3861: 'cmark_parser_set_allocation_abort_flag': identifier
not found`.

Cause: `v7.1.1` moved nine submodule pins. The working copies stayed where `v7.0.9` had them,
so the tree was half-new: `v7.1.1` sources against `v7.0.9` libraries. `CallButton` had moved
out of `lib_ui/ui/widgets/widgets.style` into `calls.style`, so with the old `lib_ui` checked
out it existed twice.

Fix — list the drift, then check each one out. `git submodule status` is not trustworthy here
(G25), so read the gitlinks straight out of the tree:

```bash
git ls-tree -r HEAD | awk '$1=="160000"{print $3" "$4}' | while read sha path; do
  cur=$(cd "$path" && git rev-parse HEAD 2>/dev/null)
  [ "$cur" != "$sha" ] && (cd "$path" && git checkout -q "$sha")
done
```

The four `Telegram/lib_*` submodules are direct children; `Telegram/ThirdParty/*` and the
top-level `cmake` are not, so a non-recursive `ls-tree` finds only half of them. That is why
the desktop build failed twice: the first sweep missed `cmark-gfm`, `MicroTeX`, `hunspell`,
`rlottie` and `cmake`. Verify all four `lib_*` trees are clean first — D1 says the fork does
not patch them, and a checkout would discard anything that was there.

### Android — 12.10.0 does not configure as published

```
Project with path ':jlatexmath' could not be found in project ':TMessagesProj'.
```

Upstream added `api project(':jlatexmath')` to `TMessagesProj/build.gradle` and never
declared the project anywhere - its own `settings.gradle` does not mention it either. The
fork declares it in the root `settings.gradle`, pointing at the inner library module of the
`TMessagesProj/lib/jlatexmath` submodule (not the submodule root, which is a parent project
with a sample app and two optional font packs).

12.10.0 also needs submodules nothing referenced before:

| Submodule | Why it is needed now |
|---|---|
| `TMessagesProj/lib/jlatexmath` | the Java library above |
| `TMessagesProj/jni/tlottie` | headers for the prebuilt Rust lottie library that replaced the in-tree `rlottie` sources; the `.a` files themselves are committed under `jni/tlottie_lib/<abi>/` |
| `jni/third_party/xiph/{ogg,opus,opusfile}` | the native build now compiles them from source |

`ffmpeg`, `dav1d` and `libvpx` are still unreferenced and stay empty - do not init them.

### Other things this merge moved

- Gradle went to **8.11.1**. The very first run after the bump died with `Could not connect
  to the Gradle daemon` while the daemon's own log said it had started. Plain retry worked;
  do not go looking for a cause.
- Upstream added `mtproto/web_proxy/*` to the desktop tree - a transport that talks through
  a webview. P8 (Cloudflare WSS) should be re-scoped against it before any code is written.
- Version numbering: the base moved, so the fork version is the bare base on both sides -
  `7.1.1` and `12.10.0`, no fourth digit. The digit only counts fork iterations on an
  unchanged base.

### What it cost

Android full rebuild, four ABIs from cold: **2 h 10 min**. Desktop full rebuild: about the
same, of which the final link is ~15 min. Neither can be shortened after a merge this size,
and they must not be run at the same time.

## G29 — CRLF in the theme assets makes every dark theme unreadable

Symptom, on every Android device and both OS versions tested: the day theme is perfect, any
dark theme draws a pure black screen with no text at all. Only things painted with a
hardcoded colour survive - white text on a blue button, the outgoing bubble. Nothing is
logged; there is no crash and no stack trace.

### The chain

1. The colours of every built-in theme except the default light one live in
   `TMessagesProj/src/main/assets/*.attheme`, one `name=value` line per colour, values as
   negative decimal ints (`windowBackgroundWhiteBlackText=-1`).
2. Git stores them with LF. This checkout has `core.autocrlf=true` and no `.gitattributes`,
   so the working tree - and therefore the APK - gets CRLF.
3. `Theme.getThemeFileValues()` splits on `\n` and hands `"-1\r"` to
   `Utilities.parseInt()`. That function scans for digits and `-`, then does `end++` **before**
   breaking, so the terminating `\r` is included in the substring.
4. `Integer.parseInt("-1\r")` throws. The `catch (Exception ignore) {}` around it swallows
   the throw and `parseInt` returns **0**.
5. Every colour in the theme becomes 0. Transparent text on a background that is also 0.

Upstream used to guard this: `parseInt` had a `if (BuildConfig.BUILD_HOST_IS_WINDOWS)` branch
that pulled the number out with a regex. **12.10.0 deleted the branch and the flag**, so a
Windows checkout has nothing between `core.autocrlf` and the parser. Their own builds are
presumably not made on Windows.

### The fix

`.gitattributes` in the Android submodule, marking `*.attheme -text`. Theme assets are data,
not source; nothing may rewrite their line endings. Existing checkouts do not re-normalise on
their own - delete the files and `git checkout --` them once.

Do not "fix" this by patching `Utilities.parseInt`: it is upstream code on a hot path used far
beyond themes, and the corruption is in the data, not in the parser.

### What made it expensive to find

- **The failure is silent.** A swallowed `catch` turned a data bug into what looked like a
  logic bug. Nothing in logcat, no exception, no wrong-looking code.
- **Every file matched upstream.** `Theme.java`, `ThemeColors.java`, `Utilities.java`, the
  assets and the resources all diffed clean against `3f03bfc73f`, which is exactly what sends
  you looking at R8, the Gradle cache and submodule drift instead of at the checkout.
- **"483 of 823 colours loaded" reads like success.** The map was full; the values in it were
  zeros. Count is not content.

The way in was a temporary `FileLog.d` in `applyThemeInBackground` printing the resolved
value of three keys after `refreshThemeColors()`. `blackText=0` next to an asset that plainly
says `-1` named the culprit in one line. A `-Fast` debug build turns that loop around in
under three minutes once the native side is warm.

### Checking it

```bash
tr -dc '\r' < TMessagesProj/src/main/assets/night.attheme | wc -c   # must print 0
```

Worth running after any upstream merge, and on any fresh clone before the first release build.

## G1 addendum — the installer carries its own copy of the version

`package-desktop-inno.ps1` does not read the version from anywhere. It hands the build to
`desktop/novagram-desktop/packaging/novagram.iss`, which holds it in a literal:

```
#define MyAppVersion "7.1.1"
```

The first installer built after the base moved to v7.1.1 therefore came out named
`NovaGramSetup-7.0.9.3-x64.exe` around a `7.1.1.0` binary. Worse than the name: the update
check compares this number, so a stale one means installed clients never see the release.

A version bump has to reach **four** places, none of which is derived from another:

| File | What breaks if it is missed |
|---|---|
| `Telegram/SourceFiles/core/version.h` | the running binary reports the old version (G1 proper) |
| `Telegram/build/version` | build metadata and `AppVersionOriginal` |
| `Telegram/Resources/winrc/Telegram.rc` and `Updater.rc` | Explorer properties and the signed file version |
| `packaging/novagram.iss` | installer filename and the update check |

`Updater.rc` in particular is easy to leave behind - it sat at `7.0.9.2` through two
releases before the v7.1.1 merge caught it.
