#!/bin/bash
# Re-extract every user-facing string from the Swift sources into Resources/Localizable.xcstrings.
# Run after adding or changing UI text. New keys appear with English as the source language;
# translations are added to the catalog (Xcode's String Catalog editor works on it directly).
set -e
cd "$(dirname "$0")/.."

CATALOG="Resources/Localizable.xcstrings"
DATA_DIR="$PWD/.build/stringsdata"

rm -rf "${DATA_DIR}"
mkdir -p "${DATA_DIR}"

echo "[SqueezeBar] Compiling with string extraction..."
swift build --scratch-path .build/strings-build \
    -Xswiftc -emit-localized-strings \
    -Xswiftc -emit-localized-strings-path -Xswiftc "${DATA_DIR}" >/dev/null

if [ ! -f "${CATALOG}" ]; then
    echo '{"sourceLanguage":"en","strings":{},"version":"1.0"}' > "${CATALOG}"
fi

ARGS=()
for f in "${DATA_DIR}"/*.stringsdata; do
    ARGS+=(--stringsdata "$f")
done

xcrun xcstringstool sync "${CATALOG}" "${ARGS[@]}"
echo "[SqueezeBar] Updated ${CATALOG}"
