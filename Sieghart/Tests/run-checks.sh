#!/bin/bash
set -euo pipefail
checks_root="$(cd "$(dirname "$0")" && pwd)"
exec bash "$checks_root/run-swift-tests.sh" "$@"
