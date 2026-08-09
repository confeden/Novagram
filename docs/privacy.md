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
  read receipts, typing indicators, and device registration.
- Firebase Cloud Messaging token and data delivery for push notifications.
- Firebase Remote Config as an official client's connectivity fallback.
- Sponsored-message retrieval, display, view, and click reporting required by
  the Telegram API Terms of Service.

Local application logs and local traffic counters are not uploaded by the
telemetry paths disabled above. Push payload minimization is a separate feature
and is not claimed by this policy.
