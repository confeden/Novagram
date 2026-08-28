# NovaGram privacy boundary

NovaGram disables optional analytics and crash-report delivery while preserving
network operations required to provide Telegram functionality.

## Disabled

- Telegram Desktop crash-report generation and upload.
- Telegram Desktop and Android `help.saveAppLog` event delivery.
- Android Firebase App Indexing user-action reporting.
- Android AppCenter, Firebase Crashlytics, and Huawei distribution variants in
  the active Gradle build graph.
- Firebase Analytics, Crashlytics, Performance, advertising-ID collection, and
  automatic screen reporting through Android manifest policy.

## Retained operational traffic

- MTProto authentication, message synchronization, media transfer, presence,
  typing indicators, and device registration. Read receipts are covered by a
  separate feature and are not unconditionally retained.
- Sponsored-message retrieval, display, view, and click reporting required by
  the Telegram API Terms of Service. Sponsored *search* suggestions are not:
  that request carried the text typed into the search box, which is content
  rather than an ad impression, and it was removed.

## Not present in shipped builds

Two entries previously listed as retained traffic do not occur at all, and are
recorded here so the claim is not made again:

- **Firebase Cloud Messaging.** The Firebase configuration resources are absent
  from the APK, so `FirebaseApp.initializeApp()` returns null, messaging never
  initialises, and no token is ever obtained or registered. Notifications
  therefore arrive only over the client's own connection while it is alive.
- **Firebase Remote Config.** Removed by upstream Telegram itself; the
  emergency-configuration chain in this base has two steps and neither is
  Firebase.

Local application logs and local traffic counters are not uploaded by the
telemetry paths disabled above. Push payload minimization is a separate feature
and is not claimed by this policy.
