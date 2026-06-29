# Changelog

All notable changes to Deft are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-06-29

First release. A native UI framework for D that wraps real Win32 controls — so
they bring native accessibility (MSAA/IAccessible) with them — and adds a
delegate-based event system, box and table layout, and a full set of controls,
menus, dialogs and system services. Win32 only.

### Application & windows

- **`Application`**: singleton lifecycle with a message loop, `quit`, and process
  initialization (common controls, COM, per-monitor DPI awareness).
- **`Widget` / `Window`**: visibility, bounds, enablement, focus, and deterministic
  `dispose()` with GC-root pinning; cancellable `onClose` and `onResize` events.
- **Geometry types**: `Rect`, `Size`, `Padding`.
- **Window icons** (`Window.setIcon`) plus `deft.util.icons` (`loadIcon`,
  `loadIconFromFile`) for title-bar, taskbar and Alt+Tab icons.

### Events

- **`Event!(T...)`**: multicast delegates with `~=`, `fire`, `disconnect`;
  `KeyEventArgs`, `MouseEventArgs`, `CloseEventArgs`, and handler aliases (`Action`,
  `SelectionEvent`, `KeyEvent`, `MouseEvent`, `TextEvent`).

### Layout

- **Box layout** (`Sizer`, `HBox`, `VBox`): proportional placement with per-child
  padding and nesting; wired into `Window.setSizer`.
- **`Grid` table layout** (à la WinForms `TableLayoutPanel`): `autoSize` / `pixels`
  / `percent` column and row tracks, inter-cell spacing, and column/row spanning.
- **Per-cell alignment** for all sizers via `HAlign { fill, left, center, right }`
  and `VAlign { fill, top, middle, bottom }`, so the cross axis can align rather
  than always stretch.
- **Fluent placement**: `Sizer.add`/`addSizer` take the child and return a
  `SizerItem` configured with `.proportion()`, `.pad()`, `.alignH()`, `.alignV()`;
  `Grid.add` returns a `GridItem` adding `.span()` and `.aligned()`.

### Controls

- **Controls**: `Label`; `Button`, `CheckBox`, `RadioButton`; `TextBox`
  (single/multi-line, read-only, `onTextChanged`/`onKeyDown`); `ListView` (report
  mode — columns, item data, selection/activation events); `TreeView`; `ListBox`
  (`single`/`multiple`/`extended` selection); `ComboBox` (`dropDownList`, editable
  `dropDown`, `simple`); `CheckListBox`; `TabControl`; `StatusBar`.
- **`Panel`** — a sizer-arranged container that, unlike a bare static control,
  forwards its children's `WM_COMMAND`/`WM_NOTIFY` notifications.
- **`Control` base**: create native common controls, text/font,
  `WM_COMMAND`/`WM_NOTIFY` routing to the originating control, and opt-in
  subclassing.

### Menus & dialogs

- **Menus & accelerators** (`deft.menu`): `MenuBar`, `Menu`, `MenuItem`,
  `showPopupMenu`, accelerator-string parsing (`parseAccelerator`) and tables wired
  into the message loop via `TranslateAccelerator`.
- **Dialogs**: a native modal `Dialog` (a real `#32770` dialog-class window built
  with `CreateDialogIndirectParamW`, announced as a dialog by screen readers),
  `showMessageBox`, and `showInputDialog`.

### System services

- **`Timer`** (repeating and one-shot).
- **`TrayIcon`**: notification-area icon with tooltip, context menu, balloon, and
  `onDoubleClicked`.
- **Cross-thread messaging** (`CommandQueue!T`, `UiDispatcher!T`): thread-safe queue
  plus a UI-thread wake mechanism.

### Accessibility & keyboard

- **Accessible names** (`setAccessibleName`): custom names via MSAA Direct
  Annotation (`IAccPropServices`).
- **Keyboard navigation**: dialog-manager message routing (`IsDialogMessage`) for
  Tab/arrow navigation, initial focus forwarding to the first focusable child, and
  native default-button handling (`DM_GETDEFID` / `Window.setDefaultButton`) so
  Enter activates buttons.
- **Radio groups are a single tab stop**: every control starts its own `WS_GROUP`,
  and a non-first `RadioButton` joins the previous one's group, so a group is one tab
  stop navigated with the arrow keys.
- **Multi-line `TextBox`** lets Tab move focus while Ctrl+Tab inserts a literal tab.
- **Keyboard-accessible context menus** on `ListView`/`TreeView` (mouse right-click
  and the Apps key / Shift+F10), anchored at the selected item.
- **First-item auto-selection on focus** for `ListView`, `TreeView`, `ListBox`, the
  drop-down-list `ComboBox`, and `CheckListBox`.

### Localization

- **Localization seam** (`deft.i18n`): `setTranslator`/`tr`/`translator` — a hook
  through which a consumer plugs in its own catalog (the library bundles none), so
  every user-facing string the framework emits can be translated.

### Win32 backend & utilities

- **Win32 backend**: default window-class registration and a single master window
  procedure with an HWND→Widget registry.
- **String utilities** (`toWStringz`, `fromWStringz`, `fromWString`): UTF-8 ↔ UTF-16
  via the Win32 conversion APIs (no Phobos).

### Demo & documentation

- **Demo** (`demo/`): a widget gallery exercising every control type, fully localized
  through the i18n seam (gettext catalogs via `mofile`, demo-only), plus a Windows
  resource pipeline (application manifest + version information) and a console-free
  windowed build.
- Project documentation: `README.md`, `CLAUDE.md`, this changelog, and
  `.editorconfig`.

[Unreleased]: https://github.com/Oire/deft/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Oire/deft/releases/tag/v0.1.0
