# Privacy design — invariant rationales and known residual holes
Expands I1-I8, I14, G9-G12, N1, D9, D13-D14 and the open questions the old roadmap listed.
Read before changing read-status hiding, the decoy, notifications, storage, device binding,
DoH scope or calls.

The repo's own Russian design notes already cover: upstream pinning, the one-release scheme,
branding via `NovaGram::WithAppName()`, the storage/encryption table, how the network is cut
in the decoy, and the upstream insertion points — `docs/internals.md`. DoH internals and its
editing rules are `docs/doh.md`; calls are `docs/calls.md`; peer IDs are `docs/peer-id.md`;
what upstream Telegram leaves on the device is `docs/upstream-baseline.md`; the feature
comparison is `docs/features.md`. This file holds the reasoning those files do not carry.

## I1 — metadata lives in sealed containers, never in plain settings

Anything that is itself metadata — silenced dialogs, muted members, the auto-delete queue,
read-status rules — lives in AES/GCM sealed containers with their own Keystore key on
Android, and in `session->local()` blobs on desktop. `SharedPreferences` is **forbidden**
for such lists.

Every container is tagged with its owner. Account slots are reused, and without the tag the
previous account's blob would be handed to the next one.

The split is deliberate, not incidental: the auto-delete queue is a list of
`dialog + message id` pairs, i.e. exactly the metadata the fork promises to protect. Flags
like "night silent is on" are not secret and belong in the ordinary settings file. That is
also an honest boundary — app-level settings are read before the PIN is entered.

Android Keystore keys are all created with `setUserAuthenticationRequired(false)`: biometrics
and the device lock screen are not bound to them. The key's protection level (StrongBox, TEE
or software) is computed but not shown to the user.

## I14 — the stolen-folder hole, and what closes it

Upstream Telegram makes an installation's data **portable by construction**, and that is the
single most valuable thing on the disk:

- Desktop derives the key for `tdata` from the local passcode, and the default passcode is
  the *empty string* (`Domain::generateLocalKey` → `encryptLocalKey(QByteArray())`). So a
  copied `tdata` folder opens on any other computer, and the client comes up already signed
  in. The servers see nothing new: the authorization key is the same one, so there is no
  new-device notice, no cloud-password prompt, no active-session entry to notice.
- Android writes `tgnet.dat` — the datacenter authorization keys — in the clear. Same result
  for anyone who can read `/data/data/<package>`.

**What is sealed.** Not the whole tree: exactly the one value everything else hangs from.

- Desktop: `keyEncrypted` inside `tdata/key_data` — the passcode-encrypted local key. Every
  other file under `tdata`, message cache included, is encrypted with the local key, so
  wrapping that one blob covers all of it and costs one AES-GCM operation per accounts write.
  The wrapper is `NVD1` + 12-byte nonce + AES-256-GCM, AAD = the magic.
- Android: the whole payload of `tgnet.dat`, magic `NVC1`, same construction, done natively
  because that file is written by the tgnet library and never passes through Java.

**Where the machine secret lives.**

- Desktop `tdata/novagram_device`: 32 random bytes protected with DPAPI (current user) using
  the machine fingerprint as extra entropy. Fingerprint = SHA-256 over `MachineGuid` and the
  system volume serial (N14). Without DPAPI it falls back to deriving the secret from the
  fingerprint alone — weaker, and reported as such in settings, but a copied folder on its
  own still opens nothing.
- Android `no_backup/novagram/device/binding.v1`: 32 random bytes wrapped by a non-exportable
  Keystore key (StrongBox attempted first). Software backing is accepted here, unlike the
  cache KEK: the question is whether the key travels with a copy of the data directory, and
  even a software Keystore key lives outside it.

**Detection is driven by the ciphertext, not by the setting.** Deleting the binding file does
not disarm anything: the magic is still in front of the sealed value, and a sealed value with
no secret is a foreign one. That is also why a binding file that exists but cannot be parsed
counts as foreign rather than as "rebind me".

**Honest limits, in the order they matter.**

1. Code running as the same Windows user, or as this application on this phone, can ask
   DPAPI or the Keystore for the same answer. Only a PIN helps there.
2. A full disk image plus the Windows account password defeats DPAPI offline. TPM sealing
   would close that and is not implemented; the backend enum has room for it (P4).
3. App-level settings (`tdata/settings1`, `SharedPreferences`) are not sealed — they are read
   before any key exists. They hold no authorization.
4. The server session survives everything here. Nothing in this feature can end a session
   from a device that cannot prove it owns it; that is done from the real device or from the
   account's active-sessions list.

## I2 — read-status hiding: the rule is decided once, from the dialog's origin

A dialog that was not in the chat list before its first incoming message was **started by
the other side**. That is the whole test, and it is evaluated once per dialog.

Server-side `read_inbox_max_id` / `read_outbox_max_id` are unusable for this **in principle**:
they survive deletion of the conversation and come back when a new one is written, i.e. they
answer "have these two ever talked", not "did the user write here". See N1, N2.

Exactly three things lift the hiding, all irreversibly:
1. the button on the banner above the chat,
2. any ordinary message from the user into that dialog (including from another device),
3. **the user's own reaction to the other side's message** — the peer sees it, named, so it
   announces reading no more quietly than a reply would.

A reaction to one's own message means nothing. The hook points are `Reactions::send` and
`SendMessagesHelper.sendReaction` — one per platform, and both placing and removing a
reaction go through them.

The gate is asked before every conversation with the server and answers "hidden" while the
answer is not yet known: an unsent receipt can be sent later, a sent one cannot be recalled.
Undecided receipts are not dropped but **held** (`ReadStatusPending` on desktop,
`novaHeldDialogReads` / `novaHeldContentReads` on Android).

`ReadStatusHiddenFor()` is the single gate, queried from every point that sends an
acknowledgement, `markContentsRead` included — otherwise the "not yet played" dot would
disappear on the other side.

### Open: residual window on desktop

Desktop has no local message store, so there is nobody to ask "did the user write here". A
message arriving into an old dialog that sits below the loaded pages *during the first list
load* is indistinguishable from a new one: the server will not return that dialog again in
the remaining pages. Android answers correctly from its cache.

The only way to close it is `messages.search` with `from_id = self`. Not added: `from_id`
behaviour in private chats is untested, and getting it wrong would disable the feature
entirely.

### Open: rules do not sync between devices

Neither read-status hiding nor member muting syncs. Messages written before a group was
converted to a supergroup live under the old chat id and are not collapsed.

## I3 — notifications: two different mechanisms, two table rows

"Text is not given to the push servers" is an **account** property (`show_previews=false`
sent to the server). Local hiding of the content is a property of **the screen**. They are
different mechanisms, which is why the status matrix has two rows.

Platform differences that matter:
- On Android, hiding the content also removes the sender's small avatar: `preview[0]` carries
  both the text and the avatar load.
- Upstream returns `rich_message` above the preview gate — an upstream defect; the fork checks
  its own switch separately.
- Popup, widgets and Android Auto draw text bypassing the composers, so the gate is placed at
  each of those points. Desktop has none of them.
- `reply_markup` button captions are written by the sender ("YES, IT'S ME" under hidden text
  tells you what the text was), so when hiding, buttons are not added at all, except the
  local "Copy".
- On desktop `show_previews` is the only field of this kind the client **reads** (the name of
  whoever left a reaction), so the echo is split: a `false` originating from the client itself
  is not let into the local value.

## I4 — the decoy never writes its own rules

No fork feature writes its own rules inside the decoy and none of them names NovaGram. The
check is placed at the module's single entry point, not at every caller.

### What the decoy cannot do, by construction

Over a *running* session it leaves already-open sockets: new ones are not created, but
existing ones only close on logout, and logout depends on the network. A cold start does not
have this problem.

On Android the package name, icon and label stay NovaGram; the marker
`no_backup/novagram/security/decoy.marker` sits on disk under an explicit name; wiping the
app's data removes it along with everything else. The decoy is designed against coerced
unlocking, not against forensics.

Android's decoy responder returns objects without serialization, while parts of the client
read raw flag bits — `current = true` alone is not enough, `flags |= 1` is also required.

## I5 — what the DoH promise actually means

**Ordinary client operation uses DNS not at all:** the first connection goes to hardcoded
IPs, after which DC addresses arrive in `help.getConfig`. So the promise is not "all traffic
over DoH" but: **every name the client resolves itself goes only through the four hardcoded
endpoints** — the proxy domain, the emergency DC config, time sync, and the fork's own update
check.

**Never covered:** WebView, the external browser, Play Services, WebRTC, the OS's own DNS.
DoH hides the content of the query but not the fact of the conversation: SNI is visible.

The HTTP tail (`ImageLoader`, `ui/web/Http*Task`, `file_download_web.cpp`) is **not** on DoH
and is recorded as a boundary.

A user-installed CA no longer intercepts DoH on either platform: on Android via
`novagram_network_security_config.xml`, on desktop via ten roots compiled into
`nova_doh_roots.h`, which as a side effect also disables loading roots from the Windows
store. A user's own server does not get pinning — they are entitled to run a private CA.

### D9 — the DNS promise was reworded (owner decision)

Was: the list cannot be reassigned "by the user, by settings, by the system or by the
network". Now: **neither the system, nor the network, nor `hosts`, nor Private DNS influences
the resolver choice or becomes a fallback, and the list itself is edited by the device
owner** — any of the four hardcoded entries can be turned off and a custom one added.

The weakening is in exactly one place and is deliberate: the promise was made against
*someone else's* substitution, not against the person's own choice. The default is unchanged
— the same four endpoints in the same order.

## I6 — calls are relay-only as a local guarantee

Calls are **enabled**. Relay-only is a local guarantee, not a request to the server. The
server's permission (`phoneCall.p2p_allowed`) intersects the fork's policy at the single
point where the instance is constructed.

Under relay-only `udp_p2p` is not announced, and domain names in call addresses are
**discarded**: the string goes into `rtc::SocketAddress` as-is, and a name there would go to
the system `getaddrinfo`. Resolving it over DoH would be *wrong* — it would hide the name and
leave the leak of the fact intact.

`PROTECTED_CALLS` is a non-user invariant; the user-facing switch is `CALLS_RELAY_ONLY`.

## I7 — do not send fields whose value the client does not know

`updateServerNotificationsSettings` is not "change one field". It unconditionally sets
`flags |= 8` and, when there is no local sound, substitutes `notificationSoundDefault`,
overwriting the dialog's server-side sound. Harmless for a manual edit, not for a background
sweep.

General rule: **never send fields whose values the client does not know.** Serializing an
*empty* settings area is a `resetToDefault` — the account loses mute, sound and story
settings.

## I8 — a hiding feature must have a visible way to turn it off

Otherwise it is irreversible in practice. The first desktop version of member muting broke on
exactly this: it hid the avatar, and the avatar was the only entry point to undoing it.

## Update checking and the network

The update check goes to GitHub, which is blocked on some networks: a proxy is needed, and an
MTProto proxy will not do — it only speaks the Telegram protocol.

Fork network requests bypass the proxy by default. `Sandbox::refreshGlobalProxy()` sets
`setApplicationProxy(NoProxy)` when the Telegram proxy is off, overriding the system setting
for every `QNetworkAccessManager` in the process. So the checker asks for itself: the Telegram
proxy if it is SOCKS5 or HTTP, otherwise `QNetworkProxyFactory::systemProxyForQuery` (system
plus PAC). Android does the same through `SharedConfig.currentProxy`.

## Cold-start gate on Android

`UserConfig.getCurrentUser()` returns `null` at the cold-start gate — the gate comes up before
the config is loaded into memory. Read the saved account block from `userconfing` and
deserialize it.
