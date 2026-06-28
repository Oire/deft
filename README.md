# Deft

A native UI framework for the [D programming language](https://dlang.org). Deft wraps real native platform controls — so you get the platform's look, behavior, and **accessibility for free** — and adds a delegate-based event system and an automatic box-layout engine on top.

> **Status: pre-alpha (work in progress).** The core infrastructure is complete and tested: application lifecycle, a window/widget hierarchy, a delegate-based event system, an HBox/VBox layout engine, the Win32 backend, a control base class, a cross-thread command queue, and accessible-name support. Concrete controls (ListView, TreeView, text fields, …) and the non-Windows backends are not implemented yet — see [Roadmap](#roadmap).

## Why Deft

- **Native controls, native accessibility.** Standard Win32 common controls expose MSAA/IAccessible automatically, so screen readers such as JAWS and NVDA work without a custom accessibility layer.
- **Automatic layout.** Compose `HBox`/`VBox` sizers with per-child proportions and padding; the layout recalculates on resize.
- **A small, modern D API.** Delegate-based events (`button.onClicked ~= { ... };`), deterministic teardown (`dispose()`), and no Phobos dependency in the library itself.

## Platforms

| Platform | Backend | Status |
|----------|---------|--------|
| Windows  | Win32   | ✅ implemented |
| Linux    | GTK4    | ⏳ planned |
| macOS    | Cocoa   | ⏳ planned |

## Requirements

- A D compiler — **DMD 2.112+** or a recent **LDC**.
- **dub** (ships with the compiler).

On Windows the required Win32 bindings come from `core.sys.windows` in druntime — no extra packages.

## Installation

Add Deft to your project with dub:

```sh
dub add deft
```

or in `dub.json`:

```json
"dependencies": {
    "deft": "~>0.1.0-alpha"
}
```

While developing the two side by side, a path dependency works too (this is what `demo/` uses):

```json
"dependencies": {
    "deft": { "path": "../deft" }
}
```

## Quick start

```d
import deft;
import core.sys.windows.windows : BS_PUSHBUTTON, WS_TABSTOP, BN_CLICKED;

// A minimal button. (Concrete controls ship in a later plan; until then you
// build them over the Control base, which is a one-liner per control.)
final class Button : Control
{
    Event!() onClicked;

    this(Widget parent, string text)
    {
        super(parent, "BUTTON", BS_PUSHBUTTON | WS_TABSTOP);
        setText(text);
    }

    override bool processCommand(ushort code)
    {
        if (code == BN_CLICKED) { onClicked.fire(); return true; }
        return false;
    }

    override Size getPreferredSize() => Size(100, 30);
}

int main()
{
    auto app = Application.instance;
    app.initialize();                       // common controls, COM, DPI awareness

    auto window = new Window("Hello, Deft", 480, 320);

    auto button = new Button(window, "Close");
    button.onClicked ~= { app.quit(); };

    auto root = new VBox();
    root.add(button, 0, Padding.all(8));    // proportion 0 = keep preferred size
    window.setSizer(root);

    window.show();
    return app.run();                       // runs the message loop until quit
}
```

A fuller example — a label, two proportional panels (2:1), a Close button, and a custom accessible name — lives in [`demo/source/app.d`](demo/source/app.d).

## Building, testing, running

```sh
dub build                 # build the library (debug)
dub build -b release      # release build
dub test                  # run unit tests

cd demo && dub run        # build and launch the demo app
cd demo && dub run -b release   # smaller, optimized demo build
```

`dub test` exercises the parts with non-trivial logic: layout math (proportional sizing, nesting, padding), event registration/dispatch, UTF-8 ↔ UTF-16 conversion, and command-queue thread safety. UI behavior is verified manually via the demo (Win32 needs a running message loop).

## Architecture

The public surface is re-exported from the `deft` package, so `import deft;` is usually all you need.

| Module | Responsibility |
|--------|----------------|
| `deft.app` | `Application` singleton — process init (common controls, COM, DPI awareness) and the message loop. |
| `deft.window` | `Window` — top-level windows, `onClose`/`onResize`, default-button handling, root sizer. |
| `deft.widget` | `Widget` base class and the `Rect` / `Size` / `Padding` geometry types. |
| `deft.controls.control` | `Control` base for native common controls — text, font, `WM_COMMAND`/`WM_NOTIFY` routing, subclassing. |
| `deft.events` | `Event!(T...)` multicast delegates and event-argument types. |
| `deft.layout` | `Sizer` / `HBox` / `VBox` — proportional box layout. |
| `deft.commandqueue` | `CommandQueue!T` / `UiDispatcher!T` — thread-safe cross-thread UI messaging. |
| `deft.accessibility` | `setAccessibleName` — custom accessible names via MSAA Direct Annotation. |
| `deft.util.strings` | UTF-8 ↔ UTF-16 helpers for the wide Win32 API. |
| `deft.platform.win32.*` | Win32 backend: window-class registration and the master window procedure. |

**Handle lifetime.** A `Widget` owns its native `HWND`. Because D's GC is non-deterministic, call `dispose()` for prompt, predictable cleanup (it destroys the window, detaches from the parent, and unregisters the widget). While a widget's `HWND` is alive the widget is pinned as a GC root so it can't be collected out from under the message loop.

**Message dispatch.** One master `WndProc` looks up the `Widget` that owns the target `HWND` (via `GWLP_USERDATA`, with a registry fallback) and forwards to `Widget.processMessage`; per-widget message handling lives in the widget subclasses.

## Accessibility

Deft uses native controls, so MSAA/IAccessible accessibility — the API JAWS and NVDA use for classic Win32 controls — works out of the box: correct roles, names, and keyboard focus. On top of that the framework:

- enables **per-monitor DPI awareness**, so OS bitmap scaling on high-DPI displays doesn't misalign the screen-reader cursor;
- routes the message loop through the **dialog manager** (`IsDialogMessage`), so Tab / Shift+Tab / arrow keys move focus between controls;
- **forwards focus** to the first focusable child when a window is activated, so keyboard users land on a real control;
- answers `DM_GETDEFID` so **Enter activates the focused (or designated) button** natively — no key emulation;
- provides `setAccessibleName(widget, name)` for controls that lack a visible text label.

> Standalone static text (a decorative label not attached to a control) is intentionally **not** announced — that matches native Win32 behavior. A static is announced when it labels a control (created immediately before it in z-order) or when reached with the screen-reader cursor.

## Windows resources (manifest + version info)

A polished GUI app should embed an application manifest (ComCtl32 v6 themed controls + DPI awareness) and version information (read by screen readers and shown on the file's Details tab). The demo shows the recommended pattern:

- `demo/app.rc` declares both the manifest and a `VERSIONINFO` block, using numeric constants so `rc.exe` needs **no** SDK include path.
- `demo/make-res.ps1` (a dub `preGenerateCommands` step) locates `rc.exe` via `PATH` or the Windows SDK and compiles `app.rc` → `app.res`. The compiled `app.res` is committed too, so a fresh checkout builds even without the SDK.
- `demo/dub.json` links `app.res` via `sourceFiles-windows` and sets `/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup` — a windowed app (no console) that keeps an ordinary `int main()`.

The manifest is **not** required for MSAA accessibility (that works regardless) — only for theming and as an authoritative DPI declaration.

## Executable size

The library pulls in no Phobos (only druntime + the Win32 bindings), so a Deft executable is a plain statically-linked D GC app. The default `dub build` is a **debug** build (~1.6 MB) — almost entirely debug symbols. A release build is much smaller:

```sh
dub build -b release   # demo: ~540 KB
```

The Microsoft linker keeps debug info in a separate `.pdb`, so the release `.exe` is already symbol-free — nothing further to strip. For substantially smaller binaries, build with LDC (`--build=release -O -gc-sections`).

## API documentation

The source is documented with [DDoc](https://dlang.org/spec/ddoc.html), D's standard documentation system. Generate browsable HTML locally:

```sh
dub build -b ddoc      # writes HTML to api/
```

This uses a custom `ddoc` build type (defined in `dub.json`) that outputs to **`api/`** on purpose — dub's built-in `-b docs`/`-b ddox` write into `docs/`, which this project reserves for plans. Generated HTML is git-ignored and not committed. Once Deft is published to the [dub registry](https://code.dlang.org), API docs are also auto-hosted at `https://deft.dpldocs.info`.

## Roadmap

- **Plan 002 — controls & system services:** concrete controls (Button, Label, TextCtrl, ListView, TreeView, …), menus, accelerators, a tray icon, and related services. See [`docs/plans/`](docs/plans/).
- GTK4 (Linux) and Cocoa (macOS) backends.

Completed plans live in [`docs/plans/completed/`](docs/plans/completed/).

## Contributing

This is an early-stage open-source project. Conventions:

- American spelling throughout.
- Tabs for indentation (see `.editorconfig`).
- Keep the library free of Phobos imports in non-test code; unit-test blocks may use Phobos.
- Document public symbols with DDoc comments.
- `dub test` must pass before a change lands.

See [CLAUDE.md](CLAUDE.md) for a deeper tour of the codebase and its conventions.

## License

[Boost Software License 1.0](LICENSE) — the standard permissive license for D libraries.
