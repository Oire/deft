# Accessibility in Deft

Accessibility is a first-class concern in Deft, not a later add-on. The strategy
is deliberate: Deft wraps **real native controls**, so the platform's own
accessibility implementation (MSAA / IAccessible on Windows — the API JAWS and
NVDA use for classic controls) describes every control correctly with no custom
accessibility layer to maintain. On top of that, the framework does the extra
work that native controls alone don't guarantee: keyboard reachability, sensible
default focus, keyboard-triggered context menus, DPI correctness, and names for
controls that lack a visible label.

This document is a checklist of what Deft covers and exactly where each behavior
lives in the source, so you can verify a claim by reading the code.

## Checklist

| Concern | Status | Where |
|---|---|---|
| **Screen-reader roles/names/state** for all controls (MSAA) | ✅ via native controls | every `deft.controls.*` wrapper |
| **Custom accessible name** for unlabeled controls | ✅ `setAccessibleName` (MSAA Direct Annotation) | `source/deft/accessibility.d` |
| **Per-monitor DPI awareness** (so SR cursor tracking is correct) | ✅ | `Application.initialize` → `enableDpiAwareness`, `source/deft/app.d`; also forced before the first window in `Window`'s constructor |
| **Keyboard navigation** between controls (Tab / Shift+Tab / arrows) | ✅ dialog-manager routing | `Application.run` (`IsDialogMessageW`), `source/deft/app.d`; `WS_EX_CONTROLPARENT` on `Window`/`Panel` |
| **Initial focus** lands on a real control | ✅ focus forwarding | `Window.processMessage` (`WM_SETFOCUS`), `source/deft/window.d` |
| **Enter activates the default/focused button** (no key emulation) | ✅ native `DM_GETDEFID` | `Window.processMessage`, `source/deft/window.d`; `Dialog.addStandardButtons`, `source/deft/controls/dialog.d` |
| **Dialogs announced as dialogs**, children read as contents | ✅ real `#32770` dialog window | `source/deft/controls/dialog.d` |
| **Context menus from the keyboard** (Apps key / Shift+F10), anchored at selection | ✅ | `ListView`/`TreeView` `processSubclassed`, `source/deft/controls/{listview,treeview}.d`; `showPopupMenu`, `source/deft/menu.d` |
| **Radio groups are one tab stop**, navigated by arrow keys | ✅ `WS_GROUP`/`WS_TABSTOP` handling | `RadioButton`, `source/deft/controls/button.d` |
| **Multi-line text box does not trap Tab** (Tab moves focus; Ctrl+Tab inserts a tab) | ✅ | `TextBox.processSubclassed`, `source/deft/controls/textbox.d` |
| **First item selected on focus** for list/tree/combo (so the SR has something to announce) | ✅ | `processSubclassed` in `listview`/`treeview`/`listbox`/`combobox`/`checklistbox` |
| **Keyboard mnemonics** (`&` in labels) for menus, buttons, and form fields | ✅ native `&` parsing | menu/button/label text; built-in `Yes`/`No` dialog buttons carry mnemonics |
| **Window/taskbar/Alt+Tab icon** | ✅ | `Window.setIcon` + default window-class icon, `source/deft/window.d`, `source/deft/platform/win32/init.d` |
| **Embedded manifest + version info** (themed ComCtl32 v6; version read by the JAWS version keystroke) | ✅ (demo pattern) | `demo/app.rc`, `demo/make-res.ps1` |

> **Standalone static text is intentionally not announced.** A decorative `Label`
> not attached to a control stays silent — that matches native Win32 behavior. A
> static is announced when it labels a control (created immediately before it in
> z-order) or when reached with the screen-reader cursor.

## Verifying without a screen reader

You can inspect what a screen reader would read without driving JAWS/NVDA:

- **MSAA layer** (authoritative for classic controls): P/Invoke
  `AccessibleObjectFromWindow` + `get_accRole` / `get_accName` / `get_accState`.
- **UIA tree** (PowerShell): `Add-Type -AssemblyName UIAutomationClient`, find the
  window by name, and walk descendants for `ControlType` / `Name` /
  `IsKeyboardFocusable`. Note UIA may report native child controls as a generic
  `Pane` — a UIA-bridge quirk that does not affect MSAA screen readers.

See [CLAUDE.md](CLAUDE.md) for fuller notes on these techniques.

## Mnemonic conventions

- Mark the mnemonic letter with `&` in a control's text: `"&Open"`, `"E&xit"`.
- For a text field, put the mnemonic on the **`Label` created immediately before
  it** (Alt+letter then moves focus to the field).
- `OK`/`Cancel` conventionally have no mnemonic (Enter / Esc); `Yes`/`No` do — the
  built-in dialog buttons follow this.
