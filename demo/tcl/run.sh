#!/usr/bin/env bash
# Convenience launcher for the Tcl port of the Contacts demo.
# Usage: ./run.sh [port]   (default port: 8767)
set -euo pipefail
cd "$(dirname "$0")"
exec tclsh server.tcl "${1:-8767}"
