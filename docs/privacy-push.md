# Push privacy baseline

NovaGram starts as a mirror of the official clients. Privacy changes are staged after clean builds work.

Android FCM in the official client receives a data field `p` in `GcmPushListenerService`, then `PushListenerController` decrypts it locally with `SharedConfig.pushAuthKey`.

Initial policy:

- Keep FCM available for the first mirror build.
- Do not add normal Android notification `title/body` payloads.
- Later add two build profiles:
  - `standard`: FCM encrypted wake-up, server-side previews forced off.
  - `strict-foss`: no Firebase registration, notifications via MTProto background/foreground connection only.

Required later patch points:

- `TMessagesProj/src/main/java/org/telegram/messenger/GcmPushListenerService.java`
- `TMessagesProj/src/main/java/org/telegram/messenger/PushListenerController.java`
- `TMessagesProj/src/main/java/org/telegram/messenger/NotificationsController.java`
- `TMessagesProj/src/main/java/org/telegram/ui/NotificationsCustomSettingsActivity.java`

Do not alter self-destruct media, deleted message behavior, spam limits, read semantics, or server-side protocol behavior.

