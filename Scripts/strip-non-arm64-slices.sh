#!/bin/zsh

set -euo pipefail

app_bundle_path="${1:?expected app bundle path}"
checked_count=0
stripped_count=0

# Avoid `find | file` here. That combination completes normally in Terminal
# but can stall when this script runs as an Xcode build phase. Clipy embeds
# binaries only in Contents/MacOS and top-level frameworks, so direct zsh
# globs cover every Mach-O without walking resources or signing metadata.
candidates=(
    "$app_bundle_path"/Contents/MacOS/*(N)
    "$app_bundle_path"/Contents/Frameworks/*.framework/Versions/A/*(N)
)

echo "Checking ${#candidates[@]} executable candidates for non-arm64 slices..."

for candidate in "${candidates[@]}"; do
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    ((checked_count += 1))
    architectures="$(lipo -archs "$candidate" 2>/dev/null || true)"

    if [[ "$architectures" != *"arm64"* ]] ||
       ([[ "$architectures" != *"x86_64"* ]] && [[ "$architectures" != *"i386"* ]]); then
        continue
    fi

    tmp_path="${candidate}.arm64"
    original_mode="$(stat -f '%Lp' "$candidate" 2>/dev/null || echo 755)"

    if lipo -thin arm64 "$candidate" -output "$tmp_path" 2>/dev/null; then
        chmod "$original_mode" "$tmp_path" 2>/dev/null || true
        mv "$tmp_path" "$candidate"
        ((stripped_count += 1))
        echo "Stripped non-arm64 slices: ${candidate#$app_bundle_path/}"
    else
        rm -f "$tmp_path"
    fi
done

echo "ARM64 slice check complete (${checked_count} executables checked, ${stripped_count} stripped)."
