#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$HOME/Library/Developer/CoreSimulator/Devices"

echo "Sample notebooks live in $ROOT/Resources/SampleNotebooks"
echo "Import them with the app or copy them into a simulator container manually."
