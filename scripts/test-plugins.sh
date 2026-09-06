#!/bin/bash
# Compatibility entry point for the existing plugin regression suite.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ./scripts/test.sh --filter PluginSupportTests "$@"
