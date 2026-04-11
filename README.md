# LocalNotebook

LocalNotebook is a native iPhone-first SwiftUI app for offline Python scripts and Jupyter notebooks. It recreates the capability set of a local notebook workflow on iPhone.

## Architecture

- `Document layer`: import/export, app-local working copies, recent files, bookmark persistence, autosave-safe storage.
- `Notebook model layer`: tolerant `nbformat` parsing/serialization, cell operations, unknown metadata preservation.
- `Execution layer`: protocol-backed local Python kernel using an embedded CPython runtime, with room for future remote kernels.
- `Rendering layer`: native SwiftUI shell and editors, with `WKWebView` only for HTML/SVG output and rich preview use cases.
- `Session layer`: active notebook/script sessions, autosave, settings, and UI test harness support.

## Build

1. Install full Xcode and an iOS simulator platform.
2. Run `./Scripts/bootstrap_python_runtime.sh`.
3. Run `./Scripts/bundle_python_packages.sh`.
4. Run `xcodegen generate`.
5. Open `LocalNotebook.xcodeproj` in Xcode.
6. Select your team for signing.
7. Build and run `LocalNotebook` on an iPhone simulator or device.

The current machine only has Xcode Command Line Tools, so build verification in this repo is limited until full Xcode is available.

## Runtime strategy

The bootstrap script follows the Python iOS docs and the CPython `Apple/iOS/README.md` workflow: build or obtain `Python.xcframework`, embed it, and run the provided `install_python` helper during the app build to copy the Python standard library and bundled packages into the app bundle.

For plotting in the MVP, the app ships a lightweight pure-Python `matplotlib.pyplot` compatibility shim that renders simple charts to SVG without requiring desktop binary wheels on iOS.

## Tests

- `LocalNotebookTests` covers notebook parsing/serialization, editing operations, autosave snapshots, and session behavior.
- `LocalNotebookUITests` covers import, run, save/reopen, clear outputs, and duplicate using a built-in fixture-import harness.

## Remaining limitations

- Real `interrupt` support is best effort because embedded CPython on iOS does not behave like a separate desktop process.
- Third-party package installation is not exposed in the MVP; only curated pure-Python packages are bundled.
- `matplotlib` compatibility is intentionally partial and focused on common static plotting flows such as `plot()`, `scatter()`, `bar()`, labels, titles, and `show()`.
- HTML/SVG output rendering is intentionally sandboxed and limited to notebook content, not arbitrary browsing.
- UI tests use an in-app import harness instead of automating the system Files picker directly.
