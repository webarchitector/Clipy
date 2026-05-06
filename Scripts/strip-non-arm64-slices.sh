#!/bin/zsh

set -euo pipefail

app_bundle_path="${1:?expected app bundle path}"

find "$app_bundle_path" -type f -print0 | while IFS= read -r -d '' candidate; do
    file_output="$(file "$candidate" 2>/dev/null || true)"

    if [[ "$file_output" != *"Mach-O universal binary"* ]] ||
       [[ "$file_output" != *"arm64"* ]] ||
       ([[ "$file_output" != *"x86_64"* ]] && [[ "$file_output" != *"i386"* ]]); then
        continue
    fi

    tmp_path="${candidate}.arm64"
    original_mode="$(stat -f '%Lp' "$candidate" 2>/dev/null || echo 755)"

    if lipo -thin arm64 "$candidate" -output "$tmp_path" 2>/dev/null; then
        chmod "$original_mode" "$tmp_path" 2>/dev/null || true
        mv "$tmp_path" "$candidate"
    else
        rm -f "$tmp_path"
    fi
done
