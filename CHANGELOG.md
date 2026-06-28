# Changelog

All notable changes to Deft are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
