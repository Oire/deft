# Deft

A native UI framework for the [D programming language](https://dlang.org), wrapping native platform controls and providing automatic layout.

> **Status: work in progress (pre-alpha).** The core infrastructure is in place — application lifecycle, a window/widget hierarchy, a delegate-based event system, an HBox/VBox layout engine, the Win32 backend, a control base class, a cross-thread command queue, and accessible-name support. Concrete controls (ListView, TreeView, text fields, …) and the non-Windows backends are not implemented yet.

## Platforms

- **Windows** (Win32) — the current and only backend.
- GTK4 (Linux) and Cocoa (macOS) are planned.

## Requirements

- A D compiler (DMD 2.112+ or a recent LDC).
- `dub`.

On Windows, `core.sys.windows` ships the needed Win32 bindings in druntime — no extra packages.

## Building and testing

```sh
dub build      # build the library
dub test       # run unit tests (layout math, events, string conversion, command queue)
```

## Demo

```sh
cd demo
dub run        # opens an 800x600 window with a label, two panels (2:1) and a Close button
```

The demo also sets a custom accessible name ("Left panel") on the left panel, announced by screen readers such as JAWS and NVDA.

## Accessibility

Deft uses native controls, so MSAA/IAccessible accessibility (the API JAWS and NVDA use for classic Win32 controls) works out of the box: correct roles, names and keyboard focus. The framework also:

- enables per-monitor DPI awareness (so the screen-reader cursor isn't thrown off by OS bitmap scaling on high-DPI displays);
- routes the message loop through the dialog manager (`IsDialogMessage`) so Tab / Shift+Tab / arrow keys move focus between controls;
- forwards focus to the first focusable child when a window is activated, so keyboard users land on a real control.

## Windows resources (manifest + version info)

A GUI app should embed an application manifest (ComCtl32 v6 themed controls + DPI awareness) and version information (read by screen readers and shown on the file's Details tab). The demo shows the pattern:

- `demo/app.rc` declares both the manifest and a `VERSIONINFO` block, using numeric constants so `rc.exe` needs **no** SDK include path.
- `demo/make-res.ps1` (a dub `preGenerateCommands` step) locates `rc.exe` via PATH or the Windows SDK and compiles `app.rc` → `app.res`. The compiled `app.res` is also committed, so a checkout builds even without the SDK installed.
- `demo/dub.json` links `app.res` via `sourceFiles-windows` and sets `/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup` so the app is windowed (no console) while keeping an ordinary `int main()`.

The manifest is **not** required for MSAA accessibility (that works regardless) — only for theming and as an authoritative DPI declaration.

## Executable size

The library itself pulls in no Phobos (it uses druntime and the Win32 bindings only), so a Deft executable is a plain statically-linked D GC app. The default `dub build` is a *debug* build (~1.6 MB) — that size is almost entirely debug symbols. A release build is much smaller:

```sh
dub build -b release   # demo: ~540 KB
```

The Microsoft linker keeps debug info in a separate `.pdb`, so the release `.exe` is already symbol-free — there is nothing further to strip. For substantially smaller binaries, build with LDC (`--build=release -O -gc-sections`).

## License

[Boost Software License 1.0](LICENSE).
