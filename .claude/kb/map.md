# Code map — where each subsystem lives
Expands M1-M31. Read before touching code in either submodule: this table replaces
exploratory search. A stale line number costs one grep; not having the row costs a
full-file read. Paths are relative to the repo root unless a row says otherwise.

| ID | To touch... | Go to |
|---|---|---|
| M1 | any desktop fork code | `desktop/novagram-desktop/Telegram/SourceFiles/novagram/` |
| M2 | any Android fork code | `android/novagram-android/TMessagesProj/src/main/java/org/telegram/messenger/novagram/` |
| M3 | the release tag (desktop half) | `.../novagram/nova_branding.cpp:17` (`kReleaseTag`) |
| M4 | the release tag (Android half) | `.../novagram/update/NovaUpdateChecker.java:59` (`RELEASE_TAG`) |
| M5 | desktop version (three files) | `core/version.h:25-26`, `Telegram/build/version`, the `.rc` — see G1 |
| M6 | decoy network barrier, desktop | `mtproto/mtp_instance.cpp:1058` (`Instance::Private::sendRequest`, declared `:1050`) — see below |
| M7 | decoy network barrier, Android | `android/.../org/telegram/tgnet/ConnectionsManager.java:155` (`offline()`) |
| M8 | decoy content / fake persona | `nova_decoy{,_persona,_server}.cpp` / `privacy/NovaDecoyServer.java`, `NovaDecoyPersona.java` |
| M9 | DoH resolver, desktop | `nova_doh.cpp:546` (`Resolver::resolve`), public entry `:893` |
| M10 | DoH pinned CA roots, desktop | `nova_doh_roots.h` (10 roots; also kills the Windows root store) |
| M11 | DoH resolver, Android | `net/NovaDoh.java:401` (`resolve`) |
| M12 | which CAs may serve DoH, Android | `TMessagesProj/src/main/res/xml/novagram_network_security_config.xml` |
| M13 | read-status gate, desktop | `nova_read_status.cpp:708` (`ReadStatusHiddenFor`) |
| M14 | read-status gate, Android | `privacy/NovaReadStatus.java:302` (`isHidden`), reactions `:427` |
| M15 | auto-delete, desktop | `nova_autodelete.cpp:920` (`DueIn`), runner `:359` |
| M16 | auto-delete, Android | `privacy/NovaAutoDelete.java:107`, store `NovaAutoDeleteStore.java` |
| M17 | PIN logic, desktop | `nova_pin.cpp`, UI `nova_pin_box.cpp`, policy `nova_pin_policy.cpp` |
| M18 | PIN logic, Android | `privacy/NovaPinVault.java`, gate `org/telegram/ui/NovaPinGateActivity.java` |
| M19 | update checker, desktop | `nova_update.cpp:173` (`Checker::start`), proxy choice `:190`, releases URL `:46-47`, verdict log `:411` |
| M20 | update checker, Android | `update/NovaUpdateChecker.java`, bar `NovaUpdateLayout.java` |
| M21 | settings UI | `nova_settings.cpp` / `org/telegram/ui/NovaGramSettingsActivity.java`, DoH page `NovaDohActivity.java` |
| M22 | notification privacy | `nova_notify_previews.cpp` / `privacy/NovaNotificationPrivacy.java`, `NovaNotificationContent.java` |
| M23 | native ABI / minSdk | `android/novagram-android/TMessagesProj/build.gradle:112-139` |
| M24 | R8 keep rules | `android/novagram-android/TMessagesProj/proguard-rules.pro:117-122` |
| M25 | build entry points | `scripts/build-desktop.ps1`, `scripts/build-android.ps1` |
| M26 | the mandatory upstream gate | `scripts/check-upstream.ps1` (state in `.analysis/upstream-check.json`) |
| M27 | installer + signing | `scripts/package-desktop-inno.ps1`, `desktop/novagram-desktop/packaging/novagram.iss` |
| M28 | update manifest format/workflow | `packaging/updates/` (the shipped JSONs here are placeholders) |
| M29 | Android + decoy strings | `TMessagesProj/src/main/res/values{,-ru}/novagram_{strings,decoy}.xml` |
| M30 | device binding, desktop | `novagram/nova_device_lock.cpp`; hooks are `storage/storage_domain.cpp` — `Unwrap` in `startModern`, `Wrap` in `writeAccounts`, `StartResult::WrongDevice` in `start`; blocked screen is the `_novaDeviceBlocked` branch of `window/window_lock_widgets.cpp` |
| M31 | device binding, Android | `privacy/NovaDeviceLock.java` + `NovaDeviceKeyStore.java`; the seal itself is native — `jni/tgnet/NovaConfigSeal.cpp`, called from `Config::readConfig`/`writeConfig`; key handed over by `ConnectionsManager.init` just before `native_init`; blocked screen is `Mode.DEVICE_CHANGED` in `ui/NovaPinGateActivity.java` |

`mtproto/*` and `history/*` paths are inside
`desktop/novagram-desktop/Telegram/SourceFiles/`; `privacy/*`, `net/*` and `update/*` are
inside the M2 directory.

## M6 — there is more than one decoy barrier in `mtp_instance.cpp`

`NovaGram::Decoy::Active()` appears nine times in that file, so a bare "the decoy check in
`mtp_instance.cpp`" is ambiguous. The two that matter:

- **`:1058`, inside `Instance::Private::sendRequest`** (declared `:1050`) — the request
  barrier described in `kb/desktop-code.md#decoy-network-barrier-placement`. It runs
  *before* `const auto session = getSession(shiftedDcId);` at `:1066` and diverts the
  request to `answerOffline(...)`, because asking for a session would already build the
  transport and start connecting.
- **`:382`, first statement of `Instance::Private::start()`** — a *different* barrier: it
  returns before any session or config loader is created, so the decoy never opens a
  datacenter socket and never falls back to public DNS-over-HTTPS resolvers.

The rest (`:406`, `:532`, `:571`, `:650`, `:673`, `:692`, `:2192`) are the same single-entry
pattern applied to config loading, proxy-domain resolution and time sync (I4). Do not attach
the sendRequest/`getSession` description to `:382` — that pairing was wrong in the knowledge
base once already.
