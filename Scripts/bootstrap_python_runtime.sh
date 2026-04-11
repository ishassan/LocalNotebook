#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT/Vendor/PythonRuntime"
BUILD_DIR="$VENDOR_DIR/build"
DIST_DIR="$VENDOR_DIR/dist"
PYTHON_VERSION="${PYTHON_VERSION:-3.14.4}"
CPYTHON_TARBALL="Python-$PYTHON_VERSION.tgz"
CPYTHON_URL="https://www.python.org/ftp/python/$PYTHON_VERSION/$CPYTHON_TARBALL"
CPYTHON_SRC="$BUILD_DIR/Python-$PYTHON_VERSION"

mkdir -p "$BUILD_DIR" "$DIST_DIR" "$VENDOR_DIR/packages"

if [ ! -d "$CPYTHON_SRC" ]; then
  curl -L "$CPYTHON_URL" -o "$BUILD_DIR/$CPYTHON_TARBALL"
  tar -xzf "$BUILD_DIR/$CPYTHON_TARBALL" -C "$BUILD_DIR"
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Full Xcode is required. The Python docs state that Command Line Tools alone are insufficient for iOS builds."
  exit 1
fi

pushd "$CPYTHON_SRC" >/dev/null
python3 Apple build iOS all --clean \
  ac_cv_func_dup3=no \
  ac_cv_func_pipe2=no
popd >/dev/null

rm -rf "$VENDOR_DIR/Python.xcframework"

XCFRAMEWORK_PATH="$(find "$CPYTHON_SRC/cross-build" -name Python.xcframework -type d | head -n 1)"
if [ -z "$XCFRAMEWORK_PATH" ]; then
  echo "Unable to locate Python.xcframework after build."
  exit 1
fi

cp -R "$XCFRAMEWORK_PATH" "$VENDOR_DIR/Python.xcframework"
echo "Installed Python runtime to $VENDOR_DIR/Python.xcframework"
echo "Next: run ./Scripts/bundle_python_packages.sh"
