# Desktop (tdesktop / Qt) code traps
Expands G13-G20, N7-N11, M1, M6. Read before editing message rendering, Qt networking,
window handling or `Storage` blobs in `desktop/novagram-desktop`.

## G13 — a custom draw branch must come before `countGeometry()`

In `history_view_message.cpp`, `Message::draw`, `pointState` and `textState` all start with
`countGeometry()` and return early when `g.width() < 1`. An element that does not pass the
stock size calculation has degenerate geometry, so any custom code placed after that call
sits below the early return and never runs. Put the fork's branch **before** it.

## G14 — `HistoryInner::paint` draws avatars after messages

Anything that must land on top of an avatar has to be drawn where the avatar is drawn (next
to `Dialogs::Ui::PaintUserpic`), not inside `Message::draw`.

## G15 — a full-width link steals the avatar's context menu

`HistoryInner::mouseActionUpdate` only checks the avatar if a link did not already claim the
point. Custom links must exclude the avatar's rectangle.

## G16 — click handlers are compared by pointer

A handler recreated on every `textState` query will never match press to release, and the
click is lost. Cache handlers by `FullMsgId`.

## G17 — `p.setOpacity` around `Message::draw` does nothing

More than forty places inside hard-reset the opacity back to 1.

## G18 — `EncryptedDescriptor` without an explicit size does not open the buffer

Whatever is written is silently lost and an empty block is encrypted.

## G19 — Qt: `abort()` throws away the read buffer

`setTransferTimeout` makes Qt call `abort()`, which closes the `QNetworkReply`; closing a
`QIODevice` discards everything received. Data must be read **as it arrives**
(`readyRead`), otherwise there is nothing to resume from: the progress bar shows 74 % while
the log says `download failed at 0 bytes`.

Conversely, a `QNetworkReply` **without** `setTransferTimeout` never finishes at all when
there is no response: `finished` never arrives and the phase stays `Checking` for the rest
of the session. Both are needed together.

(Android had the same class of failure for a different reason — `read()` only returned what
it had accumulated on a successful exit; it now writes into the caller's buffer.)

## G20 — the OpenGL capability probe leaves two empty 640x480 windows

Upstream's `Ui::GL::CheckCapabilities` creates a temporary window and "destroys" it in a way
that leaves the native window alive for the rest of the process. They must not be destroyed
(see N7); `nova_screen_guard.cpp` moves them off-screen instead.

## N7 — destroying foreign windows by "class is `QWidget`" is not safe

Tried and rejected. That class also covers Telegram's own service windows: the tray icon
refresher, the notification sample in settings, crash-report windows, power-saving and
media-key helpers. The weaker signal "Qt considers the window hidden", without a class check,
matches the main window minimized to tray.

## N8 — the empty windows are not a painting artifact

They are real windows: the user dragged another window across the rectangle and the
rectangle did not get erased.

## N9 — the fork's event filter does not create them

The `QEvent::WinIdChange` fix was kept (a filter should not create windows) but the windows
did not go away after it.

## N10 — Qt 6 is not an option for released builds

Upstream `Telegram/build/qt_version.py` selects Qt 5.15.19 on win32 without the `qt6` flag,
and that is what the official client ships. Qt 6.11.1 changes font rasterization to
DirectWrite (text looks noticeably thinner than the official client) and moves window
painting to QRhi over D3D11, which makes dragging the window visibly less smooth.

## N11 — no `sccache` / `ccache` for MSVC

Not in the toolchain, gets along badly with the precompiled header, and would require
reconfiguring CMake.

## Branding boundary

`NovaGram::WithAppName()` rewrites an already-assembled string, which is how every
translation is covered without editing `lang.strings`. It only applies where that function is
called: internal strings, logs, the data folder name and the `AppFile` constant stay
"Telegram" (`version.h`). In decoy mode branding rolls back to "Telegram Desktop" in exactly
two places — the About window title and the main-menu caption. Neither `AppName()` nor
`WithAppName()` knows about the decoy, so the tray, the Windows jump list and the
notification sample in stock settings keep calling the fork by its name.

## Decoy network barrier placement

The barrier sits in `Instance::Private::sendRequest` (`mtp_instance.cpp:1050`) **before** the
`getSession()` call: the `NovaGram::Decoy::Active()` check is at `:1058` and
`const auto session = getSession(shiftedDcId);` is at `:1066`. Asking for the session would
already create the transport and start connecting, so the check diverts to
`answerOffline(...)` instead. That handler answers from generated data and delivers the reply
on the main thread by the same path a real one takes. The config loader, the proxy-domain
resolver and HTTP time sync are disabled separately, otherwise a fallback path would fire
around MTProto.

**Do not confuse this with `:382`.** That is a different barrier — the first statement of
`Instance::Private::start()`, which returns before any session or config loader is created
(a session opens a datacenter socket the moment it exists, and the config loader falls back
to public DoH resolvers). Nine `Decoy::Active()` checks live in this file; `kb/map.md#m6`
lists them. The knowledge base once attached the sendRequest/`getSession` description to
`:382`, sending readers ~676 lines into the wrong function.

Boundary: only the MTProto protocol inside `MTP::Instance` is cut. Anything that reaches the
network outside it (opening a link in the external browser, for instance) is not covered.
