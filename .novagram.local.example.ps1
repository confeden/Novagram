# Copy to .novagram.local.ps1 and fill in with your own values.
# .novagram.local.ps1 is gitignored; this example must stay free of secrets.
$env:NOVA_TELEGRAM_API_ID = "<your api_id>"
$env:NOVA_TELEGRAM_API_HASH = "<your api_hash>"
$env:NOVAGRAM_ANDROID_KEYSTORE = "<path to your release .jks>"
$env:NOVAGRAM_PFX = "<path to your code signing .pfx>"
# package-desktop-inno.ps1 requires a non-empty password: signing is mandatory.
$env:NOVAGRAM_PFX_PASSWORD = "<your pfx password>"
