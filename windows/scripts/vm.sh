#!/bin/sh
# Run PowerShell in the Parallels VM, inside this windows/ folder as seen through the Mac share.
#   ./scripts/vm.sh 'dotnet test SqueezeBar.Media.Tests'
# Nothing is copied into Windows: build output lands in windows/.artifacts-win (see Directory.Build.props).
# Runs as SYSTEM, so GUI apps started this way are invisible; launch those with
#   prlctl exec "$SQUEEZEBAR_VM" --current-user cmd /c 'start "" <path to exe>'
VM="${SQUEEZEBAR_VM:-Windows 11 Enterprise}"
SHARE='\\Mac\Home\Documents\Project\SqueezeBar\windows'
SCRIPT="\$ProgressPreference='SilentlyContinue'; \$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'; \$env:DOTNET_NOLOGO='1';
Set-Location '$SHARE'; $1"
exec prlctl exec "$VM" powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand \
  "$(printf '%s' "$SCRIPT" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')"
