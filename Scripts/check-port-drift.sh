#!/usr/bin/env bash
# Snapshot of how far the AppLauncher/ + InputSource/ ports have drifted
# from their Selector source-of-truth. Diagnostic tool only — no CI gate,
# no exit-1 on threshold. Run after port-related refactors and eyeball the
# trend; large jumps for InputSource files (small focused ports) deserve
# review. AppLauncher files compare against ShortcutCellView.swift which
# selector still holds as one big file, so high counts there are mostly
# structural splitting noise, not real divergence.
#
#   ./Scripts/check-port-drift.sh
#   SELECTOR_ROOT=/path/to/checkout ./Scripts/check-port-drift.sh

set -euo pipefail

SELECTOR_ROOT="${SELECTOR_ROOT:-/Users/ank/dev/selector/selector}"
CLIPY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -d "$SELECTOR_ROOT" ]]; then
    echo "Selector source-of-truth not found at $SELECTOR_ROOT" >&2
    echo "Set SELECTOR_ROOT to its checkout to enable drift detection." >&2
    exit 0
fi

mappings=(
    "Clipy/Sources/InputSource/InputSource.swift|InputSourceManager.swift"
    "Clipy/Sources/InputSource/TISInputSource+Additions.swift|InputSourceManager.swift"
    "Clipy/Sources/InputSource/InputSourceService.swift|InputSourceManager.swift"
    "Clipy/Sources/AppLauncher/AppIndex.swift|ShortcutCellView.swift"
    "Clipy/Sources/AppLauncher/Calculator.swift|ShortcutCellView.swift"
    "Clipy/Sources/AppLauncher/LauncherPanel.swift|ShortcutCellView.swift"
    "Clipy/Sources/AppLauncher/AppLauncher.swift|ShortcutCellView.swift"
    "Clipy/Sources/AppLauncher/AppLauncherService.swift|ShortcutCellView.swift"
)

for entry in "${mappings[@]}"; do
    clipy_path="${entry%%|*}"
    selector_path="${entry##*|}"
    clipy_full="$CLIPY_ROOT/$clipy_path"
    selector_full="$SELECTOR_ROOT/$selector_path"
    if [[ ! -f "$clipy_full" ]]; then
        printf "MISSING        %s\n" "$clipy_path"
        continue
    fi
    if [[ ! -f "$selector_full" ]]; then
        printf "no upstream    %s\n" "$clipy_path"
        continue
    fi
    changed=$(diff -u "$selector_full" "$clipy_full" | grep -c '^[+-][^+-]' || true)
    printf "%5d lines  %s  vs  %s\n" "$changed" "$clipy_path" "$selector_path"
done
