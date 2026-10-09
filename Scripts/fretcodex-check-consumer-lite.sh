#!/usr/bin/env bash
# FretCodex fork: proves the consumer-lite manifest gate (FRETCODEX.md, F0) still holds.
#
# Builds a throwaway consumer that depends on this checkout by path and links exactly the
# products FretCodex uses, resolves it, and fails if SwiftPM fetched or pinned anything —
# i.e. if any declared product reaches Wirelet or SwiftySynth again. Run after every sync
# with upstream, before tagging.
#
#   Scripts/fretcodex-check-consumer-lite.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${SWIFT_SHEET_MUSIC_DEV:-}" == "1" ]]; then
  echo "error: unset SWIFT_SHEET_MUSIC_DEV — the check is of the consumer (default) shape" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Sources/Probe"
echo 'import SheetMusicCore' > "$work/Sources/Probe/Probe.swift"

cat > "$work/Package.swift" <<EOF
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ConsumerLiteProbe",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [.package(path: "$root")],
    targets: [
        .target(
            name: "Probe",
            dependencies: [
                .product(name: "SheetMusicCore", package: "swift-sheet-music"),
                .product(name: "SheetMusicMSCX", package: "swift-sheet-music"),
                .product(name: "SheetMusicMusicXML", package: "swift-sheet-music"),
                .product(name: "SheetMusicMIDI", package: "swift-sheet-music"),
                .product(name: "SheetMusicLayout", package: "swift-sheet-music"),
                .product(name: "SheetMusicLayoutApple", package: "swift-sheet-music"),
                .product(name: "SheetMusicUI", package: "swift-sheet-music"),
                .product(name: "SheetMusicPDF", package: "swift-sheet-music"),
                .product(name: "SheetMusicOMRModel", package: "swift-sheet-music"),
            ]
        ),
    ]
)
EOF

(cd "$work" && swift package resolve >/dev/null)

fetched=$(ls "$work/.build/checkouts" 2>/dev/null || true)
if [[ -f "$work/Package.resolved" || -n "$fetched" ]]; then
  echo "FAIL: the consumer shape pulls in remote packages:" >&2
  [[ -n "$fetched" ]] && echo "$fetched" | sed 's/^/  /' >&2
  [[ -f "$work/Package.resolved" ]] && grep '"identity"' "$work/Package.resolved" | sed 's/^/  /' >&2
  echo "Re-gate whichever declared product now reaches them (see FRETCODEX.md, F0)." >&2
  exit 1
fi
echo "OK: consumer shape resolves with no remote packages"
