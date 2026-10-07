#!/bin/sh
# Build the app in the VM and put a ready-to-run copy in windows/dist/SqueezeBar-<arch>/SqueezeBar.exe.
#   ./scripts/publish.sh          # arm64, for the Parallels VM
#   ./scripts/publish.sh x64      # Intel/AMD PCs
# Self-contained: the target PC needs neither .NET nor the Windows App SDK installed.
# Leaves out the Windows App SDK's AI runtime (onnxruntime, DirectML: ~40 MB the app never loads).
# Uses build output rather than `dotnet publish`, which drops the compiled XAML (.xbf/.pri) for unpackaged WinUI apps.
ARCH="${1:-arm64}"
cd "$(dirname "$0")/.." || exit 1
./scripts/vm.sh "Get-Process SqueezeBar -ErrorAction SilentlyContinue | Stop-Process -Force
dotnet build SqueezeBar -c Release -r win-$ARCH --self-contained -v q 2>&1 | Select-String -Pattern ' error ' | Select-Object -First 15 -Unique | Out-String -Width 300
robocopy .artifacts-win\\bin\\SqueezeBar\\release_win-$ARCH dist\\SqueezeBar-$ARCH /MIR /XF *.pdb onnxruntime*.dll DirectML.dll /NFL /NDL /NJH /NJS /NP | Out-Null
Remove-Item dist\\SqueezeBar-$ARCH\\onnxruntime*.dll, dist\\SqueezeBar-$ARCH\\DirectML.dll, dist\\SqueezeBar-$ARCH\\*.pdb -ErrorAction SilentlyContinue
Get-Item dist\\SqueezeBar-$ARCH\\SqueezeBar.exe | Select-Object FullName, LastWriteTime | Format-List | Out-String"
