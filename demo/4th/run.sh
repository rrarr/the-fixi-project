#!/usr/bin/env bash
# Launcher for the 4tH (4th) port of the Contacts demo.
#
# 4tH has no socket words at all -- only pipe/file I/O -- so this isn't a
# standalone server like the other four ports. socat does the actual TCP
# accept loop and, per connection, execs a fresh `4th` process with the
# client socket wired to its stdin/stdout (the same "inetd CGI" model
# this distribution's own 4th/web4th.4th example documents). One
# process = one request; the contact store persists across requests as
# a flat file (contacts.dat) read and rewritten each time, not an
# in-memory structure like the other ports.
#
# Usage: ./run.sh [port]   (default port: 8771)
set -euo pipefail
cd "$(dirname "$0")"

BIN4TH="$(command -v 4th || true)"
if [ -z "$BIN4TH" ]; then
    BIN4TH="$(find /nix/store -maxdepth 1 -iname '*-4th-*' 2>/dev/null | sort -V | tail -1)/bin/4th"
fi
export DIR4TH="${DIR4TH:-/home/rrarr/src/4th/4th-3.64.2/4th/}"

SOCAT="$(command -v socat)"
PORT="${1:-8771}"

echo "Contacts demo (4tH, via socat CGI) listening on http://localhost:${PORT}/contacts.html"
exec "$SOCAT" TCP-LISTEN:"${PORT}",reuseaddr,fork \
    EXEC:"${BIN4TH} cxq contacts.4th contacts.dat"
