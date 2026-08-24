# Android (Telegram Android / Gradle) code traps
Expands G21-G24, N2-N5, N12, I1, M2, M7, M23, M24. Read before editing activity lifecycle handling, chat cells,
the decoy responder or Gradle properties in `android/novagram-android`.

## G21 — `Activity.onUserInteraction` does not fire

Not for on-screen keyboard input (text goes through `InputConnection`), not for dialogs and
bottom sheets, not in the media viewer — those have their own windows. The idle counter is
fed separately from `BottomSheet`, `AlertDialog`, `PhotoViewer` and `ChatActivityEnterView`.

## G22 — locking the screen is not the same as going to background

Locking the phone with the app open does not raise a background event. A separate
`ACTION_SCREEN_OFF` receiver is required.

## G23 — a cell keeps its layout when handed back the same `MessageObject`

`forceUpdate` must be called **before** notifying the adapter, and un-collapsing needs
`resetLayout()`, otherwise an empty bubble is left behind.

## G24 — decoy responder objects are not serialized

`NovaDecoyServer` hands objects back without serialization while parts of the client read raw
flag bits. Setting `current = true` alone is not enough — `flags |= 1` is also required.

## Decoy network cutoff

A single predicate, `ConnectionsManager.offline()`
(`TMessagesProj/src/main/java/org/telegram/tgnet/ConnectionsManager.java:155`), closes about
thirty entry points into the native layer, including the constructor: `native_init` is not
called at all. Separately, push services, billing, keep-alive and the update check are not
started, and `ContactsController` does not create a system account so the invented people
never reach the phone book.

Boundary: the guarantee rests on those entry points being listed by hand. A new upstream call
added at the next sync and not covered by `offline()` breaks the rule. "No sockets" can only
be confirmed from outside, with `tcpdump` or `adb`.

## N2 — the Android message cache is not proof of "the user wrote here"

"No outgoing message of mine in `messages_v2`" happens on a fresh install, after "clear
database", when the conversation was held from another device, and when auto-delete is on.
The answer has to be three-valued, and "could not ask" must not become a rule.

## N3 — the basis date is not taken from the device clock

A clock running a day fast would declare every tomorrow-dated dialog old. Take the date of
the last message of the oldest dialog in the list.

## N4 — the first page of the chat list does not describe the remaining pages

A pinned dialog can be older than everything beneath it. The basis is taken only from a fully
loaded list, archive included.

## N5 — `Erase evidence` inside a forum topic would wipe the whole group

The sweep walks by peer, without a topic filter. The menu entry is therefore offered only in
the group itself, never inside a topic.

## N12 — Gradle speedups that must not be bundled with a feature change

`android.enableJetifier=false`, `nonTransitiveRClass=true` and the configuration cache would
each speed the build up, but each can silently break the build on legacy dependencies. Only
as a separate, isolated change.

## Storage layout

| What | Where |
|---|---|
| PIN state | `noBackupFilesDir/novagram/security/pin_state.bin`, AES-256-GCM under a Keystore key |
| PIN verifier | PBKDF2-HMAC-SHA256, 600 000 iterations, 32-byte salt, then a domain HMAC |
| Auto-delete queue | separate file, AES-GCM under its own Keystore key |
| Read-status rules | separate file, AES-GCM under its own Keystore key |
| App-level flags | `SharedPreferences` |
| Decoy marker | `noBackupFilesDir/novagram/security/decoy.marker` |
| Device binding secret | `noBackupFilesDir/novagram/device/binding.v1`, AES-GCM under its own Keystore key |
| Datacenter authorization keys | `filesDirFixed[/accountN]/tgnet.dat`, sealed with the binding secret (I14) |

Desktop equivalents are in `docs/internals.md`; the ownership-tagging rule that applies to
all of these is I1 in `kb/privacy-design.md`.

## The device key has to be installed before `native_init`

`tgnet.dat` is read by `Config::readConfig` inside `ConnectionsManager::init`, which is what
`native_init` calls. So `NovaDeviceLock.installNativeKey()` sits in the Java `init(...)`
immediately before `native_init`, after the `offline()` decoy return — not in
`ApplicationLoader`, which is not the only path that builds a `ConnectionsManager`.

Two consequences worth remembering:

- `NovaConfigSeal` keeps "can open" and "must seal writes" as two separate answers. A file
  sealed before the owner switched binding off still has to open, or the rewrite that puts it
  back in the clear could never run (N15).
- A sealed file that will not open answers **null**, never an empty buffer. An empty config is
  a legitimate first start; a sealed one that failed is an authorization this device does not
  have, and handing back "empty" would quietly re-register the client as a new device.

## Packaging facts

- Package name `com.brent.novagram`, label `NovaGram`.
- `ENABLE_GOOGLE_SERVICES=false` — released builds ship without Google Services and therefore
  without FCM. Notifications arrive over the client's own connection and can be delayed under
  Doze. To enable FCM later: create Firebase apps for `com.brent.novagram` and its suffix
  variants, drop matching `google-services.json` into the wrapper modules, then build with
  `-PENABLE_GOOGLE_SERVICES=true`.
- Release keystore `keys\brent-novagram-release.jks`; signer
  `CN=Brent NovaGram, OU=NovaGram, O=Brent, L=Local, ST=Local, C=RU`. `docs/build.md` notes
  the bootstrap keystore password is still the placeholder and says to rotate it before any
  public release — unverified whether that was ever done. Never read or copy anything from
  `keys/`.
- Built APK lands at
  `android/novagram-android/TMessagesProj_App/build/outputs/apk/afat/release/app.apk`.
- Instrumented tests exist under `TMessagesProj_AppTests/src/androidTest/.../novagram/`
  (`NovaPinKdfTest`, `NovaPinLockoutTest`, `NovaPinSessionTest`, `NovaPrivacyContractTest`,
  `NovaEncryptedBlobStoreInstrumentedTest`, `NovaCachePolicyTest`, `NovaScreenshotPolicyTest`).
  Whether they are run as part of any workflow is unverified.
