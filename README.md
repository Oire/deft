# Deft

A native UI framework for the [D programming language](https://dlang.org). Deft wraps real native platform controls — so you get the platform's look, behavior, and **accessibility for free** — and adds a delegate-based event system and automatic box and table layout on top.

> **Status: pre-alpha (work in progress).** The Win32 implementation is feature-complete enough to build real apps: application lifecycle, a window/widget hierarchy, a delegate-based event system, box (`HBox`/`VBox`) and table (`Grid`) layout, and a full set of native controls — labels, buttons/check boxes/radio buttons, single- and multi-line text fields, list/tree/list-box/combo/checked-list views, a tab control, a status bar, menus with keyboard accelerators, a system-tray icon, a timer, and native modal dialogs and message boxes — all with native accessibility. The non-Windows backends (GTK4, Cocoa) are not implemented yet — see [Roadmap](#roadmap).

## Why Deft

- **Native controls, native accessibility.** Standard Win32 common controls expose MSAA/IAccessible automatically, so screen readers such as JAWS and NVDA work without a custom accessibility layer. Dialogs are real dialog-class windows; list and tree context menus open from the keyboard (Apps key / Shift+F10); radio groups are a single tab stop navigated by arrow keys.
- **Automatic layout.** Compose `HBox`/`VBox` sizers or a `Grid` table layout (auto/pixel/percent tracks, like WinForms' `TableLayoutPanel`); place each child with a fluent handle — `add(w).stretch().pad(...).alignH(HAlign.center)` — and the layout recalculates on resize.
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

> **Not yet published to the [dub registry](https://code.dlang.org).** Until the
> first registry release, use a path or git dependency (see below); `dub add deft`
> and the version-range form will work once it's published.

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

int main()
{
    auto app = Application.instance;
    app.initialize();                       // common controls, COM, DPI awareness

    auto window = new Window("Hello, Deft", 480, 320);

    auto label = new Label(window, "What's your name?");
    auto input = new TextBox(window);
    auto greet = new Button(window, "Greet");

    greet.onClicked ~= {
        showMessageBox(window, "Hello, " ~ input.getText() ~ "!",
            "Greeting", MessageBoxStyle.info);
    };

    // Box layout — each child placed with a fluent handle. proportion 0 (the
    // default) keeps the preferred size; alignH centers the button in its column.
    auto root = new VBox();
    root.add(label).pad(Padding.all(8));
    root.add(input).pad(Padding.symmetric(8, 0));
    root.add(greet).pad(Padding.all(8)).alignH(HAlign.center);
    window.setSizer(root);

    window.show();
    return app.run();                       // runs the message loop until quit
}
```

For a label/field form, reach for `Grid` instead — an auto-sized label column and a stretching field column:

```d
auto grid = new Grid(2, 2);
grid.setColumn(0, GridTrack.autoSize);
grid.setColumn(1, GridTrack.percent(100));
grid.setRow(1, GridTrack.percent(100));     // the content row stretches
grid.add(new Label(dlg, "Title:"),   0, 0).aligned(HAlign.right, VAlign.middle);
grid.add(titleInput,                 1, 0);
grid.add(new Label(dlg, "Content:"), 0, 1).aligned(HAlign.right, VAlign.top);
grid.add(contentInput,               1, 1);  // fills its cell
dlg.setSizer(grid);
```

A fuller example — a widget gallery that exercises every control type (menus, tabs, lists, a tree, a status bar, a tray icon, a timer, and a native modal dialog) — lives in [`demo/source/app.d`](demo/source/app.d).

## Layout guide

Deft's sizers never ask you for a coordinate. You describe each child's *intent* and the integer layout math (in `deft.layout`) does the rest, recomputing on every resize. This is what makes layouts easy to get right **without inspecting them visually** — a correct description is a correct layout at every window size. The advice below is written with that goal in mind.

### Boxes or `Grid`? The deciding question is cross-row alignment

- **Nested `HBox`/`VBox` lay out independently.** A child's size in one box has no effect on a child in a sibling box. This is what you want *most* of the time: page structure, toolbars, a button row, a list that fills with buttons pinned below.
- **`Grid` exists for the one thing boxes structurally cannot do: align cells across rows and columns.** Every cell in a grid column shares that column's width.

A form is the case that *needs* the shared column. Build a form from one `HBox` per row and each row measures its own label independently, so the field edges stagger by a few pixels per row — a ragged left edge you'd have to fix by hand-matching every label's width. A `Grid` with an `autoSize` label column measures the longest label across **all** rows and gives every field the same start, automatically.

> **Rule of thumb:** reach for a box first; escalate to `Grid` the moment you'd otherwise be hand-matching sizes across rows or columns. Forms trip that wire immediately; almost nothing else does.

### How box layout divides space

A box lays its children out along its main axis (`HBox` = horizontal, `VBox` = vertical) in two passes:

1. Every **fixed** child takes its own preferred size — measured by the control (`getPreferredSize()`): a button sizes to its text, a label to its caption. These are added up.
2. Whatever space is **left over** is divided among the **stretching** children in proportion to their weights.

That's the entire model. A single integer — the child's *proportion* — encodes both passes: `0` means "no share of the leftover, just use my preferred size" (fixed), and any weight `n ≥ 1` means "give me a share of the leftover, sized by `n`." Two weight-`1` children split the slack evenly; weights `2` and `1` split it 2:1. **Only the ratios matter** — `1 : 2` and `50 : 100` are the same split — so whole numbers express every possibility and there are no fractional weights. This is the classic box-sizer model (wxWidgets, CSS `flex-grow`, GTK).

### Describe intent, not geometry

Per child you state one of two intents, so you never type a coordinate. The readable aliases say it at the call site:

- **`add(w).fixed()`** → "take your natural size" (alias for `proportion(0)`, the default). Use for buttons, labels, anything that shouldn't stretch.
- **`add(w).stretch()`** → "grow to fill the leftover space" (alias for `proportion(1)`). Pass a weight to share unevenly: `stretch(2)` versus `stretch(1)` splits 2:1.

`proportion(n)` remains available if you prefer the raw weight, but `fixed()`/`stretch()` read better — and avoid the easy-to-invert "what does proportion 0 mean again?" trap.

In a `Grid`, the column/row analog is `GridTrack.autoSize` (fit content, like `fixed`), `GridTrack.percent(w)` (a weighted share of the leftover, like `stretch`), and `GridTrack.pixels(n)` (a fixed pixel size).

A few practices follow from this:

- **One stretchy child per box.** Make natural-size children `fixed()` and let *one* region `stretch()`. If you can state "which one thing grows," the window is correct at any size with nothing left to eyeball.
- **Prefer `autoSize`/`percent` over `pixels` and `fixedSize`.** The fixed-pixel forms reintroduce magic numbers you can't sanity-check by feel. Reserve them for things with an inherently fixed size (an icon, a fixed-width sidebar); default to letting content or slack decide.
- **Set spacing once, as a constant.** Pick one gap (e.g. 8) and reuse it via `setSpacing` / `Padding.all` for consistent, structural breathing room.
- **Add children in reading order.** A sizer never reorders its children, so the order you call `add()` is the order Tab visits and a screen reader reads. Building each box in reading order makes "correct layout" and "correct tab order" the same act.

### Verify layout without seeing it

The layout math runs headless — no window, no message loop — so you can assert exact bounds in a `unittest` instead of inspecting a window. This is how `deft.layout`'s own tests work (a `FakeWidget` records the `Rect` it's given):

```d
unittest
{
    auto list = new FakeWidget(Size(0, 0));
    auto buttons = new FakeWidget(Size(200, 30));
    auto root = new VBox();
    root.add(list).stretch();              // fills the remaining height
    root.add(buttons).fixed();             // natural 30px, pinned below
    root.layout(Rect(0, 0, 400, 300));
    assert(buttons.bounds == Rect(0, 270, 400, 30));
    assert(list.bounds == Rect(0, 0, 400, 270));
}
```

Encode "buttons are 30px tall at the bottom, the list fills the rest" and `dub test` proves it for whatever window sizes you assert. For the *running* app, accessible names, roles, and focusability can be checked programmatically through the MSAA/UIA layer (see [CLAUDE.md](CLAUDE.md)).

## Building, testing, running

```sh
dub build                 # build the library (debug)
dub build -b release      # release build
dub test                  # run unit tests

cd demo && dub run        # build and launch the demo app
cd demo && dub run -b release   # smaller, optimized demo build
```

`dub test` exercises the parts with non-trivial logic: layout math (box proportions, grid auto/percent tracks, spanning, per-cell alignment, nesting, padding), accelerator-string parsing and menu-id generation, event registration/dispatch, UTF-8 ↔ UTF-16 conversion, and command-queue thread safety. UI behavior is verified manually via the demo (Win32 needs a running message loop).

## Architecture

The public surface is re-exported from the `deft` package, so `import deft;` is usually all you need.

| Module | Responsibility |
|--------|----------------|
| `deft.app` | `Application` singleton — process init (common controls, COM, DPI awareness) and the message loop (with accelerator translation). |
| `deft.window` | `Window` — top-level windows, `onClose`/`onResize`, default-button handling, icon (`setIcon`) and minimum-size, root sizer, menu/status-bar/timer/tray wiring. |
| `deft.widget` | `Widget` base class and the `Rect` / `Size` / `Padding` geometry types. |
| `deft.events` | `Event!(T...)` multicast delegates and event-argument types. |
| `deft.layout` | `Sizer` / `HBox` / `VBox` box layout and `Grid` table layout, with a fluent placement API (`SizerItem`/`GridItem`) and per-cell `HAlign`/`VAlign` alignment. |
| `deft.menu` | `MenuBar` / `Menu` / `MenuItem`, plus accelerator-string parsing and accelerator tables. |
| `deft.controls.control` | `Control` base for native common controls — text, font, `WM_COMMAND`/`WM_NOTIFY` routing, subclassing. |
| `deft.controls.*` | The control library: `Label`, `Button` / `CheckBox` / `RadioButton`, `TextBox`, `ListView`, `TreeView`, `ListBox`, `ComboBox`, `CheckListBox`, `TabControl`, `StatusBar`, `Timer`, `TrayIcon`, `Dialog` / `showMessageBox` / `showInputDialog`, and the `Panel` container. |
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
- makes **`Dialog` a real dialog-class (`#32770`) window**, so screen readers announce it as a dialog and read its children, and the dialog manager handles Esc → Cancel and Enter → default button;
- opens **context menus from the keyboard** (Apps key / Shift+F10) as well as the mouse, on `ListView` and `TreeView`, anchored at the selected item;
- groups **radio buttons into a single tab stop** navigated with the arrow keys (each control starts its own `WS_GROUP`);
- keeps **multi-line text boxes from trapping Tab** (Tab moves focus; Ctrl+Tab inserts a tab character);
- **selects the first item on focus** for list/tree/combo controls, so a screen reader has something to announce when the user tabs in;
- provides `setAccessibleName(widget, name)` for controls that lack a visible text label.

> Standalone static text (a decorative label not attached to a control) is intentionally **not** announced — that matches native Win32 behavior. A static is announced when it labels a control (created immediately before it in z-order) or when reached with the screen-reader cursor.

For a full checklist that maps each accessibility behavior to its location in the source, see [ACCESSIBILITY.md](ACCESSIBILITY.md).

## Windows resources (manifest + version info)

A polished GUI app should embed an application manifest (ComCtl32 v6 themed controls + DPI awareness) and version information (read by screen readers and shown on the file's Details tab). The demo shows the recommended pattern:

- `demo/app.rc` declares the manifest, a `VERSIONINFO` block, and an application **icon** (`1 ICON "deft.ico"`), using numeric constants so `rc.exe` needs **no** SDK include path. Deft's window class picks up icon resource id 1 automatically (so the window, taskbar and Alt+Tab all show it); `Window.setIcon` can override it per window.
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

Done so far (see [`docs/plans/completed/`](docs/plans/completed/)):

- **Plan 001 — core infrastructure:** application lifecycle, widget/window hierarchy, events, box layout, the Win32 backend, the control base, the command queue, and accessible-name support.
- **Plan 002 — controls & system services:** the full native control set, menus and keyboard accelerators, a system-tray icon, a timer, native dialogs and message boxes, the `Panel` container, and the `Grid` table layout.

Next:

- GTK4 (Linux) and Cocoa (macOS) backends.
- Richer layout (per-cell alignment is in; cell/control alignment options may grow), and additional controls as consumers need them.

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
