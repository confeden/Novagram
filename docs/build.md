# NovaGram build notes

Development plans live in [`roadmap.md`](roadmap.md).

## Layout

- `android/novagram-android`: Telegram Android upstream mirror with NovaGram package/signing config.
- `desktop/novagram-desktop`: Telegram Desktop `v7.0.1` beta mirror.
- `keys`: local signing material, ignored by Git.
- `dist`: installer outputs, ignored by Git.
- `.novagram.local.ps1`: local API/signing environment, ignored by Git.

## Android

Package name:

```properties
APP_PACKAGE=com.brent.novagram
```

Telegram API credentials are read from `android/novagram-android/local.properties`:

```properties
NOVA_TELEGRAM_API_ID=<your api_id>
NOVA_TELEGRAM_API_HASH=<your api_hash>
```

Build:

```powershell
D:\Documents\Coding\NovaGram\scripts\build-android.ps1
```

Default task:

```powershell
:TMessagesProj_App:assembleAfatRelease
```

The Android release keystore is:

```text
D:\Documents\Coding\NovaGram\keys\brent-novagram-release.jks
```

Current bootstrap password is `android`, matching the existing Gradle properties. Rotate this before any public release.

Google Services is disabled by default:

```properties
ENABLE_GOOGLE_SERVICES=false
```

To enable FCM later, create Firebase apps for `com.brent.novagram` and any suffix variants, place matching `google-services.json` files into the wrapper modules, then build with:

```powershell
.\gradlew.bat :TMessagesProj_App:assembleAfatRelease -PENABLE_GOOGLE_SERVICES=true
```

Verified APK:

```text
android/novagram-android/TMessagesProj_App/build/outputs/apk/afat/release/app.apk
package: com.brent.novagram
label: NovaGram
signer: CN=Brent NovaGram, OU=NovaGram, O=Brent, L=Local, ST=Local, C=RU
```

## Desktop

Base tag:

```text
telegramdesktop/tdesktop v7.0.1
```

Build:

```powershell
D:\Documents\Coding\NovaGram\scripts\build-desktop.ps1 -Config Release
```

Do not pass `-Qt6` for released builds. Upstream `Telegram/build/qt_version.py`
selects Qt 5.15.19 on win32 without the `qt6` flag, and that is what the
official client ships. Building with Qt 6.11.1 changes font rasterization
(DirectWrite instead of the GDI path, so text looks thinner than the official
client) and switches window painting to QRhi over D3D11, which makes dragging
the window visibly less smooth. See the roadmap section "Версия Qt".

First dependency bootstrap:

```powershell
D:\Documents\Coding\NovaGram\scripts\build-desktop.ps1 -Prepare -PrepareOnly
```

The Windows desktop build is pinned to:

```text
Visual Studio 2026 Build Tools, MSVC 14.44, Windows SDK 10.0.26100.0
Python 3.10.11
CMake 3.31.12
Ninja 1.13.1
NASM 3.01
YASM 1.3.0
Qt 5.15.19, built by Telegram's prepare script, same as the official client
```

CMake 4.4.0 is installed on this PC but is not used for Telegram Desktop, because it trips tdesktop's `-Werror=dev` policy checks.

The script passes:

```text
TDESKTOP_API_ID
TDESKTOP_API_HASH
TDESKTOP_DISABLE_AUTOUPDATE=ON
```

Current executable:

```text
desktop/novagram-desktop/out/NovaGram.exe
```

Package with Inno Setup:

```powershell
D:\Documents\Coding\NovaGram\scripts\package-desktop-inno.ps1
```

Create optional self-signed Authenticode PFX:

```powershell
D:\Documents\Coding\NovaGram\scripts\new-desktop-codesign-cert.ps1
```

Signing is mandatory: `package-desktop-inno.ps1` throws before it ever calls ISCC unless `NOVAGRAM_PFX` points at an existing file and `NOVAGRAM_PFX_PASSWORD` is non-empty. Without both, no installer is produced at all.

### Desktop build pitfalls

Always build through `scripts/build-desktop.ps1`. Calling `ninja -C out` directly
fails: the CMake cache stores `CMAKE_C_COMPILER=cl`, which only resolves inside
the `vcvars64.bat` environment the script sets up. A direct call makes CMake
re-run, fail to find `cl` and Ninja, and truncate `out/CMakeCache.txt`, after
which the next configure rebuilds the whole tree.

Switching the Qt version needs a clean `out/`. Generated `moc_*.cpp` files carry
the version of the moc that produced them, and mixing them fails as
`fatal error C1189: "This file was generated using the moc from 5.15.19."` or
the symmetric message for Qt 6. Find the stale ones with:

```bash
grep -rl "5\.15\.19" --include="moc_*.cpp" out
```

Clear `out/` by hand and keep `tdata`. Do **not** use `-ForceConfigure` for
this: `cmake/run_cmake.py` deletes everything in the build directory except
entries starting with `debug` or `release`, so it takes the working profile
`out/tdata` with the signed-in account along with the build artifacts.

Close the running `out/NovaGram.exe` before building. It holds `out/log.txt`
and the executable itself, so configure and the final link both fail while it
is running. The failure reads
`lld-link: error: failed to write output 'NovaGram.exe': permission denied`.

`vcvars64.bat` calls `vswhere.exe` by bare name. An interactive developer shell
usually already has `C:\Program Files (x86)\Microsoft Visual Studio\Installer`
on `PATH`; a shell started by tooling does not, and vcvars then fails with
`'vswhere.exe' is not recognized`. `scripts/build-desktop.ps1` adds that
directory itself, so the build works from any shell.

### Testing the decoy without touching the working profile

`out/NovaGram.exe` accepts `-workdir`, so the decoy can be run against a
throwaway profile while `out/tdata` with the signed-in account stays where it
is. A directory whose `tdata` contains a `novagram_decoy` file is enough; an
empty file works, the client generates the seed and the time anchor itself on
first start.

```bash
mkdir -p out/decoytest/tdata && touch out/decoytest/tdata/novagram_decoy
```

```powershell
out\NovaGram.exe -workdir out\decoytest
```

Do not swap `out/tdata` aside for this. `-workdir` leaves the working profile
untouched, which matters because a half-finished swap loses the signed-in
account.

### Local PIN state

The desktop PIN feature keeps its state in `tdata/novagram_pin` next to
`tdata/key_data`. Deleting that file removes the emergency PIN and the
persistent lockout counter, but not the primary PIN: the primary PIN is the
upstream local passcode and lives in `tdata/key_data`.

### Testing the emergency PIN

`out/NovaGram.exe` uses `out/tdata` as its working directory, separate from the
installed client in `%APPDATA%/NovaGram`. Entering the emergency PIN on a locked
cold start now erases everything in that `tdata` except `temp` and `tdummy`, so
back the directory up before testing:

```bash
cp -r desktop/novagram-desktop/out/tdata desktop/novagram-desktop/out/tdata.backup
```
