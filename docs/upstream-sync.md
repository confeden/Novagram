# Upstream sync

## Android

Repository:

```text
android/novagram-android
```

Remote:

```text
upstream = https://github.com/DrKLO/Telegram.git
```

Sync:

```powershell
cd D:\Documents\Coding\NovaGram\android\novagram-android
git fetch upstream
git merge upstream/master
```

## Desktop

Repository:

```text
desktop/novagram-desktop
```

Remote:

```text
upstream = https://github.com/telegramdesktop/tdesktop.git
```

Current base:

```text
v6.9.4
```

Sync beta:

```powershell
cd D:\Documents\Coding\NovaGram\desktop\novagram-desktop
git fetch --tags upstream
git checkout -b novagram/<new-version> <tag>
git submodule update --init --recursive
```

