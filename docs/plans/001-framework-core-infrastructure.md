# Deft — Core Infrastructure

## Overview

Build the core infrastructure for a new D language UI framework that wraps native platform controls. This plan produces a standalone, reusable dub library package with: application lifecycle management, a window/widget class hierarchy, a delegate-based event system, a layout engine (HBox/VBox with proportions), and the Win32 backend implementation for all of the above.

The framework is a separate open-source project — no Notika-specific code lives here. Notika consumes it as a dub dependency.

After this plan, you can create a window with child widgets, arrange them with sizers, and handle events — but the individual control types (ListView, TreeView, etc.) come in plan 002.

## Context

- This is a brand-new project in its own repository
- Win32 backend is the first and only platform target; GTK4 (Linux) and Cocoa (macOS) backends come later
- D's `core.sys.windows` provides Win32 bindings in the standard library — no extra packages needed
- Fedra reference (architectural patterns): `C:\repos\fedra` — command channel, UI wake, event dispatch
- WinForms Notika (behavioral reference): `C:\repos\accessmind\notika-windows`
- Native Win32 common controls (SysListView32, SysTreeView32, Edit, Button, etc.) provide MSAA accessibility to JAWS/NVDA for free — no custom accessibility layer needed for standard controls

## Development Approach

- Complete each task fully before moving to the next
- Unit tests for layout engine math and event dispatch logic
- No UI tests (Win32 requires a running message loop) — manual verification with a demo app
- All tests must pass before starting the next task
- Update this plan file when scope changes during implementation
- Use American spelling throughout

## Testing Strategy

- **Unit tests**: layout calculations (proportional sizing, min sizes, nested sizers), event delegate registration/dispatch, UTF-8 ↔ UTF-16 conversion, command queue thread safety
- **No UI tests**: Win32 controls require a running message loop; test via demo app
- **Demo app**: a minimal `demo/` subdirectory with a main.d that creates a window with sizers and a few placeholder controls — proof that the framework works
- **Test location**: `source/deft/` with `unittest` blocks (D convention)

## Implementation Steps

### Task 1: Project setup and dub package

**Files:**
- Create: `dub.json`
- Create: `source/deft/package.d`
- Create: `source/deft/platform/package.d`
- Create: `source/deft/platform/win32/package.d`
- Create: `README.md`
- Create: `LICENSE`
- Create: `.gitignore`

- [ ] Create `dub.json` with: `name` = Deft, `targetType` = "library", `authors`, `license` = "BSL-1.0" (Boost, standard for D libs) or user's choice, `description` = "Native UI framework for D", `sourcePaths` = ["source"], `dflags-windows` for linking `user32.lib`, `comctl32.lib`, `shell32.lib`, `gdi32.lib`, `ole32.lib` (for COM/IAccessible). Use `"lflags-windows"` or `"libs-windows"` as appropriate for the linker
- [ ] Create `source/deft/package.d` as the root public import module — re-exports core types
- [ ] Create platform abstraction stubs: `platform/package.d` that uses `version(Windows)` to import `platform.win32`, with `static assert(0, "Unsupported platform")` fallback
- [ ] Create `.gitignore` for D projects (`.dub/`, `__*`, `*.o`, `*.obj`, `*.lib`, `*.exe`)
- [ ] Verify the project compiles with `dub build`

### Task 2: String conversion utilities

**Files:**
- Create: `source/deft/util/package.d`
- Create: `source/deft/util/strings.d`

- [ ] Implement `toWStringz(string s) -> const(wchar)*` — converts D UTF-8 string to null-terminated UTF-16 for Win32 APIs. Use `std.utf.toUTF16` then append null
- [ ] Implement `fromWStringz(const(wchar)* ws) -> string` — converts null-terminated UTF-16 back to D UTF-8 string. Scan for null, slice, use `std.utf.toUTF8`
- [ ] Implement `fromWString(const(wchar)[] ws) -> string` — converts a known-length UTF-16 slice to UTF-8
- [ ] Write unit tests: ASCII roundtrip, Cyrillic roundtrip, Hebrew roundtrip, CJK roundtrip, empty string, embedded nulls, lone surrogates (should not crash)

### Task 3: Event system with delegates

**Files:**
- Create: `source/deft/events.d`

- [ ] Define `Event(T...)` as a struct wrapping `void delegate(T...)[] listeners` — a multicast delegate list. Supports `opOpAssign!"~"` for `event ~= &handler` syntax, `fire(args)` to invoke all listeners, `disconnect(&handler)` to remove one
- [ ] Define common event signatures as aliases: `alias Action = void delegate()`, `alias SelectionEvent = void delegate(int index)`, `alias KeyEvent = void delegate(KeyEventArgs args)`, `alias MouseEvent = void delegate(MouseEventArgs args)`, `alias TextEvent = void delegate(string text)`
- [ ] Define `KeyEventArgs` struct: `uint keyCode`, `bool ctrl`, `bool shift`, `bool alt`, `bool handled` (set to true to suppress further processing)
- [ ] Define `MouseEventArgs` struct: `int x`, `int y`, `MouseButton button`
- [ ] Write unit tests: register handler, fire event, verify called; register multiple, verify all called; disconnect one, verify not called; fire with no handlers (no crash); fire with args, verify args received

### Task 4: Widget base class hierarchy

**Files:**
- Create: `source/deft/widget.d`
- Create: `source/deft/window.d`

- [ ] Define `Widget` as the abstract base class: `HWND handle` (Win32 window handle), `Widget parent`, `Widget[] children`, `bool visible`, `Rect bounds`. Methods: `show()`, `hide()`, `setVisible(bool)`, `setBounds(Rect)`, `getBounds() -> Rect`, `getClientRect() -> Rect`, `setEnabled(bool)`, `isEnabled() -> bool`, `setFocus()`, `invalidate()`, `dispose()` (deterministic cleanup: calls `DestroyWindow` on the HWND, removes from parent's children, removes from the HWND→Widget mapping). Protected: `HWND rawHandle() @property`. Handle lifetime model: the Widget owns its HWND. Call `dispose()` explicitly for deterministic cleanup (D's GC is non-deterministic). `dispose()` is idempotent — safe to call multiple times. Use `core.memory.GC.addRoot` on widgets to prevent premature GC collection while HWNDs are alive; `GC.removeRoot` in `dispose()`
- [ ] Define `Rect` struct: `int x, y, width, height`. Helper: `static Rect fromRECT(RECT r)`, `RECT toRECT()`
- [ ] Define `Size` struct: `int width, height`
- [ ] Define `Padding` struct: `int left, top, right, bottom`. Convenience: `Padding.all(int n)`, `Padding.symmetric(int h, int v)`
- [ ] Implement `Widget.addChild(Widget child)` — appends to children array, sets child.parent
- [ ] Implement `Widget.removeChild(Widget child)` — removes from array, nulls child.parent
- [ ] Define `CloseEventArgs` struct: `bool cancel = false` — passed to close event handlers; if any handler sets `cancel = true`, the window close is suppressed (needed for minimize-to-tray and confirm-exit flows)
- [ ] Define `Window` class extending `Widget`: represents a top-level window (WS_OVERLAPPEDWINDOW). Constructor takes title and size. Has `onClose` event (`Event!(CloseEventArgs*)`) and `onResize` event (`Event!(int, int)`). Sets `handle` via `CreateWindowExW`
- [ ] Implement `Window.show()` — calls `ShowWindow(handle, SW_SHOW)` + `UpdateWindow(handle)`
- [ ] Implement `Window.setTitle(string title)` — calls `SetWindowTextW`
- [ ] Implement `Window.close()` — sends `WM_CLOSE`

### Task 5: Win32 application lifecycle and message loop

**Files:**
- Create: `source/deft/app.d`
- Create: `source/deft/platform/win32/wndproc.d`
- Create: `source/deft/platform/win32/init.d`

- [ ] Implement `Application` class (singleton): `static Application instance()`, `int run()` (runs the Win32 message loop: `GetMessageW` / `TranslateMessage` / `DispatchMessageW`), `void quit(int exitCode = 0)` (posts `WM_QUIT`)
- [ ] Implement `Application.initialize()` — calls `InitCommonControlsEx` with `ICC_LISTVIEW_CLASSES | ICC_TREEVIEW_CLASSES | ICC_TAB_CLASSES | ICC_BAR_CLASSES` to enable all common controls, initializes COM with `CoInitializeEx(null, COINIT_APARTMENTTHREADED)` for accessibility/shell APIs
- [ ] Implement the master `WndProc` — a single `extern(Windows) LRESULT wndProc(HWND, UINT, WPARAM, LPARAM)` that looks up the `Widget` associated with the HWND (via a global `HWND -> Widget` associative array or `SetWindowLongPtrW` / `GetWindowLongPtrW` with `GWLP_USERDATA`), then dispatches messages to the widget's internal handlers
- [ ] Register a default window class ("FrameworkWindow") in `init.d` with the master WndProc, `CS_HREDRAW | CS_VREDRAW`, default cursor, and standard background brush
- [ ] Handle `WM_DESTROY` → call `PostQuitMessage(0)` only for the main window
- [ ] Handle `WM_CLOSE` → create `CloseEventArgs`, fire `Window.onClose(&args)`, if `args.cancel` is false call `DestroyWindow`, otherwise suppress the close
- [ ] Handle `WM_SIZE` → fire `Window.onResize(width, height)`, trigger layout recalculation
- [ ] Handle `WM_COMMAND` → route to menu/button/accelerator command handlers (by control ID)
- [ ] Handle `WM_NOTIFY` → route to common control notifications (by control ID + notification code)
- [ ] Store `HINSTANCE` from `GetModuleHandleW(null)` at initialization for window creation

### Task 6: Layout engine — HBox and VBox sizers

**Files:**
- Create: `source/deft/layout.d`

- [ ] Define `Sizer` abstract base class: `void layout(Rect availableArea)` (abstract), `Size preferredSize()` (abstract), `void add(Widget widget, int proportion = 0, Padding padding = Padding.init)`, `void addSizer(Sizer sizer, int proportion = 0, Padding padding = Padding.init)`. Internally stores `SizerItem[]` where `SizerItem` is a struct with `Widget widget` (nullable), `Sizer sizer` (nullable), `int proportion`, `Padding padding`, `Size minSize`
- [ ] Implement `HBox : Sizer` — lays out children horizontally. Algorithm: (1) subtract all padding and min-width items from available width, (2) distribute remaining width to proportional items by their proportion weight, (3) position each item left-to-right, (4) call `widget.setBounds()` or `sizer.layout()` for each child with its computed rect
- [ ] Implement `VBox : Sizer` — same algorithm but vertical (distribute height, stack top-to-bottom)
- [ ] Implement `preferredSize()` for both: sum of children's preferred sizes along main axis, max along cross axis, plus padding
- [ ] Wire layout into `Window`: `Window` holds an optional `Sizer rootSizer`. On `WM_SIZE`, call `rootSizer.layout(clientRect)`. Provide `Window.setSizer(Sizer s)`
- [ ] Write unit tests for layout math: single child fills available space; two children with equal proportion split evenly; 2:1 proportion ratio; fixed-size (proportion 0) + proportional; nested sizers (VBox inside HBox); padding applied correctly; zero available space doesn't crash; empty sizer returns Size(0,0)

### Task 7: Control base class and common behaviors

**Files:**
- Create: `source/deft/controls/package.d`
- Create: `source/deft/controls/control.d`

- [ ] Define `Control : Widget` — base class for all Win32 common controls. Constructor takes parent Widget, Win32 class name (e.g., "Button", "SysListView32"), style flags, extended style flags. Creates the HWND with `CreateWindowExW` as a child window (`WS_CHILD | WS_VISIBLE` + provided styles), parent = `parent.handle`
- [ ] Implement `Control.setText(string text)` — `SetWindowTextW`
- [ ] Implement `Control.getText() -> string` — `GetWindowTextW` + `GetWindowTextLengthW`
- [ ] Implement `Control.setFont(HFONT font)` — `WM_SETFONT`
- [ ] Implement `Control.getPreferredSize() -> Size` — returns a reasonable default (can be overridden per control type)
- [ ] Implement a `defaultFont()` utility function that creates or retrieves the system default GUI font (`GetStockObject(DEFAULT_GUI_FONT)`) — applied to all controls at creation
- [ ] Implement control-to-parent message routing: when `WM_COMMAND` or `WM_NOTIFY` arrives at the parent WndProc with a child control ID, look up the child Control by HWND and call its `processCommand` or `processNotify` virtual method
- [ ] Implement subclassing support: `Control.subclass()` installs a subclass WndProc via `SetWindowSubclass` (from `comctl32`) for controls that need to intercept their own messages (e.g., intercepting Enter key in a TextCtrl)

### Task 8: Command queue for cross-thread UI communication

**Files:**
- Create: `source/deft/commandqueue.d`

- [ ] Define `CommandQueue(T)` — a thread-safe generic queue. Internally a `T[]` protected by `core.sync.mutex.Mutex`. Methods: `void push(T item)` (lock, append, unlock), `T[] drainAll()` (lock, swap with empty array, unlock, return old array), `bool empty()` (lock, check length, unlock)
- [ ] Define `UiDispatcher(T)` struct: holds `CommandQueue!T queue`, `HWND targetHwnd`, `uint messageId`. Method `void post(T command)` — pushes to queue then calls `PostMessageW(targetHwnd, messageId, 0, 0)` to wake the UI thread. Method `T[] drain()` — calls `queue.drainAll()`
- [ ] The framework provides the generic mechanism. Notika defines its own `UiCommand` enum and creates a `UiDispatcher!UiCommand`. The WndProc handler for `messageId` calls `drain()` and processes commands
- [ ] Use `WM_APP + 1` as the default wake message ID (in the `WM_APP` through `0xBFFF` range reserved for application use)
- [ ] Write unit tests: push from multiple threads, drain returns all items in order; drain on empty returns empty array; push + drain roundtrip; concurrent push safety (spawn N threads, each push M items, verify total count after drain)

### Task 9: Accessibility — custom accessible names

**Files:**
- Create: `source/deft/accessibility.d`

- [ ] Implement `setAccessibleName(Widget widget, string name)` — for standard common controls, this sets the accessible name that screen readers announce. On Win32, use `IAccessible` COM interface: call `SetPropW(hwnd, "AccessibleName", ...)` or more robustly, implement a minimal `IAccessible` wrapper that overrides `get_accName` for the control's HWND
- [ ] Simpler approach first: use WM_GETOBJECT + a custom IAccessible proxy that delegates all methods to the default implementation (via `AccessibleObjectFromWindow`) except `get_accName` which returns the custom name. This is the Win32 equivalent of WinForms `Control.AccessibleName`
- [ ] Implement `IAccessibleProxy` class that implements `IAccessible` COM interface: stores a custom name string and a reference to the default `IAccessible`. All methods delegate to default except `get_accName(VARIANT, BSTR*)` which returns the custom name
- [ ] Handle `WM_GETOBJECT` with `OBJID_CLIENT` in the WndProc: if the widget has a custom accessible name, return `LresultFromObject` with the proxy; otherwise defer to `DefWindowProc`
- [ ] Document: for standard common controls (ListView, TreeView, Button, etc.), MSAA accessibility works automatically — screen readers can read items, navigate, etc. Custom accessible names are only needed for controls that lack a visible text label (e.g., a category panel that has no label, just a TreeView)

### Task 10: Demo application and verification

**Files:**
- Create: `demo/dub.json`
- Create: `demo/source/app.d`

- [ ] Create a demo dub project that depends on the framework via path dependency
- [ ] Demo creates a Window with title "Framework Demo" and size 800x600
- [ ] Add a VBox sizer to the window containing: a Label "Hello from Deft", an HBox with two placeholder panels (colored rectangles or static controls) at 2:1 proportion, a Button "Close" that calls `Application.quit()`
- [ ] Set an accessible name on one of the panels: "Left panel" — verify with NVDA/JAWS that it announces the name
- [ ] Wire the Close button's click event to quit
- [ ] Verify: `dub run` launches the demo, window appears, layout adjusts on resize, button click exits
- [ ] Run `dub test` — all unit tests pass (layout math, events, string conversion, command queue)
- [ ] Verify with a screen reader: window title announced, button label announced, accessible name on panel announced

## Technical Details

**Widget ↔ HWND mapping (via GWLP_USERDATA):**
```d
// On creation, associate the Widget with its HWND
SetWindowLongPtrW(hwnd, GWLP_USERDATA, cast(LONG_PTR)cast(void*)widget);

// In WndProc, retrieve the Widget
Widget widget = cast(Widget)cast(void*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
if (widget !is null) {
    return widget.processMessage(msg, wParam, lParam);
}
return DefWindowProcW(hwnd, msg, wParam, lParam);
```

**Event system usage:**
```d
// Define events on a widget
class Button : Control {
    Event!() onClicked;
}

// User code
auto btn = new Button(parent, "Click me");
btn.onClicked ~= { writeln("Button was clicked!"); };
btn.onClicked ~= { app.quit(); };  // multiple handlers
```

**Layout engine usage:**
```d
auto root = new VBox();
root.add(searchBox, 0, Padding.all(4));       // fixed height
root.add(noteList, 1, Padding.symmetric(4, 0)); // takes remaining space
root.add(statusBar, 0);                        // fixed height

window.setSizer(root);
```

**Command queue (WinForms-equivalent pattern):**
```d
// Define in app code (not framework)
enum UiCommand {
    NewNote,
    OpenNote,
    CategorySelected,
    // ...
}

// Setup
auto dispatcher = UiDispatcher!UiCommand(mainWindow.handle, WM_APP + 1);

// Background thread sends a command
dispatcher.post(UiCommand.NewNote);
// → pushes to queue, then PostMessageW(hwnd, WM_APP+1, 0, 0)

// Main window WndProc receives WM_APP+1
foreach (cmd; dispatcher.drain()) {
    handleCommand(cmd);
}
```

**String conversion:**
```d
import deft.util.strings;

// D string → Win32 wide string
auto title = "Notika — Notes";
SetWindowTextW(hwnd, title.toWStringz);

// Win32 wide string → D string
auto len = GetWindowTextLengthW(hwnd);
auto buf = new wchar[len + 1];
GetWindowTextW(hwnd, buf.ptr, cast(int)buf.length);
string text = buf[0 .. len].fromWString;
```

## Post-Completion

**Manual verification:**
- Demo app launches on Windows, shows correct layout
- Resizing the window adjusts sizer proportions correctly
- Button click fires event and quits the app
- Screen reader (JAWS/NVDA) announces: window title, button text, custom accessible name on panel
- `dub test` passes all unit tests
- Framework compiles as a standalone library with no Notika dependencies

**Repository setup:**
- Push to a new public GitHub repository
- Add a README with "work in progress" status and description
- Tag as v0.1.0-alpha after this plan completes
