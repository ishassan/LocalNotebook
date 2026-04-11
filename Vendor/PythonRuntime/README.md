This folder is intentionally excluded from source control for large runtime artifacts.

Expected contents after bootstrapping:

- `Python.xcframework`
- `packages/`
- optional build caches under `build/` and `dist/`

Bootstrap steps:

1. Install full Xcode.
2. Run `./Scripts/bootstrap_python_runtime.sh`
3. Run `./Scripts/bundle_python_packages.sh`
