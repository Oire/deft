# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## What this is

**Deft** is a native UI framework for the D language. It wraps real native platform controls (Win32 today; GTK4/Cocoa planned) and adds a delegate-based event system and an HBox/VBox layout engine. The whole point of wrapping native controls is that they bring **native accessibility** (MSAA/IAccessible) for free — accessibility is a first-class concern here, not an afterthought.

The framework is standalone and open-source. It is consumed by other projects (e.g. Notika) as a dub dependency; **no consumer-specific code lives here.**

## Layout

```
source/deft/
  package.d              public re-exports (import deft; gets everything)
  app.d                  Application: init + message loop
  window.d               Window: top-level windows, default-button, sizer wiring
  widget.d               Widget base + Rect/Size/Padding
  events.d               Event!(T...) multicast delegates + arg structs
  layout.d               Sizer / HBox / VBox
  commandqueue.d         CommandQueue!T / UiDispatcher!T (cross-thread)
  accessibility.d        setAccessibleName (MSAA Direct Annotation)
  controls/control.d     Control base for native common controls
  util/strings.d         UTF-8 <-> UTF-16 (Win32 MultiByte/WideChar APIs)
  platform/win32/        init.d (window class), wndproc.d (master WndProc + registry)
demo/                    demo app + Windows resource pipeline (manifest, version info)
docs/plans/              implementation plans; completed/ holds finished ones
```

## Commands

```sh
dub build                 # build library (debug)
dub build -b release      # release build (~540 KB demo; debug is ~1.6 MB of symbols)
dub test                  # unit tests — MUST pass before a change lands
cd demo && dub run        # build + launch the demo
```

Environment here: DMD 2.112 / dub 1.41 on Windows (x86_64). DMD uses the Microsoft linker; debug info goes to a side `.pdb`, so release exes are already symbol-free.

## Conventions

- **American spelling** throughout.
- **Tabs** for indentation (see `.editorconfig`).
- **No Phobos in non-test code.** The library links druntime + Win32 only, which keeps consumer binaries small. `import std.*` is allowed *inside* `unittest` blocks only. String conversion uses Win32 `MultiByteToWideChar`/`WideCharToMultiByte`, not `std.utf`.
- **DDoc comments** on public symbols (`///` or `/** */`).
- Prefer per-widget message handling (`Widget.processMessage` overrides) over branching in the raw `WndProc`.

### Shell convention (enforced by a hook)

Never redirect to a null device (`/dev/null`, `>nul`, `nul`). A pre-tool hook blocks it. Redirect to a real file or drop the redirection. PowerShell's `$null` variable is fine; the null *device* is not.

### Git

- Commit/push only when asked. If on `master`, branch first.
- End commit messages with the `Co-Authored-By` trailer.

## Win32 / accessibility gotchas (learned the hard way)

- **`extern(Windows)` callbacks must be `nothrow`** and wrap their body in `try { ... } catch (Throwable) {}` — never let a D throwable escape into the OS dispatcher.
- **Widget lifetime:** a widget owns its `HWND`; it's pinned with `GC.addRoot` while alive and released in `dispose()`. `dispose()` is idempotent and destroys children first.
- **Keyboard navigation** requires the message loop to call `IsDialogMessageW(GetActiveWindow(), &msg)` before dispatch, and the top-level window to have `WS_EX_CONTROLPARENT`. Without it, child controls are unreachable by keyboard.
- **Enter on buttons:** a plain window has no default button, so `Window` answers `DM_GETDEFID` (focused push button = its own default; otherwise `setDefaultButton`). This is native — do **not** emulate keystrokes.
- **DPI:** `Application.initialize` sets per-monitor DPI awareness (dynamically resolved, with a manifest also declaring it in the demo). A DPI-unaware app is bitmap-scaled and screen-reader cursors land in the wrong place.
- **Accessible names:** use MSAA Direct Annotation (`IAccPropServices::SetHwndPropStr`), not a hand-rolled `IAccessible` proxy. `IAccPropServices` isn't in druntime, so a minimal binding lives in `accessibility.d`.
- **Static labels** are only announced when they label an adjacent control or are reached with the screen-reader cursor — standalone statics being silent is expected, not a bug.

### Verifying accessibility without a screen reader

You can't drive JAWS from a tool call, but you can inspect what it would read:

- **UIA tree** (PowerShell): `Add-Type -AssemblyName UIAutomationClient`, find the window by name, walk descendants for `ControlType` / `Name` / `IsKeyboardFocusable`.
- **MSAA layer** (what JAWS uses for classic controls): P/Invoke `AccessibleObjectFromWindow` + `get_accRole`/`get_accName`/`get_accState`. This is the authoritative check.
- Note: UIA may show native child controls as generic `Pane` even when MSAA is correct — that's a UIA-bridge quirk for child controls in a custom window class and does not affect MSAA screen readers.

## Demo resource pipeline (manifest + version info)

`demo/app.rc` (manifest + `VERSIONINFO`, numeric constants so no SDK headers are needed) is compiled to `demo/app.res` by `demo/make-res.ps1` (a dub `preGenerateCommands` step that locates `rc.exe` and cleans up its temp files). `app.res` is committed as a no-SDK fallback. The exe links it via `sourceFiles-windows` and uses `/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup` for a console-free windowed app.

## Plans workflow

Implementation plans live in `docs/plans/NNN-*.md` with checkbox task lists. When a plan is finished, check its boxes and `mv` it into `docs/plans/completed/`. Record notable deviations from a plan in an "Implementation Notes" section in that plan file.

**Important:** `docs/` is reserved for plans. Do **not** generate API docs into it. Use `dub build -b ddoc` (a custom build type) which writes DDoc HTML to `api/` (git-ignored). Avoid dub's built-in `-b docs`/`-b ddox` — they dump HTML into `docs/`.
