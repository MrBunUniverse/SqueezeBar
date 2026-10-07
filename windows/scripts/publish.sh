#!/bin/sh
# Build the app in the VM and put a ready-to-run copy in windows/dist/SqueezeBar-<arch>/SqueezeBar.exe (a small launcher; the app and its DLLs sit in app/).
#   ./scripts/publish.sh          # arm64, for the Parallels VM
#   ./scripts/publish.sh x64      # Intel/AMD PCs
# Also zips it (inside the VM, since dist/ is owned by the VM user) to dist/SqueezeBar-windows-<arch>.zip, the fixed name the README download buttons expect.
# Self-contained: the target PC needs neither .NET nor the Windows App SDK installed.
# Leaves out the Windows App SDK's AI runtime (onnxruntime, DirectML: ~40 MB the app never loads).
# Uses build output rather than `dotnet publish`, which drops the compiled XAML (.xbf/.pri) for unpackaged WinUI apps.
ARCH="${1:-arm64}"
cd "$(dirname "$0")/.." || exit 1
./scripts/vm.sh "Get-Process SqueezeBar -ErrorAction SilentlyContinue | Stop-Process -Force
dotnet build SqueezeBar -c Release -r win-$ARCH --self-contained -v q 2>&1 | Select-String -Pattern ' error ' | Select-Object -First 15 -Unique | Out-String -Width 300
dotnet publish SqueezeBar.Launcher -c Release -r win-$ARCH -v q 2>&1 | Select-String -Pattern ' error ' | Select-Object -First 15 -Unique | Out-String -Width 300
Remove-Item dist\\SqueezeBar-$ARCH -Recurse -Force -ErrorAction SilentlyContinue
robocopy .artifacts-win\\bin\\SqueezeBar\\release_win-$ARCH dist\\SqueezeBar-$ARCH\\app /MIR /XF *.pdb onnxruntime*.dll DirectML.dll /NFL /NDL /NJH /NJS /NP | Out-Null
Copy-Item .artifacts-win\\publish\\SqueezeBar.Launcher\\release_win-$ARCH\\SqueezeBar.exe dist\\SqueezeBar-$ARCH\\SqueezeBar.exe
Remove-Item dist\\SqueezeBar-windows-$ARCH.zip -ErrorAction SilentlyContinue
tar -a -c -f dist\\SqueezeBar-windows-$ARCH.zip -C dist\\SqueezeBar-$ARCH .
Get-Item dist\\SqueezeBar-$ARCH\\app\\SqueezeBar.exe | Select-Object FullName, LastWriteTime | Format-List | Out-String"
[ -f "dist/SqueezeBar-$ARCH/SqueezeBar.exe" ] || exit 1
[ -f "dist/SqueezeBar-windows-$ARCH.zip" ] || exit 1
echo "dist/SqueezeBar-windows-$ARCH.zip"
