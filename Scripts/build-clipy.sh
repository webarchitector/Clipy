#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./Scripts/build-clipy.sh signed
  ./Scripts/build-clipy.sh unsigned

Modes:
  signed    Build Release with the "Clipy Dev" code-signing identity.
  unsigned  Build Release with code signing disabled.
EOF
}

build_mode="${1:-}"
if [[ "$build_mode" != "signed" && "$build_mode" != "unsigned" ]]; then
    usage >&2
    exit 2
fi
if (( $# != 1 )); then
    usage >&2
    exit 2
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild was not found. Install Xcode and select its developer directory." >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
workspace_path="$repo_root/Clipy.xcworkspace"
configuration="Release"

if [[ ! -d "$workspace_path" ]]; then
    echo "Workspace not found: $workspace_path" >&2
    exit 1
fi

if [[ "$build_mode" == "signed" ]]; then
    identity_name="Clipy Dev"
    if ! security find-identity -v -p codesigning 2>/dev/null \
        | grep -Fq "\"${identity_name}\""; then
        echo "Code-signing identity '${identity_name}' was not found." >&2
        echo "Create it with: $script_dir/create-clipy-dev-certificate.sh" >&2
        exit 1
    fi

    output_dir="$repo_root/build/Release"
    echo "Building signed Clipy.app..."
    xcodebuild \
        -workspace "$workspace_path" \
        -scheme Clipy \
        -configuration "$configuration" \
        CONFIGURATION_BUILD_DIR="$output_dir" \
        CODE_SIGN_IDENTITY="$identity_name" \
        CODE_SIGN_STYLE=Manual \
        build
else
    derived_data_dir="$repo_root/build/DerivedData"
    output_dir="$derived_data_dir/Build/Products/Release"
    echo "Building unsigned Clipy.app..."
    xcodebuild \
        -workspace "$workspace_path" \
        -scheme Clipy \
        -configuration "$configuration" \
        -derivedDataPath "$derived_data_dir" \
        CODE_SIGNING_ALLOWED=NO \
        build
fi

app_path="$output_dir/Clipy.app"
if [[ ! -d "$app_path" ]]; then
    echo "Build completed, but the app bundle was not found: $app_path" >&2
    exit 1
fi

echo
echo "Build succeeded:"
echo "$app_path"
