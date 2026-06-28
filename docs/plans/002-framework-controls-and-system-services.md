# Deft — Controls and System Services

## Overview

Implement all 18 control types that Notika needs, plus the menu system, accelerator tables, and system-level services (tray icon, timer). Each control is a thin D class wrapping a native Win32 common control via `CreateWindowExW`, with delegate-based events and automatic MSAA accessibility.

After this plan, the framework provides every UI building block Notika requires. No Notika-specific code lives here — controls are generic and reusable.

## Context

- Depends on: Plan 001 (core infrastructure: Widget, Control, events, layout, WndProc)
- Win32 common controls reference: [Microsoft Learn — Common Controls](https://learn.microsoft.com/en-us/windows/win32/controls/common-controls-intro)
- WinForms Notika (control usage reference): `C:\repos\accessmind\notika-windows` — `src/Notika/Ui/MainWindow.Designer.cs`
- All controls inherit from `Control : Widget` (plan 001 Task 7)
- Native Win32 common controls provide MSAA accessibility for free — JAWS/NVDA can read ListView items, TreeView nodes, button labels, etc., without custom code

## Development Approach

- Complete each task fully before moving to the next
- No unit tests for individual controls (require running message loop)
- Unit tests for: menu builder logic, accelerator parsing, timer callback infrastructure
- Manual testing with the demo app (extend demo from plan 001)
- All tests must pass before starting the next task
- Update this plan file when scope changes during implementation
- Use American spelling throughout

## Testing Strategy

- **Unit tests**: accelerator key string parsing, menu item ID generation
- **Manual (demo app)**: extend the demo from plan 001 to exercise each control — verify visual appearance, event firing, and screen reader behavior
- **Accessibility**: verify with JAWS/NVDA that each control type is announced correctly (label, state, contents)

## Implementation Steps

### Task 1: Label and Button controls

**Files:**
- Create: `source/deft/controls/label.d`
- Create: `source/deft/controls/button.d`

- [ ] Implement `Label : Control` — wraps Win32 "Static" class (`SS_LEFT` style). Constructor: `this(Widget parent, string text)`. Read-only display of text. Override `getPreferredSize()` to calculate from text extent via `GetTextExtentPoint32W`
- [ ] Implement `Button : Control` — wraps Win32 "Button" class (`BS_PUSHBUTTON`). Constructor: `this(Widget parent, string text)`. Event: `Event!() onClicked`. Handle `WM_COMMAND` with `BN_CLICKED` notification to fire `onClicked`
- [ ] Implement `CheckBox : Control` — wraps "Button" class with `BS_AUTOCHECKBOX`. Additional: `bool isChecked()` (send `BM_GETCHECK`), `void setChecked(bool)` (send `BM_SETCHECK`). Event: `Event!() onToggled`
- [ ] Implement `RadioButton : Control` — wraps "Button" class with `BS_AUTORADIOBUTTON`. Same check API as CheckBox. Group behavior: first radio in a group gets `WS_GROUP` style
- [ ] Extend demo app: add a Label, a Button with click handler, a CheckBox, a RadioButton group — verify all display and fire events

### Task 2: TextCtrl (single-line and multiline)

**Files:**
- Create: `source/deft/controls/textbox.d`

- [ ] Implement `TextBox : Control` — wraps Win32 "Edit" class. Constructor: `this(Widget parent, string initialText = "", TextBoxStyle style = TextBoxStyle.singleLine)`. Enum `TextBoxStyle { singleLine, multiLine, singleLineReadOnly, multiLineReadOnly }`
- [ ] For single-line: style `ES_AUTOHSCROLL`. For multiline: style `ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL`. For read-only: add `ES_READONLY`
- [ ] Implement `getText() -> string` and `setText(string text)` — override from Control base
- [ ] Implement `setReadOnly(bool)` — send `EM_SETREADONLY`
- [ ] Implement `selectAll()` — send `EM_SETSEL(0, -1)`
- [ ] Implement `getSelectionRange() -> tuple(int, int)` — send `EM_GETSEL`
- [ ] Implement `appendText(string text)` — move caret to end, replace selection with text
- [ ] Events: `Event!(string) onTextChanged` (fired on `EN_CHANGE` via `WM_COMMAND`), `Event!(KeyEventArgs) onKeyDown` (via subclassing to intercept `WM_KEYDOWN` before the edit control processes it)
- [ ] For Enter key behavior (Submit vs Newline): the subclassed `WM_KEYDOWN` handler checks for VK_RETURN, fires `onKeyDown`; if `args.handled` is set, suppress the keystroke. Notika's code sets this based on config
- [ ] Extend demo: add single-line TextBox with onTextChanged printing to debug output, and a multiline Textbox

### Task 3: ListView (Report mode with columns)

**Files:**
- Create: `source/deft/controls/listview.d`

- [ ] Implement `ListView : Control` — wraps "SysListView32" with `LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS`. Constructor: `this(Widget parent)`
- [ ] Implement `addColumn(string title, int width, ColumnAlign align = ColumnAlign.left)` — `LVM_INSERTCOLUMNW` with `LVCOLUMNW`. Track column count internally
- [ ] Implement `setColumnWidth(int col, int width)` — `LVM_SETCOLUMNWIDTH`
- [ ] Implement `getColumnWidth(int col) -> int` — `LVM_GETCOLUMNWIDTH`
- [ ] Implement `addItem(string[] cells)` — `LVM_INSERTITEMW` for first cell, then `LVM_SETITEMTEXTW` for subsequent columns (subitems). Returns the item index
- [ ] Implement `clear()` — `LVM_DELETEALLITEMS`
- [ ] Implement `getItemCount() -> int` — `LVM_GETITEMCOUNT`
- [ ] Implement `getSelectedIndex() -> int` — `LVM_GETNEXTITEM` with `LVNI_SELECTED`, returns -1 if none
- [ ] Implement `setSelectedIndex(int index)` — `LVM_SETITEMSTATE` with `LVIS_SELECTED | LVIS_FOCUSED`
- [ ] Implement `ensureVisible(int index)` — `LVM_ENSUREVISIBLE`
- [ ] Implement `getItemText(int row, int col) -> string` — `LVM_GETITEMTEXTW`
- [ ] Implement `setItemData(int index, void* data)` and `getItemData(int index) -> void*` — `LVM_SETITEM` / `LVM_GETITEM` with `LVIF_PARAM` for associating arbitrary data (e.g., a note ID string pointer) with list items. Set lParam during `addItem` or separately
- [ ] Implement column reordering: `setColumnsOrder(int[] order)` — `LVM_SETCOLUMNORDERARRAY`, `getColumnsOrder() -> int[]` — `LVM_GETCOLUMNORDERARRAY`
- [ ] Events: `Event!(int) onSelectionChanged` (via `LVN_ITEMCHANGED` in `WM_NOTIFY` — fire only when selection actually changes, not on every state flag change), `Event!(int) onItemActivated` (via `LVN_ITEMACTIVATE` or `NM_DBLCLK` — Enter key or double-click), `Event!(int, MouseEventArgs) onContextMenu` (via `NM_RCLICK` or `WM_CONTEXTMENU`)
- [ ] Extend demo: add a ListView with 3 columns and sample data, wire selection and activation events

### Task 4: TreeView

**Files:**
- Create: `source/deft/controls/treeview.d`

- [ ] Implement `TreeView : Control` — wraps "SysTreeView32" with `TVS_HASLINES | TVS_LINESATROOT | TVS_HASBUTTONS | TVS_SHOWSELALWAYS`. Constructor: `this(Widget parent)`
- [ ] Define `TreeItem` struct: `HTREEITEM handle` (opaque handle to Win32 tree item), helpers for comparison and null check
- [ ] Implement `addRoot(string text) -> TreeItem` — `TVM_INSERTITEMW` with `TVI_ROOT` parent
- [ ] Implement `addChild(TreeItem parent, string text) -> TreeItem` — `TVM_INSERTITEMW` with parent handle
- [ ] Implement `clear()` — `TVM_DELETEITEM` with `TVI_ROOT`
- [ ] Implement `getSelectedItem() -> TreeItem` — `TVM_GETNEXTITEM` with `TVGN_CARET`
- [ ] Implement `setSelectedItem(TreeItem item)` — `TVM_SELECTITEM` with `TVGN_CARET`
- [ ] Implement `getItemText(TreeItem item) -> string` — `TVM_GETITEMW` with `TVIF_TEXT`
- [ ] Implement `setItemData(TreeItem item, void* data)` and `getItemData(TreeItem item) -> void*` — `TVIF_PARAM` for associating arbitrary data (e.g., category ID pointer) with tree nodes
- [ ] Implement `expandItem(TreeItem item)` — `TVM_EXPAND` with `TVE_EXPAND`
- [ ] Events: `Event!(TreeItem) onSelectionChanged` (via `TVN_SELCHANGEDW` in `WM_NOTIFY`), `Event!(TreeItem, MouseEventArgs) onContextMenu` (via `NM_RCLICK` or `WM_CONTEXTMENU`)
- [ ] Extend demo: add a TreeView with nested items, wire selection event

### Task 5: ListBox and ComboBox

**Files:**
- Create: `source/deft/controls/listbox.d`
- Create: `source/deft/controls/combobox.d`

- [ ] Implement `ListBox : Control` — wraps "ListBox" with `LBS_NOTIFY | WS_VSCROLL | WS_BORDER`. Constructor: `this(Widget parent)`
- [ ] Implement `addItem(string text)` — `LB_ADDSTRING`, `insertItem(int index, string text)` — `LB_INSERTSTRING`, `removeItem(int index)` — `LB_DELETESTRING`, `clear()` — `LB_RESETCONTENT`
- [ ] Implement `getSelectedIndex() -> int` — `LB_GETCURSEL`, `setSelectedIndex(int index)` — `LB_SETCURSEL`
- [ ] Implement `getItemText(int index) -> string` — `LB_GETTEXT` + `LB_GETTEXTLEN`
- [ ] Implement `getItemCount() -> int` — `LB_GETCOUNT`
- [ ] Implement `setItemData(int index, void* data)` — `LB_SETITEMDATA`, `getItemData(int index) -> void*` — `LB_GETITEMDATA`
- [ ] Events: `Event!(int) onSelectionChanged` (via `LBN_SELCHANGE` in `WM_COMMAND`), `Event!(int) onItemActivated` (via `LBN_DBLCLK`)
- [ ] Implement `ComboBox : Control` — wraps "ComboBox" with `CBS_DROPDOWNLIST | WS_VSCROLL` (read-only dropdown). Same add/remove/get API as ListBox but using `CB_*` messages
- [ ] Events: `Event!(int) onSelectionChanged` (via `CBN_SELCHANGE`)
- [ ] Extend demo: add a ListBox and a ComboBox with sample items

### Task 6: Notebook (Tab control)

**Files:**
- Create: `source/deft/controls/tabcontrol.d`

- [ ] Implement `TabControl : Control` — wraps "SysTabControl32". Constructor: `this(Widget parent)`
- [ ] Implement `addPage(string title, Widget pageContent) -> int` — inserts a tab via `TCM_INSERTITEMW`, stores the page Widget internally. Page widget is reparented to occupy the tabcontrol's display area (below the tab strip)
- [ ] Implement `getSelectedPage() -> int` — `TCM_GETCURSEL`
- [ ] Implement `setSelectedPage(int index)` — `TCM_SETCURSEL`, show/hide page widgets accordingly
- [ ] Handle `TCN_SELCHANGE` notification: hide old page widget, show new page widget, fire `Event!(int) onPageChanged`
- [ ] Implement `getDisplayRect() -> Rect` — `TCM_ADJUSTRECT` to get the content area below tabs, used for positioning page widgets
- [ ] On parent resize: reposition all page widgets to fill the display rect
- [ ] Extend demo: add a TabControl with two tab pages, each containing different controls

### Task 7: StatusBar

**Files:**
- Create: `source/deft/controls/statusbar.d`

- [ ] Implement `StatusBar : Control` — wraps "msctls_statusbar32" with `SBARS_SIZEGRIP`. Constructor: `this(Widget parent)`
- [ ] Implement `setText(string text)` — `SB_SETTEXTW` for the default single part
- [ ] Implement `setParts(int[] widths)` — `SB_SETPARTS` for multi-part status bar. -1 for last part means "fill remaining"
- [ ] Implement `setPartText(int part, string text)` — `SB_SETTEXTW` with part index
- [ ] StatusBar auto-positions at the bottom of the parent window (it handles its own layout via `WM_SIZE` → send `WM_SIZE` to the status bar HWND so it repositions). The layout engine must account for the status bar's height when calculating the sizer's available area
- [ ] Extend demo: add a StatusBar that shows "Ready" and updates on button clicks

### Task 8: Menu system (MenuBar, Menu, MenuItem)

**Files:**
- Create: `source/deft/menu.d`

- [ ] Implement `MenuItem` struct: `int id`, `string label`, `string accelerator` (e.g., "Ctrl+N"), `MenuItemKind kind` (Normal, Separator, Checkable), `bool checked`, `bool enabled`, `Event!() onClicked`. Construct via fluent builder pattern
- [ ] Implement `Menu` class: wraps `HMENU` from `CreatePopupMenu()`. Methods: `append(MenuItem item)`, `appendSeparator()`, `appendSubmenu(Menu submenu, string label)`. Each item registered with `AppendMenuW` or `InsertMenuItemW`
- [ ] Implement `MenuBar` class: wraps `HMENU` from `CreateMenu()`. Methods: `append(Menu menu, string label)`. Attach to window via `SetMenu(hwnd, hmenu)`
- [ ] Implement accelerator string parsing: `parseAccelerator("Ctrl+Shift+N") -> ACCEL` struct with `fVirt` flags and `key` code. Handle: Ctrl, Alt, Shift modifiers; letter keys (A-Z); function keys (F1-F12); special keys (Delete, Insert, Up, Down, etc.)
- [ ] Build an accelerator table from all MenuItems that have accelerators: `CreateAcceleratorTableW`. Install in the message loop via `TranslateAccelerator` (must be called before `TranslateMessage` in `Application.run()`)
- [ ] Route `WM_COMMAND` from menu items: match command ID to MenuItem, fire `onClicked`
- [ ] Implement `Menu.findItem(int id) -> MenuItem*` — for dynamic label updates
- [ ] Implement `setChecked(int id, bool)` — `CheckMenuItem`
- [ ] Implement `setEnabled(int id, bool)` — `EnableMenuItem`
- [ ] Implement `showPopupMenu(Menu menu, Widget parent, int x, int y)` — `TrackPopupMenu` at screen coordinates for context menus. If x, y are -1, -1, position at the focused item (keyboard-triggered context menu via Apps key / Shift+F10)
- [ ] Write unit tests for accelerator string parsing: "Ctrl+N", "Ctrl+Shift+N", "Alt+Shift+Up", "F1", "Shift+F1", "Ctrl+,", empty string, invalid string
- [ ] Extend demo: add a menu bar with File > Exit (Ctrl+Q) and Help > About, verify accelerator works

### Task 9: Timer and system tray

**Files:**
- Create: `source/deft/controls/timer.d`
- Create: `source/deft/controls/trayicon.d`

- [ ] Implement `Timer` class: wraps `SetTimer` / `KillTimer`. Constructor: `this(Widget owner)`. Methods: `start(int intervalMs, bool oneShot = false)` — calls `SetTimer(owner.handle, timerId, interval, null)`. `stop()` — calls `KillTimer`. Event: `Event!() onTick`. Handle `WM_TIMER` in the owner widget's WndProc, match timer ID, fire `onTick`. For one-shot: auto-call `stop()` after first tick
- [ ] Implement unique timer ID generation: use a `static uint nextTimerId` counter (incrementing). Do NOT use the Timer object pointer as ID — D's GC can relocate objects, invalidating the pointer. Maintain a `static Timer[uint]` mapping for dispatch
- [ ] Implement `TrayIcon` class: wraps `Shell_NotifyIconW` with `NOTIFYICONDATAW`. Constructor: `this(Window owner, string tooltip)`. Methods: `setIcon(HICON icon)`, `setTooltip(string text)`, `showBalloon(string title, string text)`, `setContextMenu(Menu menu)`, `destroy()`
- [ ] Handle tray icon messages: register a callback message ID (`WM_APP + 100` range). On `WM_LBUTTONDBLCLK` → fire `Event!() onDoubleClicked`. On `WM_RBUTTONUP` or `WM_CONTEXTMENU` → show context menu via `TrackPopupMenu` at cursor position (use `GetCursorPos`, and `SetForegroundWindow` before `TrackPopupMenu` to ensure menu dismisses correctly — this is a known Win32 quirk)
- [ ] Implement `TrayIcon.destroy()` — must be called before owner window destruction to avoid screen reader focus issues (same pattern as Fedra). Calls `Shell_NotifyIconW` with `NIM_DELETE`
- [ ] Implement default icon loading: `loadIcon(int resourceId) -> HICON` using `LoadIconW`, and `loadIconFromFile(string path) -> HICON` using `LoadImageW`
- [ ] Extend demo: add a tray icon with a context menu containing "Show" and "Exit" items

### Task 10: Dialog infrastructure

**Files:**
- Create: `source/deft/controls/dialog.d`
- Create: `source/deft/controls/messagebox.d`

- [ ] Implement `Dialog : Window` — a modal dialog window. Constructor: `this(Widget parent, string title, int width, int height)`. Differences from Window: created with `WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | DS_MODALFRAME` (no maximize/minimize), centered on parent
- [ ] Implement `showModal() -> DialogResult` — enters a modal message loop: disable parent window (`EnableWindow(parent.handle, FALSE)`), run a local `GetMessageW` / `DispatchMessageW` loop until `endModal()` is called, re-enable parent, return result
- [ ] Implement `endModal(DialogResult result)` — sets the result, posts `WM_CLOSE` to break out of the modal loop. Enum `DialogResult { ok, cancel, yes, no }`
- [ ] Implement standard button row helper: `addStandardButtons(ButtonSet set)` where `ButtonSet { okCancel, yesNo, ok }` — creates a right-aligned HBox at the bottom of the dialog with the appropriate buttons, wired to `endModal()` with the corresponding result. OK/Yes buttons get default style (`BS_DEFPUSHBUTTON`). Escape key triggers Cancel/No
- [ ] Handle Escape key: intercept `WM_KEYDOWN` with `VK_ESCAPE`, call `endModal(DialogResult.cancel)`
- [ ] Handle Enter key: if no control has consumed it, trigger the default button
- [ ] Implement `MessageBox` wrapper: `showMessageBox(Widget parent, string text, string title, MessageBoxStyle style) -> DialogResult`. Style enum: `{ info, warning, error, question }`. Maps to `MessageBoxW` with appropriate `MB_*` flags. Returns mapped `DialogResult`
- [ ] Implement `showInputDialog(Widget parent, string title, string prompt, string initialValue = "") -> string` — a convenience dialog with a Label, a TextCtrl, and OK/Cancel buttons. Returns the entered text or null on cancel. Uses the `Dialog` infrastructure
- [ ] Extend demo: add a menu item that opens a modal Dialog with OK/Cancel buttons

### Task 11: Comprehensive demo and verification

**Files:**
- Modify: `demo/source/app.d`

- [ ] Extend the demo app into a "widget gallery" that exercises every control type: Window, Label, Button, CheckBox, RadioButton, TextBox (single + multi), ListView (with 3 columns and 10 rows), TreeView (with nested nodes), ListBox, ComboBox, TabControl (2 tabs), StatusBar, MenuBar (File, Edit, Help menus), Timer (updates a label every second), TrayIcon (with context menu), Dialog (opened from menu), MessageBox (from menu)
- [ ] Wire cross-control interactions: selecting a ListView item updates the StatusBar text; clicking a Button opens a Dialog; TreeView selection changes a Label
- [ ] Run `dub build` — must succeed with no errors
- [ ] Run `dub test` — all unit tests pass
- [ ] Manual verification: launch demo, tab through all controls (verify logical tab order), resize window (verify layout adjusts), test keyboard accelerators, test context menus (right-click and Apps key), test tray icon
- [ ] Accessibility verification with JAWS/NVDA: all controls announced with correct type and label, ListView items readable with column headers, TreeView nodes expandable/navigable, CheckBox states announced, Dialog announced on open, StatusBar changes announced

## Technical Details

**ListView Report mode setup:**
```d
auto list = new ListView(parent);
list.addColumn("Title", 200);
list.addColumn("Updated", 120, ColumnAlign.left);
list.addColumn("Created", 120, ColumnAlign.left);

list.addItem(["My first note", "2026-05-01", "2026-04-15"]);
list.addItem(["Shopping list",  "2026-04-30", "2026-04-20"]);

list.onSelectionChanged ~= (int index) {
    statusBar.setText("Selected: " ~ list.getItemText(index, 0));
};

list.onItemActivated ~= (int index) {
    openNoteDialog(list.getItemText(index, 0));
};
```

**Menu construction with accelerators:**
```d
auto fileMenu = new Menu();
fileMenu.append(MenuItem(ID_NEW, "&New Note...", "Ctrl+N"));
fileMenu.append(MenuItem(ID_SAVE, "&Save", "Ctrl+S"));
fileMenu.appendSeparator();
fileMenu.append(MenuItem(ID_EXIT, "E&xit", "Ctrl+Q"));

auto viewMenu = new Menu();
viewMenu.append(MenuItem(ID_PREVIEW, "Show &Preview", "", MenuItemKind.checkable));

auto menuBar = new MenuBar();
menuBar.append(fileMenu, "&File");
menuBar.append(viewMenu, "&View");
window.setMenuBar(menuBar);
```

**Modal dialog pattern:**
```d
auto dlg = new Dialog(parent, "Edit Note", 640, 500);
auto sizer = new VBox();

auto titleLabel = new Label(dlg, "Title:");
auto titleInput = new TextBox(dlg);
auto contentLabel = new Label(dlg, "Content:");
auto contentInput = new TextBox(dlg, "", TextBoxStyle.multiLine);

sizer.add(titleLabel, 0, Padding.all(8));
sizer.add(titleInput, 0, Padding.symmetric(8, 0));
sizer.add(contentLabel, 0, Padding(8, 8, 8, 0));
sizer.add(contentInput, 1, Padding.all(8));

dlg.setSizer(sizer);
dlg.addStandardButtons(ButtonSet.okCancel);

if (dlg.showModal() == DialogResult.ok) {
    auto title = titleInput.getText();
    auto content = contentInput.getText();
    // save...
}
```

**Tray icon with context menu:**
```d
auto trayMenu = new Menu();
trayMenu.append(MenuItem(ID_TRAY_SHOW, "&Show Notika"));
trayMenu.appendSeparator();
trayMenu.append(MenuItem(ID_TRAY_EXIT, "E&xit"));

auto tray = new TrayIcon(window, "Notika");
tray.setIcon(appIcon);
tray.setContextMenu(trayMenu);

tray.onDoubleClicked ~= {
    window.show();
    window.setForeground();
};

// CRITICAL: destroy tray BEFORE window on close
window.onClose ~= {
    tray.destroy();
};
```

**Timer for debounce:**
```d
auto debounceTimer = new Timer(window);
debounceTimer.onTick ~= {
    auto query = searchBox.getText();
    dispatcher.post(UiCommand.SearchChanged(query));
};

searchBox.onTextChanged ~= (string _) {
    debounceTimer.stop();
    debounceTimer.start(300, true);  // one-shot, 300ms
};
```

## Post-Completion

**Manual verification:**
- Widget gallery demo runs, all 18 control types functional
- Tab order is logical through all controls
- Keyboard accelerators work (menu shortcuts, Enter/Escape in dialogs)
- Context menus appear on right-click AND on Apps key / Shift+F10
- Tray icon shows, context menu works, double-click toggles window
- Timer fires correctly (one-shot and repeating)
- JAWS/NVDA reads all controls correctly: types, labels, states, list items, tree nodes

**Performance baseline:**
- ListView handles 1000+ items without visible lag (virtual mode not needed for Phase 1, but document as future optimization)
- Window resize with nested sizers responds within 16ms (no visible flicker)
