#!/usr/bin/env bash
# Convenience launcher for the Zig port of the Contacts demo.
# Usage: ./run.sh [port]   (default port: 8769)
set -euo pipefail
cd "$(dirname "$0")"

ZIG_BIN="$(command -v zig || true)"
if [ -z "$ZIG_BIN" ]; then
    # fall back to a nix store install if zig isn't on PATH
    ZIG_BIN="$(find /nix/store -maxdepth 1 -iname '*-zig-*' 2>/dev/null | sort -V | tail -1)/bin/zig"
fi

BIN="$(mktemp -d)/zig-contacts-server"
"$ZIG_BIN" build-exe server.zig -femit-bin="$BIN" -O ReleaseFast
exec "$BIN" "${1:-8769}"
