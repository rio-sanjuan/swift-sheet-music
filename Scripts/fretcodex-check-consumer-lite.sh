#!/usr/bin/env bash
# FretCodex fork: proves the consumer-lite manifest gate (FRETCODEX.md, F0) still holds.
#
# Builds a throwaway consumer that depends on this checkout by path and links exactly the
# products FretCodex uses, resolves it, and fails if SwiftPM fetched or pinned anything —
# i.e. if any declared product reaches Wirelet or SwiftySynth again. Run after every sync
# with upstream, before tagging.
#
#   Scripts/fretcodex-check-consumer-lite.sh
#
# Works from a checkout of any name. SwiftPM names a path dependency after its directory — the
# package identity is the lowercased last path component, not the manifest's `name` — so the probe
# addresses the products by that identity, worked out from the checkout's physical path (symlinks
# resolved, which is the path the probe hands SwiftPM).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
identity="$(basename "$root" | tr '[:upper:]' '[:lower:]')"
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
                .product(name: "SheetMusicCore", package: "$identity"),
                .product(name: "SheetMusicMSCX", package: "$identity"),
                .product(name: "SheetMusicMusicXML", package: "$identity"),
                .product(name: "SheetMusicMIDI", package: "$identity"),
                .product(name: "SheetMusicLayout", package: "$identity"),
                .product(name: "SheetMusicLayoutApple", package: "$identity"),
                .product(name: "SheetMusicUI", package: "$identity"),
                .product(name: "SheetMusicPDF", package: "$identity"),
                .product(name: "SheetMusicOMRModel", package: "$identity"),
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
