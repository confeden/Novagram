# Feature status — full per-platform matrix
Expands S1-S19, I12, I13, P1, and the user-visible side of D8, D9 and N13. Source of truth
for "is this feature done, and on which platform".

State words used below map to the ROADMAP vocabulary:
`verified` = run on a real account/device (ROADMAP `ok`) · `built` = compiles, never run
(ROADMAP `unverified`) · `foundation` = storage/contracts exist, feature inactive
(`unverified`) · `limited` = platform or Telegram API prevents the full intent ·
`planned` = requirements exist, no code · `rejected` = decided against, see D-ids.

A planned feature is never shown to the user as working until it reaches `built`.

## Matrix

| Feature | Desktop | Android |
|---|---|---|
| Branding, autoupdate + crash reports off | verified | built |
| Optional telemetry off | built | built |
| Separate NovaGram settings section | built | verified |
| Primary PIN as local encryption key | verified | limited: login gate only, Telegram DB not encrypted |
| Stolen data folder cannot sign in (device binding, S19) | verified; blocked screen not seen | verified |
| PIN verifier under a Keystore key | — | verified (StrongBox) |
| Disable primary PIN from settings | verified (stock path) | built |
| PIN prompt moment, 5 options | built; minimize-to-tray option verified | built |
| Emergency PIN | verified | verified |
| Physical data wipe by emergency PIN | verified (cold start only) | verified |
| Decoy mode after emergency PIN, enabled in place | verified | verified (process restart) |
| Total network cutoff in decoy | verified: zero sockets | verified |
| Real name + phone number inside decoy, always current | verified | verified |
| Decoy never names NovaGram; fills privacy + "Devices" | built | verified |
| Decoy profile bios, group members, call rejection | built | built |
| PIN brute-force lockout surviving restart | built | verified |
| Biometric bypass of emergency PIN blocked | built | verified |
| Shuffled PIN keypad; Russian UI before unlock | built | verified (keypad) |
| Offer to set a PIN after login | verified | verified |
| Screenshot / screen-recording block | verified | foundation |
| Auto-delete own messages | verified | built; delete cycle never run |
| Countdown to deletion in the message menu | built | verified |
| Report of what `Erase evidence` destroyed | built | built |
| Per-chat auto-delete override, incl. forum groups | verified | built |
| Chats where the user is admin are excluded | built | built |
| `Erase evidence` in the chat menu | built | built |
| Read-status hiding | verified | built; gate never tested with a second account |
| Rule armed in any new dialog started by the other side | built | built |
| "Read status hidden" banner above the chat | built | built |
| All receipt send points intercepted | built | built |
| Own reaction to their message lifts the hiding | built | built |
| `show_previews=false` to the server | built, default on | built, default on |
| Local hiding of notification content | rejected: no own push | built, default on |
| Night silent mode 22:00-07:00 | built; sending at night never tested | verified |
| One release for both platforms, tag `v<PC base>/<Android base>` | built | built |
| Version number opens the release; app name opens the GitHub project | built | built |
| Update check at most once per 8 h | verified | built |
| Visible update button with progress and cancel | verified | built |
| Download + install update with restart | verified | limited: system APK installer |
| Update check via GitHub releases, no manifest | verified | planned: manifest for now |
| Anonymized names for files saved without asking | built | built |
| Metadata stripped from outgoing JPEG and PNG | built | built |
| Quick access to proxy settings | verified | verified |
| Mute a member in a chat (groups only) | built | verified; notification suppression built |
| Marquee text when hovering a settings row | built | limited: no cursor |
| Hardware-backed cache encryption | limited: passcode already encrypts everything | foundation |
| Hardware binding of PIN state | planned (DPAPI/TPM) | verified (Keystore) |
| Strict DoH | verified, roots pinned in-binary | verified, system roots |
| Editable DoH server list | built | verified |
| `dcDomainName` pinned to a constant | built | built |
| Transport over Cloudflare WSS | planned | planned |
| Telegram ads removal | rejected: impossible without breaching TOS | rejected: same |
| Secret Chat priority | limited: absent from Telegram Desktop | planned |
| Calls enabled | verified: audio both ways | built: `PROTECTED_CALLS` no longer kills them |
| Relay-only calls, IP not visible to the peer | verified: `allowP2P: FALSE`, call holds | built |
| Domain names in call addresses discarded | built | built |
| Call key verification ceremony (emoji) | planned | planned |
| `ID` row in the profile — user, group, channel, bot | built | built |
| Jump to a peer by numeric ID from text | planned | planned |

## Public promises made in the Telegram group

Binding on both platforms.

| Promise | Desktop | Android |
|---|---|---|
| One branch, always on the latest official beta | built | built |
| Emergency PIN wipes data of **all** accounts | verified | verified |
| Timer deleting own messages, counted from send | verified | built |
| Auto-delete off for chats where the user is admin | built | built |
| Manual `Erase evidence` in the chat menu | built | built |
| Randomized local file names | built | built |
| Full metadata scrub on send | limited: JPEG and PNG only | limited: JPEG and PNG only |
| DNS only from the NovaGram list, no system/network override | verified | verified |
| Backstop via Telegram's own auto-delete | rejected | rejected |

One promise must NOT be called fulfilled in a release description: the metadata scrub is
not "full" — HEIC/HEIF, TIFF/RAW, PDF, Office documents and audio tags go out untouched,
and so does video on desktop (on Android ordinary sending re-encodes it and loses the
metadata by itself).

## Verified by actually running it

**Desktop:** primary and emergency PIN; data wipe and decoy on both cold start and a live
process; snapshot of the wiped account's name and number; network cutoff in decoy (zero
sockets); screenshot block; auto-delete; read-status hiding (gate log, outgoing dump, the
peer's side); auto-delete entries in a forum group; the whole update chain, now including
over DoH with a byte-for-byte installer comparison; a call in both directions under
relay-only.

**Android:** primary and emergency PIN; data wipe (132 files -> 38, authorization record
destroyed); the decoy in full; the encrypted auto-delete queue (write-read round trip);
`Erase evidence` in a real group; the countdown in the message menu; night silent
(`silent: YES` in the receiving side's dump); the "Proxy" entry by both paths; muting a
member.

## NOT verified by running, most important first

DoH end-to-end on either platform is now verified (see ROADMAP S5); the rest of this list
still stands:

1. Read-status hiding on Android with a second account — the feature's main scenario.
2. Full auto-delete cycle on Android (set 1 day, come back after 24 h, confirm the message
   became a dot and then vanished on both sides).
3. Both halves of the notification promise — neither tested; the server half needs a second
   device, and desktop has no push of its own at all.
4. Hiding lifted by one's own reaction.
5. The `ID` row in the profile.
6. File-name masking and metadata scrubbing.
7. Night silent on desktop.
8. Four of the five PIN-prompt moments.
9. Muting a member on desktop.
10. The `Erase evidence` report.
11. The lockout countdown after three wrong PINs.
12. The desktop blocked screen and its "start over" button (S19) — the foreign copy was
    opened with the old build, so the screen itself never rendered.
13. The D14 device-binding toggle, on either platform.

## Verification tooling

Desktop verification **can** be automated, contrary to an earlier belief: the window is
captured with `CopyFromScreen` over its rectangle and buttons are pressed with
`SetCursorPos` + `mouse_event`. Only screens that are explicitly screenshot-protected come
out masked.

For read-status specifically, see `docs/verify-read-status.md` — "did a second tick
appear" is **not** a test, the tick is drawn by the client from its own data.

## S19 — what the device-binding run actually covered

Both platforms were exercised by hand against a real signed-in account. What was observed,
so that the next session does not re-run it or over-claim it:

**Desktop.** A profile written by the previous build (`out/brent`, no `novagram_device`, no
`NVD1` in `key_datas`) migrated on the first start of the new binary: the binding file
appeared, `key_datas` gained the wrapper, and the account kept working. A copy of that
`tdata` taken to another machine opened with nothing — tried there with the *old* NovaGram,
which stops at the passcode screen because `DecryptLocal` no longer matches. That is the
stronger result: refusal comes from the bytes, not from this client's cooperation.

**Android.** `com.brent.novagram` 12.9.2.3 on the Mi A1 held a plaintext `tgnet.dat` with
`ru-ru` readable at offset 8. Installing the release build over it sealed the file — `NVC1`
at offset 4, then nonce and ciphertext, no plaintext left — and the session survived the
upgrade untouched. The whole data directory (`files`, `shared_prefs`, `databases`,
`no_backup`) was then copied into a second install (`.beta`, its own uid and its own
Keystore, i.e. a foreign device as far as the key is concerned): the client came up on
`NovaPinGateActivity` with "Данные принадлежат другому устройству", not signed in.
"Начать заново" wiped local data and left an ordinary first run.

**Still unseen.** The desktop blocked screen and its reset button — the foreign copy was
opened with the old build, so the new screen never rendered. The D14 toggle was never
switched on either platform.

**Re-checked after the v7.1.1 / 12.10.0 merge.** Both merged builds were launched and the
binding still holds: desktop logs `NovaGram device lock: bound, mechanism: Windows DPAPI +
отпечаток компьютера` and opens the bound profile, Android keeps its session with `NVC1`
still at offset 4 of `tgnet.dat`. The merge touched `window_lock_widgets.cpp`, so the desktop
half of this is not the same binary that was first verified — the storage path is, though.

**Testing notes.** The Android blocked screen is `FLAG_SECURE`, so `screencap` returns zero
bytes; read it with `uiautomator dump` instead. The theft test needs no second device: a
second install with its own Keystore identity is exactly what the seal cannot follow. Do not
use the Pixel 4a for it — no root, so nothing can be written into `/data/data`.

## D4 in numbers, and where Android stood

The desktop settings screen is the reference: 15 subtitles, 130-310 characters, median ~217,
formula "mechanics in the present tense, then the one honest limit". Most Android subtitles
are already the *same string word for word* - `NovaAutoDeleteInfo`, `NovaMetadataInfo`,
`NovaCallsRelayInfo`, `NovaNightSilentInfo` all match their desktop twin exactly, and the
rest sit inside the range. Two did not, and only two:

| String | Was | Now (ru / en) |
|---|---|---|
| `NovaPushPreviewInfo` | 1566 | 307 / 321 |
| `NovaHideContentInfo` | 1419 | 243 / 289 |

Two traps found while shortening them, both worth remembering:

- **Do not write "the avatar is not hidden".** On Android hiding the content also removes the
  sender's small avatar - `preview[0]` carries the text and the avatar load together (I3).
  A subtitle promising the avatar stays would promise more than the feature does.
- **"without network the text may not arrive" is a tautology** - without network the push
  does not arrive either. The real failure is Doze and battery saving: the push is delivered
  while the client's own connection sleeps, so the text never loads.

Everything else long in `novagram_strings.xml` is a dialog body, a warning before an
irreversible action, or the body of a standalone screen. D4 does not apply to those and
shortening them is harmful - `NovaDeviceChangedDescription`, `NovaEmergencyCreateDescription`,
`NovaPinCreateDescription`, `NovaEraseEvidenceAbout` and the rest stay as they are.

### Verification tooling — Android caveat

`uiautomator dump` returns `ERROR: null root node` on NovaGram's own settings screens, and
`screencap` returns zero bytes on the device-blocked screen. Neither is a fault: read the
shipped text out of the APK instead, which is stronger evidence anyway —

```bash
aapt2 dump resources app.apk | grep -A 3 "string/NovaPushPreviewInfo"
```

It prints the default and the `(ru)` value side by side, so a missing translation shows up
immediately.
