#!/usr/bin/env bash
# Convenience launcher for the PicoLisp port of the Contacts demo.
# Usage: ./run.sh [port]   (default port: 8766)
set -euo pipefail
cd "$(dirname "$0")"
exec pil server.l -main "${1:-8766}" +
