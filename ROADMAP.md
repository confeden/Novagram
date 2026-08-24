# NovaGram — project state

Privacy fork of Telegram for Windows + Android (two submodules), shipped as one release
carrying both upstream bases. `v7.1.1/12.10.0` is drafted; `v7.0.9.3/12.9.2.3` is the
published one.

## Status

| ID | Component | State | Evidence |
|---|---|---|---|
| S1 | Release `v7.1.1/12.10.0` | draft | tag pushed, both artifacts attached, notes written; not published. `v7.0.9.3/12.9.2.3` is still Latest |
| S2 | Desktop base `tdesktop v7.1.1` | ok | merged, builds, `NovaGram.exe` reports `7.1.1.0`; branch name `novagram/v7.0.7` is historic |
| S3 | Android base `Telegram Android 12.10.0 (7031)` | ok | merged, builds through R8; APK reports `12.10.0`, code `70319` |
| S4 | Emergency PIN → wipe → decoy | ok | run on both platforms |
| S5 | Strict DoH, 4 pinned endpoints | ok | run on a live network, both platforms |
| S6 | PIN encrypts local data | ok desktop / limited Android | Android PIN is a login gate only; the Telegram DB is not encrypted |
| S7 | Read-status hiding | ok desktop / unverified Android | Android gate never tested with a second account — the main scenario |
| S8 | Auto-delete own messages | ok desktop / unverified Android | Android delete cycle never run |
| S9 | Screenshot + recording block | ok desktop / wip Android | Android has storage+contracts only, feature inactive |
| S10 | Calls, relay-only | ok desktop / unverified Android | desktop: `allowP2P: FALSE`, audio both ways |
| S11 | Update system | ok desktop / unverified Android | desktop reads GitHub releases; Android still needs the manual manifest workflow |
| S12 | Notification privacy | unverified | neither half tested; server half needs a 2nd device, desktop has no push |
| S13 | Filename masking + JPEG/PNG scrub | unverified | builds only; other formats out of scope |
| S14 | Emergency PIN in a live unlocked desktop session | broken | wipe works on cold start only — cache DBs open, Windows refuses deletion |
| S15 | Hardware binding of PIN state | ok Android / planned desktop | Keystore/StrongBox; desktop DPAPI/TPM not started |
| S16 | Upstream comparison branches | ok | `git diff --name-only <base>...HEAD` gives 117 desktop / 128 Android, the numbers README prints; zero upstream commits behind |
| S17 | Reproducible build | broken | none exists; Releases binaries cannot be tied to the source |
| S18 | Root build logs | ok | `android-merge-build.log` and `desktop-merge-build.log` are the v7.1.1/12.10.0 builds |
| S19 | Device binding of local data | ok both | stolen-folder hole closed (I14, M30-M31, N16). Both theft paths run by hand; what was run and what is still unseen: `kb/feature-status.md` |

## Map

M1-M31 live in `.claude/kb/map.md` — the full `file:line` index for both submodules; load it
before touching code, it replaces exploratory search. One ambiguity worth knowing up front:
`mtp_instance.cpp` holds **nine** `Decoy::Active()` checks, and the request barrier (M6) is
`:1058` in `Private::sendRequest`, not the `:382` one in `Private::start`.

## Invariants

| ID | Rule | Why |
|---|---|---|
| I1 | Metadata lists live in AES/GCM sealed containers tagged with the owning account, never `SharedPreferences` | account slots are reused; an untagged blob would pass to the next account |
| I2 | Read-status hiding is decided once per dialog — did it exist before its first incoming message; the gate answers "hidden" while undecided | an unsent receipt can be sent later, a sent one cannot be recalled |
| I3 | `show_previews=false` (account) and local content hiding (screen) stay two separate mechanisms | they fail independently and are promised separately |
| I4 | The decoy check sits at the module's single entry point; no fork feature writes its own rules inside the decoy or names NovaGram | one bypassed caller gives the decoy away |
| I5 | DoH covers only names the client resolves itself, via four hardcoded endpoints | WebView, browser, Play Services, WebRTC and the OS resolver are outside the client |
| I6 | Relay-only is enforced locally at instance construction; domain names in call addresses are discarded, not resolved | resolving over DoH hides the name but still leaks the fact |
| I7 | Never send API fields whose values the client does not know | `updateServerNotificationsSettings` forces `flags \|= 8` and a default sound; an empty settings area serializes as `resetToDefault` |
| I8 | Anything that hides must expose a visible way to switch it off | otherwise it is irreversible in practice |
| I9 | `check-upstream.ps1` runs first in every build and stops it when upstream is newer; integration is manual | scripts must never merge or rebase a dirty privacy fork (`UPSTREAM_POLICY.md`) |
| I10 | A **release** Android build is mandatory before shipping | only R8 catches a class reachable solely from an upstream hook (G3) |
| I11 | Desktop release links with the pinned LLVM/LLD, never MSVC `link.exe` | link.exe peak memory is unsuitable for this workstation |
| I12 | `ok` only after running on a real account/device, never after a build | vocabulary in kb/feature-status.md |
| I13 | A feature ships on both platforms; done on one, the other is `planned` and enters Next | the group promises are made for both |
| I14 | What a stolen copy must open is sealed to the **machine**, not to a passcode: desktop wraps the local key in `tdata/key_data`, Android seals `tgnet.dat` | upstream defaults to an *empty* passcode and writes `tgnet.dat` in the clear, so a copied folder signs in anywhere. `kb/privacy-design.md#i14` |

## Gotchas

- **G1** Desktop build calls itself the old version → version compiles from generated-but-committed `core/version.h`, and `set_version.py` mangles the 4th digit into an alpha → edit `version.h`, `build/version`, both `.rc` files and `packaging/novagram.iss` by hand, plus Android `NovaUpdateChecker.RELEASE_TAG` — five places. `kb/build.md#g1`
- **G2** `SIGSEGV, pc=0` on `Thread-19` shortly after start, arm64 below Android 12 → `ANDROID_PLATFORM` above `minSdkVersion` makes clang emit `R_AARCH64_TLSDESC` → keep them equal; `llvm-readelf -r libtmessages.*.so \| grep TLSDESC` must be empty. `kb/build.md#g2`
- **G3** `minifyAfatReleaseWithR8` fails "Missing class" → R8 strips a class reachable only via an upstream hook (`NovaUpdateLayout`) → `-keep` in `proguard-rules.pro`. Debug never catches it. `kb/build.md#g3`
- **G4** `LNK1104` / `failed to write output 'NovaGram.exe': permission denied` → a client started from `out/` is still running (installed copy is harmless) → close `out/*.lnk`. `kb/build.md#g4`
- **G5** A build that died on a link error reported success → `exit /b` in the generated `.cmd`, top level of `cmd /c`, so the code never reached PowerShell → plain `exit`. `kb/build.md#g5`
- **G6** Link takes ~15 min, no lld in `build.ninja` → `CMAKE_LINKER` alone does nothing → `CMAKE_LINKER_TYPE=LLD` (CMake 3.29+); tell them apart by `lld-link:` vs `LINK :`. `kb/build.md#g6`
- **G7** `out/NovaGram.exe` is ~2 MB and will not start → link interrupted, usually memory (it holds 16-18 GB) → rebuild, run nothing heavy alongside. `kb/build.md#g7`
- **G8** `ninja -C out`, `-ForceConfigure` and Qt switches each break the tree, and `run_cmake.py` deletes `out/tdata` with the signed-in account → use `build-desktop.ps1`. `kb/build.md#g8`
- **G9** Fork requests ignore the system proxy → `refreshGlobalProxy()` sets `NoProxy` process-wide → the checker picks its own. `kb/privacy-design.md`
- **G10** `UserConfig.getCurrentUser()` is `null` at the Android cold-start gate → the gate precedes config load → deserialize the saved account block from `userconfing`. `kb/privacy-design.md`
- **G11** Update check silently fails on some networks → it goes to GitHub, blocked there; an MTProto proxy cannot help, it speaks only Telegram → needs SOCKS5/HTTP. `kb/privacy-design.md`
- **G12** Decoy switched on over a *running* session still has live sockets → existing connections close only on logout, which needs the network → absent on cold start. `kb/privacy-design.md#i4`
- **G13-G17** Desktop message drawing: a custom branch never runs (`countGeometry()` returns early); an overlay hides under the avatar; the avatar loses its context menu to a full-width link; clicks are lost (handlers compared by pointer); `setOpacity` around `Message::draw` does nothing. Cause and fix for each: `kb/desktop-code.md`
- **G18** Data written through `EncryptedDescriptor` vanishes → without an explicit size it never opens the buffer and encrypts an empty block. `kb/desktop-code.md#g18`
- **G19** Progress shows 74 % but the log says `download failed at 0 bytes` → `setTransferTimeout` makes Qt `abort()`, and closing the `QIODevice` discards the buffer → read on `readyRead`. `kb/desktop-code.md#g19`
- **G20** Two empty 640x480 windows after start → upstream `Ui::GL::CheckCapabilities` leaves the native window alive → `nova_screen_guard.cpp` moves them off-screen; do not destroy (N7). `kb/desktop-code.md#g20`
- **G21** The idle timer never fires on Android → `onUserInteraction` misses IME input, dialogs, sheets and the media viewer → feed it from all four. `kb/android-code.md#g21`
- **G22** Locking the phone does not trigger the lock policy → locking is not backgrounding → add an `ACTION_SCREEN_OFF` receiver. `kb/android-code.md#g22`
- **G23** A chat cell keeps its old layout / shows an empty bubble → it was handed back the same `MessageObject` → `forceUpdate` before notifying the adapter, `resetLayout()` when un-collapsing. `kb/android-code.md#g23`
- **G24** Decoy data reads back wrong on Android → the responder returns objects without serialization while callers read raw flag bits → set `flags |= 1` as well as `current = true`. `kb/android-code.md#g24`
- **G25** `git submodule` commands misbehave → cause and rule live in CLAUDE.md, loaded every session. Extra detail only: `submodule status` reports both uninitialized (`-`) while both trees are populated, and the branches `.gitmodules` names are not the ones checked out.
- **G26** About to translate a repo doc into Russian because of D11 → D11 is a house rule, not
  a survey of the tree: the five files listed under the KB index are English → check the file
  first and keep it in the language it is already in. Bites P9, which edits `docs/build.md`.
- **G27** A desktop file that needs both OpenSSL and Win32 does not compile → `windows.h`
  pulls in `wincrypt.h`, which turns `X509_NAME` and friends into macros, while OpenSSL
  declares types by those names → include the OpenSSL headers **first**; after that the
  macros only shadow names the file never uses. Only `nova_device_lock.cpp` needs both.
- **G29** Every dark theme on Android draws black on black — text simply gone, day theme fine
  → `core.autocrlf=true` hands the `.attheme` assets to the parser with CRLF, and 12.10.0
  dropped the `BUILD_HOST_IS_WINDOWS` branch of `Utilities.parseInt` that used to tolerate it;
  `Integer.parseInt("-1\r")` throws into a swallowed `catch`, so every colour becomes 0 → the
  fork's `.gitattributes` marks `*.attheme -text`. `kb/build.md#g29`
- **G28** The first build after an upstream merge fails on something the merge never touched
  — desktop `error 805: struct 'CallButton' already defined`, Android `Project with path
  ':jlatexmath' could not be found` → a merge moves submodule pins and adds project
  references, but checks nothing out and declares nothing → sync every gitlink to what `HEAD`
  records before blaming a conflict resolution. `kb/build.md#g28`

## Negative knowledge

- **N1** `read_outbox_max_id` to answer "did the user write here" → it survives deleting the conversation and returns with a new one; it only says "these two have talked at some point".
- **N2** The Android message cache as proof of the same → "no outgoing in `messages_v2`" also happens on a fresh install, after "clear database", when the chat was held from another device, and with auto-delete on. The answer must be three-valued.
- **N3** Auto-delete basis date from the device clock → a clock a day fast declares every tomorrow-dated dialog old. Use the last message of the oldest dialog.
- **N4** Basis from the first page of the chat list → a pinned dialog can be older than everything below it. Use a fully loaded list, archive included.
- **N5** `Erase evidence` inside a forum topic → the sweep walks by peer with no topic filter and would wipe the whole group. Group menu only.
- **N6** A 90 s download timeout → it only makes a dead transfer look alive. Correct: 20 s plus auto-continuation of any attempt that advanced ≥1 byte, up to forty chunks.
- **N7** Destroying stray windows by "class is `QWidget`" → also matches Telegram's own service windows (tray refresher, notification sample, crash reporter, power/media-key helpers). "Qt considers it hidden" without a class check matches the main window in the tray.
- **N8** Treating the two empty windows as a paint artifact → they are real windows left behind after another window was dragged over the rectangle.
- **N9** Blaming the fork's event filter for creating them → the `QEvent::WinIdChange` fix was kept on principle, but the windows stayed.
- **N10** Releasing on Qt 6 → 6.11.1 moves rasterization to DirectWrite (text visibly thinner) and painting to QRhi/D3D11 (dragging less smooth). Upstream ships 5.15.19 on win32.
- **N11** `sccache`/`ccache` with MSVC → not in the toolchain, fights the precompiled header, needs a CMake reconfigure.
- **N12** Bundling `android.enableJetifier=false`, `nonTransitiveRClass=true` or the configuration cache into a feature change → each can silently break the build on legacy deps. Separate change only.
- **N13** Telegram's own auto-delete as a backstop → it clears the whole chat history, while the promise covers outgoing messages only.
- **N14** Putting the computer name into the desktop machine fingerprint → people rename their PC and would lock themselves out. Only `MachineGuid` and the system volume serial are used: both change exactly when the installation really is a different one.
- **N15** Dropping the device key the moment binding is switched off → the rewrite is queued on the network thread on Android, so a key deleted first leaves a sealed file nothing can open. The key stays, only sealing of new writes stops; desktop mirrors it by writing the accounts file unbound **before** removing `tdata/novagram_device`.
- **N16** Reading S19 as "a stolen Android directory is now useless" → only `tgnet.dat` is sealed; `cache4.db` stays upstream plaintext and still opens in any SQLite tool. Desktop has no such gap.

## Decisions

- **D1** Startup flicker of the empty windows stays as-is — fixing it means patching the `lib_ui` submodule and eating a conflict on every upstream merge.
- **D2** Android ships local notification-content hiding **on by default** — sender, chat and avatar visible, text hidden.
- **D3** Default PIN prompt moment on both platforms is **on screen lock**.
- **D4** Toggle subtitles are one or two sentences: what it does plus the single most important honest limit; a limit buried in a fourth paragraph has not been communicated. Measure: 130-310 chars on desktop, median ~217; most Android twins are the same string word for word.
- **D5** A collapsed row for a muted member reads "Скрытое сообщение", not the name, with a red cross over the avatar.
- **D6** No rules for specific addresses in fork code — circumventing blocks is the job of the system proxy or Telegram's proxy settings.
- **D7** No mirror for the update manifest — it must point into the same project.
- **D8** Removing Telegram ads is rejected on both platforms — impossible without breaching the Telegram TOS.
- **D9** DNS promise reworded: system, network, `hosts` and Private DNS can neither influence the resolver nor be a fallback, but the **device owner** may edit the list — weakened deliberately in this one place, the promise was made against someone else's substitution. Default unchanged. `kb/privacy-design.md#i5`
- **D10** README is a showcase, not a reference: internals → `docs/internals.md`, upstream behaviour → `docs/upstream-baseline.md`, feature breakdown → `docs/features.md`. The two fork repos' descriptions point at the main repo because forks do not appear in GitHub search.
- **D11** Project docs are Russian; API/class/proper names stay English. This knowledge base is the exception — English, for agents only.
- **D12** No dated journal here: a solved problem compresses to symptom → cause → fix → lesson, and the investigation is deleted.
- **D13** A copy this machine cannot unseal is never wiped automatically — the client blocks and offers one "start over" button. DPAPI and Keystore losses on the owner's own machine are permanent, not transient, so a silent `startFromScratch()` would destroy data the rightful machine still opens.
- **D14** Device binding is on by default and can be switched off in settings. Off means portable: a carried `tdata` keeps working, which is the only reason anyone would want it.

## Now

`v7.1.1/12.10.0` sits as a GitHub **draft** with both artifacts attached; everything is
pushed. The themed sweep came back with no invisible text anywhere, and two things it did
find are fixed and rebuilt: a stale `RELEASE_TAG` and six toggle titles that ellipsized
mid-word (G1, G30). Publishing is the owner's call. Residue in `kb/feature-status.md`: the D14
toggle and four cosmetic defects, three of them upstream.

## Next

| ID | Task | Why / blocked on |
|---|---|---|
| P1 | Run the unverified list by hand, top-down | S7, S8, S12, S13 — ranked list in `kb/feature-status.md` |
| P3 | Emergency PIN inside an unlocked desktop session | S14, the last broken component |
| P4 | Hardware binding of desktop PIN state (DPAPI/TPM) | S15 — so the lockout counter survives deleting `tdata/novagram_pin` |
| P5 | Jump to a peer by numeric ID from message text | UI half done; a bare ID needs `access_hash`, so it must distinguish "no such peer" from "no access key". `docs/peer-id.md` |
| P6 | Call key verification ceremony (emoji) | planned both platforms. `docs/calls.md` |
| P7 | Move Android update checks off the manifest onto GitHub releases | desktop already does; drops the manual `gh workflow run` step |
| P8 | Transport over Cloudflare WSS | v7.1.1 ships `mtproto/web_proxy/*`; re-scope first |
| P9 | Refresh `docs/build.md` | still names base tag `v7.0.1` and links a non-existent `roadmap.md`; it is an **English** file — see G26 |

## KB index

| File | Holds | Read it when |
|---|---|---|
| `.claude/kb/build.md` | toolchain pins, release procedure, timings, G1-G8 in full | building, packaging, bumping a version, shipping |
| `.claude/kb/feature-status.md` | full per-platform matrix, public promises, verified vs not | asked "is X done", or planning verification |
| `.claude/kb/privacy-design.md` | rationales for I1-I8 and I14, read-status derivation, DoH scope, residual holes | changing read-status, decoy, notifications, storage, device binding, DoH, calls |
| `.claude/kb/desktop-code.md` | tdesktop/Qt rendering, network and window traps; branding; decoy barrier | editing under `desktop/novagram-desktop` |
| `.claude/kb/android-code.md` | Android lifecycle/cell traps, decoy cutoff, storage, packaging | editing under `android/novagram-android` |
| `.claude/kb/map.md` | M1-M31: `file:line` for every subsystem, both submodules | before touching any code |
| `.claude/kb/_legacy-roadmap.md` | verbatim pre-restructure `docs/ROADMAP.md` (Russian), may be stale | a fact seems missing; grep only |

Not duplicated here (user-facing repo docs): `README.md`, `UPSTREAM_POLICY.md`,
`packaging/updates/README.md`, `docs/*.md`. All Russian except these five, English on
purpose (G26): `UPSTREAM_POLICY.md` and `docs/` `build` · `privacy` · `privacy-push` ·
`upstream-sync`.
