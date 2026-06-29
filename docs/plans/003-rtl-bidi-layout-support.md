# RTL & Bidi Layout Support

## Overview

Add right-to-left (RTL) and bidirectional layout support to Deft for Hebrew,
Arabic, and other RTL locales — a first-class concern alongside accessibility,
which this user explicitly cares about.

The strategy is to **lean on the OS, not rewrite the layout engine.** Win32
mirrors an entire window — child positions, native-control internals (scrollbar
side, list-view column order, caret), text alignment, and reading order — when a
window carries the `WS_EX_LAYOUTRTL` extended style. Because Deft wraps real
native controls and its sizers already produce ordinary client coordinates, the
OS mirrors that output for free. The layout engine (`HBox`/`VBox`/`Grid`) needs
**zero** direction logic.

Direction is resolved from a three-value `LayoutDirection`:

- `system` (default) — inferred from the user's OS locale via
  `GetLocaleInfoEx(LOCALE_IREADINGLAYOUT)`, so a Hebrew/Arabic Windows user gets
  RTL with **no application code at all**;
- `ltr` / `rtl` — explicit overrides.

Overrides layer: a process-wide default (`Application.setLayoutDirection`) that
new windows inherit, plus a per-window override (`Window.setLayoutDirection`).

The real work is not the switch (a handful of ex-style ORs) but a **bounded
coordinate audit**: the few sites that compute screen/client coordinates by hand
and then position a popup or page, which behave differently once the client area
is mirrored. Plus an **LTR-island escape hatch** so file paths, code, and
numbers can stay LTR inside an RTL window.

Bidi *within* a single string (Hebrew text with embedded Latin words or digits)
is already handled for free by the native controls (Uniscribe/DirectWrite) and
the existing UTF-8↔UTF-16 conversion — no work required.

## Context (from discovery)

Files/components involved (all read during the audit that produced this plan):

- `source/deft/window.d` — `Window` ctor builds the top-level window with
  `WS_EX_CONTROLPARENT`; natural home for per-window direction + the global hook.
- `source/deft/controls/panel.d` — child container window (`WS_EX_CONTROLPARENT`).
- `source/deft/controls/dialog.d` — `buildDialogTemplate` writes a `DLGTEMPLATE`
  whose `dwExtendedStyle` is currently `0` (offset 4); standard-button row.
- `source/deft/controls/control.d` — `Control` base; ctor takes an `exStyle`
  parameter — the seam for the LTR-island escape hatch.
- `source/deft/menu.d` — `showPopupMenu` anchors at `rc.left` and calls
  `TrackPopupMenu` with `TPM_LEFTALIGN`.
- `source/deft/controls/listview.d`, `treeview.d` — keyboard context-menu path
  computes an item rect (`LVM_GETITEMRECT`/`TVM_GETITEMRECT`) then `ClientToScreen`.
- `source/deft/controls/tabcontrol.d` — `getDisplayRect` (`TCM_ADJUSTRECT`) and
  `layoutPages` (`r.x += bounds.x`).
- `source/deft/app.d` — `Application`; natural home for the global default setter.
- `source/deft/package.d` — public re-exports.
- `source/deft/i18n.d` — the localization seam just added; RTL is the layout half
  of the same i18n story and should be documented next to it.

Related patterns found:

- Ex-styles are set at creation today (`Window`, `Panel`, `Control`, and the
  dialog template), which is the cleanest place to apply `WS_EX_LAYOUTRTL`.
- Dynamic feature resolution already exists (`enableDpiAwareness` resolves a
  `user32` entry point at runtime) — the same defensive style suits
  `GetLocaleInfoEx`.
- UI behavior is verified manually via the demo (per `README.md`/`CLAUDE.md`);
  only pure logic is unit-tested. RTL follows the same split.

Dependencies identified: none new. `GetLocaleInfoEx` and the RTL ex-styles are in
`core.sys.windows`; targets are modern Windows already (per-monitor DPI v2).

## Development Approach

- Complete each task fully before moving to the next.
- Make small, focused changes; build after each (`dub build`, `dub test`).
- **Unit tests are required for the pure, non-UI logic** (direction resolution,
  locale inference, ex-style mapping) and must pass before the next task.
- **Mirroring correctness is UI behavior** and, consistent with this project's
  established convention, is verified **manually via the demo** using the
  checklist in *Post-Completion* — it only surfaces at runtime and cannot be
  asserted headlessly. Each coordinate-audit task therefore lists its manual
  verification step explicitly instead of a unit test.
- Maintain backward compatibility: `LayoutDirection.system` is the default and,
  on an LTR locale, every behavior is byte-for-byte what it is today.
- Honor conventions: American spelling, tabs, no Phobos outside `unittest`, DDoc
  on public symbols, accessibility-first.
- Keep this plan in sync with reality as scope shifts.

## Testing Strategy

- **Unit tests** (required, headless): `LayoutDirection` resolution
  (`system`→resolved, `ltr`/`rtl` passthrough), `exStyleFor` mapping, and that
  `systemLayoutDirection()` returns a valid value without crashing on the CI
  locale. These live in `source/deft/layoutdirection.d` `unittest` blocks.
- **No e2e harness** exists in this project; there is nothing to add there.
- **Manual RTL verification**: a dedicated checklist (see *Post-Completion*),
  run against the demo forced to RTL, covering mirroring of each control, popup
  anchoring, tab pages, LTR islands, and screen-reader reading order.

## Progress Tracking

- Mark completed items with `[x]` immediately.
- Add newly discovered tasks with ➕ prefix; blockers with ⚠️ prefix.
- Update this file if implementation deviates from scope.

## What Goes Where

- **Implementation Steps** (`[ ]`): code, unit tests for pure logic, docs.
- **Post-Completion** (no checkboxes): manual RTL testing with a screen reader,
  and notes for consuming projects (e.g. Notika) on adopting the new API.

## Implementation Steps

### Task 1: `LayoutDirection` type, locale inference, and resolution helpers

**Files:**
- Create: `source/deft/layoutdirection.d`
- Modify: `source/deft/package.d`

- [ ] create `deft.layoutdirection` with `enum LayoutDirection { system, ltr, rtl }`
      (`system` avoids the `auto` keyword and reads as "follow the OS")
- [ ] add `LayoutDirection systemLayoutDirection()` — query
      `GetLocaleInfoEx(LOCALE_NAME_USER_DEFAULT, LOCALE_IREADINGLAYOUT, ...)`;
      a value of `1` means RTL reading order, anything else (incl. failure) → `ltr`
- [ ] define locally any constant absent from `core.sys.windows`
      (`LOCALE_IREADINGLAYOUT` is the likely one to be missing; `WS_EX_LAYOUTRTL`
      = 0x0040_0000, `WS_EX_NOINHERITLAYOUT` = 0x0010_0000, `WS_EX_RTLREADING`
      = 0x0000_2000, `TPM_LAYOUTRTL` = 0x4000 as needed) — same precedent as the
      minimal bindings in `accessibility.d`
- [ ] add module-global default `__gshared LayoutDirection g_appLayoutDirection = LayoutDirection.system`
      with `setAppLayoutDirection`/`appLayoutDirection` accessors
- [ ] add `LayoutDirection resolve(LayoutDirection d)` — `system` → app default,
      then `system` → `systemLayoutDirection()`; `ltr`/`rtl` pass through
- [ ] add `DWORD exStyleForLayout(LayoutDirection d)` → `WS_EX_LAYOUTRTL` when
      resolved RTL, else `0` (single source of truth for the style bit)
- [ ] re-export the module from `source/deft/package.d`
- [ ] write tests: `resolve` for `ltr`/`rtl` (exact) and `system` (assert the
      result is a *member of* `{ltr, rtl}`, never a specific value — it depends on
      the CI machine's locale); `exStyleForLayout` mapping; `systemLayoutDirection()`
      returns `ltr` or `rtl` and does not throw
- [ ] run `dub test` — must pass before Task 2

### Task 2: Apply direction to `Window` + `Application` global setter

**Files:**
- Modify: `source/deft/window.d`
- Modify: `source/deft/app.d`

- [ ] add `Application.setLayoutDirection(LayoutDirection)` /
      `Application.layoutDirection()` thin wrappers over the module global (keeps
      the discoverable entry point on `Application`)
- [ ] `Window`: add a private resolved-direction field; OR `exStyleForLayout(...)`
      into the creation ex-style alongside `WS_EX_CONTROLPARENT`
- [ ] add `Window.setLayoutDirection(LayoutDirection)` that updates `GWL_EXSTYLE`
      and forces a non-client refresh (`SetWindowPos` with `SWP_FRAMECHANGED`)
- [ ] **DDoc the runtime caveat firmly:** a post-creation flip re-mirrors the
      *layout* (the next sizer pass repositions children in the flipped client
      origin) but does **not** restyle controls that already exist — Win32 applies
      mirroring to a child's internals (text alignment, scrollbar side, list-view
      column order, caret) only at *creation* time. For a fully-correct RTL window,
      set the direction (app default or per-window) **before** creating controls;
      the runtime setter is a convenience for whole-window re-layout, not a true
      live re-theme
- [ ] DDoc the default (`system`, inferred from locale) on the public methods
- [ ] manual check (deferred to checklist): an RTL window mirrors its box-laid
      children with no layout-engine change
- [ ] run `dub build` + `dub test` — must pass before Task 3

### Task 3: Apply direction to `Panel`, `Dialog`, and the message box

**Files:**
- Modify: `source/deft/controls/panel.d`
- Modify: `source/deft/controls/dialog.d`
- Modify: `source/deft/controls/messagebox.d`

- [ ] `Dialog`: write `exStyleForLayout(resolved)` into the dialog template's
      `dwExtendedStyle` (offset 4 in `buildDialogTemplate`), resolving direction
      from the parent widget's window (fall back to the app default)
- [ ] `messagebox.d`: OR `MB_RTLREADING | MB_RIGHT` into the `MessageBoxW` flags
      when the owner/app direction resolves RTL — the native message box does not
      reliably inherit the owner's mirroring, and it is a first-class, screen-
      reader-announced surface, so it must read right-to-left in an RTL app
- [ ] `Panel`: determine whether a child panel inherits the parent window's
      mirroring automatically; if not, OR the style into its creation ex-style.
      Record the finding in *Technical Details* and only add the explicit set if
      the manual check shows it is needed (avoid `WS_EX_NOINHERITLAYOUT` surprises)
- [ ] DDoc any new behavior
- [ ] manual check (deferred): RTL dialog (incl. `showInputDialog`), an RTL
      panel/tab page, and an RTL message box mirror correctly
- [ ] run `dub build` + `dub test` — must pass before Task 4

### Task 4: Coordinate audit — popup menu anchoring (`menu.d`, `trayicon.d`)

**Files:**
- Modify: `source/deft/menu.d`
- Modify: `source/deft/controls/trayicon.d`

- [ ] in `showPopupMenu`, detect the target window's direction via
      `GetWindowLongPtrW(parent.handle, GWL_EXSTYLE) & WS_EX_LAYOUTRTL`
- [ ] when RTL: anchor the keyboard-triggered menu at the focused control's
      **right** edge (`rc.right`) instead of `rc.left`, and pass
      `TPM_LAYOUTRTL | TPM_RIGHTALIGN` (instead of `TPM_LEFTALIGN`) to
      `TrackPopupMenu`
- [ ] `trayicon.d` has its **own** `TrackPopupMenu(... TPM_LEFTALIGN ...)`
      (handleMouse): give it the same RTL treatment, or route it through the
      now-direction-aware `showPopupMenu` to avoid duplicated logic
- [ ] keep the LTR path byte-for-byte unchanged
- [ ] manual check (deferred): both the regular and tray context menus open on the
      correct edge from keyboard and mouse in both directions
- [ ] run `dub build` + `dub test` — must pass before Task 5

### Task 5: Coordinate audit — list/tree keyboard context menu

**Files:**
- Modify: `source/deft/controls/listview.d`
- Modify: `source/deft/controls/treeview.d`

- [ ] review the keyboard-anchor branch (`sx == -1 && sy == -1`): the item rect
      from `LVM_GETITEMRECT`/`TVM_GETITEMRECT` plus `ClientToScreen` is computed
      in the (now possibly mirrored) client space
- [ ] anchor at the item's **leading** edge for the active direction (RTL → right)
      so the menu appears beside the item where focus is, then hand the screen
      point to `showPopupMenu` (which Task 4 made direction-aware)
- [ ] confirm the mouse hit-test branch still resolves the correct row/item under
      the cursor when mirrored
- [ ] keep the LTR path unchanged
- [ ] manual check (deferred): right-click and Apps/Shift+F10 land correctly in RTL
- [ ] run `dub build` + `dub test` — must pass before Task 6

### Task 6: Coordinate audit — tab control page placement (`tabcontrol.d`)

**Files:**
- Modify: `source/deft/controls/tabcontrol.d`

- [ ] verify `getDisplayRect` (`TCM_ADJUSTRECT`) and `layoutPages`
      (`r.x += bounds.x`, then `setBounds`) place pages correctly when the parent
      is mirrored; adjust the offset math only if the manual check shows drift
- [ ] confirm page show/hide and selection still track the right page in RTL
- [ ] keep the LTR path unchanged
- [ ] manual check (deferred): tab pages fill the display area and the tab strip
      reads right-to-left in RTL
- [ ] run `dub build` + `dub test` — must pass before Task 7

### Task 7: LTR-island escape hatch

**Files:**
- Modify: `source/deft/controls/control.d`

- [ ] add `Control.setLayoutDirection(LayoutDirection)` (and/or a readable
      `Control.setLeftToRight()`): for an LTR island inside an RTL window, **clear
      the control's own `WS_EX_LAYOUTRTL`** bit (it was inherited at creation) and
      clear `WS_EX_RTLREADING`, via `GWL_EXSTYLE` + frame refresh. Note:
      `WS_EX_NOINHERITLAYOUT` is **not** the right tool for a leaf control — it only
      stops a window passing mirroring to its *child* windows, so it does nothing
      on a childless `TextBox`. Reserve `WS_EX_NOINHERITLAYOUT` for a *container*
      (`Panel`) that should host an entire LTR sub-tree
- [ ] DDoc when to use it (file paths, code, version numbers, IDs) and that it is
      a no-op in an LTR window
- [ ] manual check (deferred): an LTR text box inside an RTL window keeps LTR
      caret/alignment while the surrounding UI stays mirrored
- [ ] run `dub build` + `dub test` — must pass before Task 8

### Task 8: Exercise RTL in the demo

**Files:**
- Modify: `demo/source/app.d`

- [ ] make the **authoritative** RTL test a from-creation launch: support
      forcing the app default to `rtl` *before* any window/control is created
      (e.g. a `--rtl` command-line switch or an env var read at startup), so the
      whole gallery is built mirrored — this is what a real RTL app looks like
- [ ] add a `View ▸ Right-to-left` checkable menu item calling
      `window.setLayoutDirection(...)` as a **convenience** only; comment that it
      re-mirrors layout but not pre-existing controls' internals (per Task 2)
- [ ] mark one field (e.g. a path/number-style text box) as an LTR island to
      demonstrate and exercise Task 7
- [ ] confirm the demo builds, launches mirrored under the from-creation switch,
      and the LTR island stays LTR
- [ ] manual check (deferred): from-creation RTL mirrors the whole gallery
      correctly (the toggle is only a rough live preview)

### Task 9: Documentation

**Files:**
- Modify: `README.md`
- Modify: `ACCESSIBILITY.md`
- Modify: `CHANGELOG.md`

- [ ] README: a short "Right-to-left & bidi" subsection — `LayoutDirection`,
      auto-from-locale default, LTR islands, and the "bidi-in-strings is free"
      note; cross-link the i18n seam
- [ ] ACCESSIBILITY.md: add RTL/reading-order rows to the checklist with source
      locations
- [ ] CHANGELOG: `Unreleased` entry for RTL support
- [ ] run `dub build -b ddoc` to confirm DDoc still generates cleanly

### Task 10: Verify acceptance criteria

- [ ] verify every Overview requirement is implemented (auto-from-locale default,
      app + per-window overrides, LTR islands, audited coordinate sites)
- [ ] verify the LTR locale path is unchanged (no regressions in `dub test` or the
      demo run on an LTR system)
- [ ] run the full suite: `dub test`
- [ ] build the demo: `dub build --root=demo -b release`
- [ ] complete the manual RTL checklist in *Post-Completion*

### Task 11: Finalize

- [ ] update CLAUDE.md if a new RTL pattern/gotcha is worth recording
- [ ] tick all checkboxes and reconcile any ➕/⚠️ items
- [ ] move this plan to `docs/plans/completed/` (plain `mv`)

## Technical Details

- **Direction detection:** `GetLocaleInfoEx(LOCALE_NAME_USER_DEFAULT,
  LOCALE_IREADINGLAYOUT, buf, len)` writes a numeric string; `"1"` = RTL,
  `"0"` = LTR (and `2`/`3` are vertical layouts, treated as LTR for our purposes).
  Resolve defensively — any failure falls back to LTR.
- **Style bit & inheritance:** `WS_EX_LAYOUTRTL` (0x0040_0000) on a window mirrors
  its client coordinate system, so the unchanged sizer output is mirrored by the
  OS. A child window **inherits** the parent's mirroring **at creation time**
  (which is why direction must be decided before controls are created, and why a
  runtime flip can't fully re-theme existing controls).
  - **LTR island (leaf control):** clear the control's **own** `WS_EX_LAYOUTRTL`
    (and `WS_EX_RTLREADING`, 0x0000_2000) — the bit it inherited at creation. Do
    **not** use `WS_EX_NOINHERITLAYOUT` here: that bit only governs whether a
    window propagates mirroring to its *child* windows, so it is a no-op on a
    childless control.
  - **LTR sub-tree (container):** `WS_EX_NOINHERITLAYOUT` (0x0010_0000) on a
    `Panel` stops it handing mirroring down to its children — the correct use.
- **Dialog template:** `dwExtendedStyle` lives at byte offset 4 in the packed
  `DLGTEMPLATE` written by `buildDialogTemplate`; set it there so the dialog is
  created mirrored from the start.
- **Message box:** `MessageBoxW` does not reliably inherit the owner's mirroring;
  OR `MB_RTLREADING | MB_RIGHT` into its flags when RTL.
- **Popups:** `TrackPopupMenu` accepts `TPM_LAYOUTRTL` and `TPM_RIGHTALIGN`;
  combine with anchoring at the leading (right) edge in RTL. Both `menu.d`'s
  `showPopupMenu` and `trayicon.d`'s own `TrackPopupMenu` call need this.
- **Why not mirror in the layout engine:** that would be larger *and* incomplete —
  it could not mirror native-control internals (scrollbar side, column order,
  caret), which `WS_EX_LAYOUTRTL` handles. The engine stays direction-agnostic.
- **Open question to settle during Task 3:** whether a child `Panel` inherits the
  parent's mirror automatically (expected) or needs the style set explicitly.

## Post-Completion

*Items requiring manual intervention or external systems — informational only.*

**Manual RTL verification** (run the demo with `View ▸ Right-to-left` on, ideally
on a Hebrew/Arabic Windows or with the app default forced to `rtl`):

- Window, tabs, panels, and the dialog mirror: controls flow right-to-left,
  scrollbars sit on the left, list-view columns order right-to-left.
- Box and grid layouts mirror with **no** code change (first `add()` child on the
  right).
- Context menus (mouse and Apps/Shift+F10) open on the correct edge in `ListView`,
  `TreeView`, and via `showPopupMenu`.
- The **tray icon** context menu opens with the correct alignment/reading order.
- Tab pages fill the display area; the tab strip reads right-to-left.
- A **multi-part status bar** mirrors its parts (no code expected, but confirm).
- An LTR island (path/number field) keeps LTR caret and alignment inside the RTL
  window.
- A **message box** (`showMessageBox`) reads right-to-left.
- Standard dialog buttons (already OS-localized) read in the correct order.
- Hebrew text with embedded Latin/digits shapes correctly inside text boxes
  (bidi-in-string, expected free).
- **Screen reader (JAWS/NVDA in an RTL configuration):** reading order and
  announced control order match the visual right-to-left order — the core
  accessibility acceptance test.

**External system updates:**

- Consuming projects (e.g. Notika): no change required to keep current behavior
  (`system` default = today's behavior on an LTR locale). To adopt RTL, call
  `Application.setLayoutDirection` or `Window.setLayoutDirection`, and mark any
  LTR islands. Worth a short note to those consumers when this ships.
