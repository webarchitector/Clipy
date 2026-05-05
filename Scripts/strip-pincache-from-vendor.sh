#!/bin/zsh
# Removes PINCache/PINOperation references from the vendored CocoaPods support
# files. Run this after regenerating vendor/Dependencies (e.g. via `pod install`)
# so the local build does not link or embed the unused PINCache framework.
#
# Idempotent: safe to re-run.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
support="$repo_root/vendor/Dependencies/Target Support Files"

if [[ ! -d "$support" ]]; then
    echo "vendor not bootstrapped — nothing to strip"
    exit 0
fi

xcconfigs=(
    "$support/Pods-Clipy/Pods-Clipy.debug.xcconfig"
    "$support/Pods-Clipy/Pods-Clipy.release.xcconfig"
    "$support/Pods-ClipyTests/Pods-ClipyTests.debug.xcconfig"
    "$support/Pods-ClipyTests/Pods-ClipyTests.release.xcconfig"
)

for cfg in "${xcconfigs[@]}"; do
    [[ -f "$cfg" ]] || continue
    sed -i '' \
        -e 's| "${PODS_CONFIGURATION_BUILD_DIR}/PINCache"||g' \
        -e 's| "${PODS_CONFIGURATION_BUILD_DIR}/PINOperation"||g' \
        -e 's| "${PODS_CONFIGURATION_BUILD_DIR}/PINCache/PINCache.framework/Headers"||g' \
        -e 's| "${PODS_CONFIGURATION_BUILD_DIR}/PINOperation/PINOperation.framework/Headers"||g' \
        -e 's| -framework "PINCache"||g' \
        -e 's| -framework "PINOperation"||g' \
        -e 's| "-F${PODS_CONFIGURATION_BUILD_DIR}/PINCache"||g' \
        -e 's| "-F${PODS_CONFIGURATION_BUILD_DIR}/PINOperation"||g' \
        "$cfg"
done

frameworks_sh="$support/Pods-Clipy/Pods-Clipy-frameworks.sh"
if [[ -f "$frameworks_sh" ]]; then
    sed -i '' \
        -e '/install_framework "\${BUILT_PRODUCTS_DIR}\/PINCache\/PINCache.framework"/d' \
        -e '/install_framework "\${BUILT_PRODUCTS_DIR}\/PINOperation\/PINOperation.framework"/d' \
        "$frameworks_sh"
fi

echo "stripped PINCache/PINOperation references from vendor support files"
