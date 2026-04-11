#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$ROOT/Vendor/PythonRuntime/packages"
REQ_FILE="$ROOT/Vendor/PythonRuntime/requirements.txt"

mkdir -p "$TARGET_DIR"

cat >"$REQ_FILE" <<'EOF'
packaging==25.0
pyparsing==3.2.5
python-dateutil==2.9.0.post0
six==1.17.0
EOF

python3 -m pip install --upgrade --target "$TARGET_DIR" -r "$REQ_FILE"
echo "Bundled pure-Python packages into $TARGET_DIR"
echo "Note: plotting support is provided by the app-bundled matplotlib compatibility shim in Resources/PythonApp."
