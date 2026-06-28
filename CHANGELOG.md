# Changelog

All notable changes to Deft are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Controls and system services (plan 002), plus a review pass focused on
keyboard/screen-reader use. Win32 only.

### Added

- **Controls**: `Label`; `Button`, `CheckBox`, `RadioButton`; `TextBox`
  (single/multi-line, read-only, `onTextChanged`/`onKeyDown`); `ListView` (report
  mode — columns, item data, selection/activation events); `TreeView`; `ListBox`
  (`single`/`multiple`/`extended` selection); `ComboBox` (`dropDownList`, editable
  `dropDown`, `simple`); `CheckListBox`; `TabControl`; `StatusBar`.
- **`Panel`** — a sizer-arranged container that, unlike a bare static control,
  forwards its children's `WM_COMMAND`/`WM_NOTIFY` notifications.
- **Menus & accelerators** (`deft.menu`): `MenuBar`, `Menu`, `MenuItem`,
  `showPopupMenu`, accelerator-string parsing (`parseAccelerator`) and tables wired
  into the message loop via `TranslateAccelerator`.
- **System services**: `Timer` (repeating and one-shot); `TrayIcon` (notification
  area icon with tooltip, context menu, balloon, and `onDoubleClicked`).
- **Dialogs**: a native modal `Dialog` (a real `#32770` dialog-class window built
  with `CreateDialogIndirectParamW`), `showMessageBox`, and `showInputDialog`.
- **`Grid` table layout** (à la WinForms `TableLayoutPanel`): `autoSize` / `pixels`
  / `percent` column and row tracks, inter-cell spacing, and column/row spanning.
- **Per-cell alignment** for all sizers via `HAlign { fill, left, center, right }`
  and `VAlign { fill, top, middle, bottom }` — the cross axis no longer always
  stretches.
- **Keyboard-accessible context menus** on `ListView`/`TreeView` (mouse right-click
  and the Apps key / Shift+F10), anchored at the selected item.
- **First-item auto-selection on focus** for `ListView`, `TreeView`, `ListBox`,
  the drop-down-list `ComboBox`, and `CheckListBox`.
- **Demo** expanded into a widget gallery exercising every control type.

### Changed

- **Fluent sizer placement.** `Sizer.add`/`addSizer` now take only the child and
  return a `SizerItem` configured with `.proportion()`, `.pad()`, `.alignH()`,
  `.alignV()`; `Grid.add` returns a `GridItem` adding `.span()` and `.aligned()`.
  **Breaking:** the positional `add(widget, proportion, padding)` overload was
  removed — `add(w).proportion(1).pad(...)` is now the one form.
- **`Dialog` is a genuine native dialog** (previously a styled `Window`), so screen
  readers announce it as a dialog and read its children, and Esc/Enter/Tab are
  handled by the dialog manager.
- **Radio groups are a single tab stop.** Every control now starts its own
  `WS_GROUP`; a non-first `RadioButton` joins the previous one's group, so a group is
  one tab stop navigated with the arrow keys.
- **Multi-line `TextBox` no longer traps Tab** — Tab moves focus, Ctrl+Tab inserts a
  literal tab.

## [0.1.0-alpha] — 2026-06-28

First milestone: the core framework infrastructure (plan 001). Win32 only.

### Added

- **Application lifecycle** (`Application`): singleton, message loop, `quit`, and
  process initialization (common controls, COM, per-monitor DPI awareness).
- **Widget hierarchy** (`Widget`, `Window`): visibility, bounds, enablement,
  focus, deterministic `dispose()` with GC-root pinning; cancellable `onClose`
  and `onResize` events.
- **Geometry types**: `Rect`, `Size`, `Padding`.
- **Event system** (`Event!(T...)`): multicast delegates with `~=`, `fire`,
  `disconnect`; `KeyEventArgs`, `MouseEventArgs`, `CloseEventArgs`, and handler
  aliases (`Action`, `SelectionEvent`, `KeyEvent`, `MouseEvent`, `TextEvent`).
- **Layout engine** (`Sizer`, `HBox`, `VBox`): proportional box layout with
  per-child padding and nesting; wired into `Window.setSizer`.
- **Control base** (`Control`): create native common controls, text/font,
  `WM_COMMAND`/`WM_NOTIFY` routing to the originating control, and opt-in
  subclassing.
- **Cross-thread messaging** (`CommandQueue!T`, `UiDispatcher!T`): thread-safe
  queue plus a UI-thread wake mechanism.
- **Accessibility** (`setAccessibleName`): custom accessible names via MSAA
  Direct Annotation (`IAccPropServices`).
- **String utilities** (`toWStringz`, `fromWStringz`, `fromWString`): UTF-8 ↔
  UTF-16 via the Win32 conversion APIs (no Phobos).
- **Win32 backend**: default window-class registration and a single master
  window procedure with an HWND→Widget registry.
- **Keyboard & accessibility behavior**: dialog-manager message routing
  (`IsDialogMessage`) for Tab/arrow navigation, initial focus forwarding to the
  first focusable child, and native default-button handling (`DM_GETDEFID` /
  `Window.setDefaultButton`) so Enter activates buttons.
- **Demo** (`demo/`): a window with a label, two proportional panels (2:1) and a
  Close button, plus a Windows resource pipeline (application manifest +
  version information) and a console-free windowed build.
- Project documentation: `README.md`, `CLAUDE.md`, this changelog, and
  `.editorconfig`.

[Unreleased]: https://example.com/deft/compare/v0.1.0-alpha...HEAD
[0.1.0-alpha]: https://example.com/deft/releases/tag/v0.1.0-alpha
