#!/usr/bin/env bash
# Launcher for the Gforth port of the Contacts demo.
#
# Unlike 4tH, Gforth has a real socket library (unix/socket.fs, backed
# by an actual C extension) and ANS-standard READ-FILE/READ-LINE that
# behave correctly on a live socket -- so this is a true standalone
# server with a persistent in-memory store, same architecture as the
# Node/Tcl/PicoLisp/Zig ports (no inetd/socat workaround needed).
#
# Usage: ./run.sh [port]   (default port: 8776)
set -euo pipefail
cd "$(dirname "$0")"

GFORTH="$(command -v gforth || true)"
if [ -z "$GFORTH" ]; then
    # nixpkgs-unstable's gforth derivation is currently broken (swig
    # build failure); nixos-24.05's cached binary build works. Fall
    # back to it directly, picking only real built derivations (paths
    # with an actual bin/gforth, not unbuilt .drv files).
    for d in /nix/store/*-gforth-*; do
        [ -x "$d/bin/gforth" ] && GFORTH="$d/bin/gforth" && break
    done
fi
if [ -z "$GFORTH" ]; then
    echo "gforth not found -- run: nix --extra-experimental-features 'nix-command flakes' shell github:NixOS/nixpkgs/nixos-24.05#gforth" >&2
    exit 1
fi

PORT="${1:-8776}"
exec "$GFORTH" server.fs -e "${PORT} serve bye"
