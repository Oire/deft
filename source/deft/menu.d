/**
 * Menu system: menu bars, popup menus, menu items and keyboard accelerators.
 *
 * A `MenuItem` is a lightweight value describing one command (id, label,
 * optional accelerator such as `"Ctrl+N"`, and an `onClicked` event). `Menu`
 * wraps a native popup `HMENU`; `MenuBar` wraps a window menu `HMENU` and is
 * attached to a `Window` via `Window.setMenuBar`.
 *
 * Menu and accelerator commands both arrive as `WM_COMMAND` with a null
 * `lParam`; `Window` routes them here through `dispatchMenuCommand`, which fires
 * the matching item's `onClicked`. Accelerators are collected from every item
 * carrying an accelerator string into a single `HACCEL` table that the message
 * loop feeds to `TranslateAccelerator`.
 *
 * The native menus provide MSAA accessibility for free: screen readers announce
 * menu names, item labels, accelerator text, and checked/disabled state.
 */
module deft.menu;

version (Windows):

import core.sys.windows.windows;

import deft.events;
import deft.util.strings;
import deft.widget : Widget;

/// The kind of a menu item.
enum MenuItemKind
{
	/// A normal command item.
	normal,
	/// A horizontal separator line (no command).
	separator,
	/// A command item with a check mark that can be toggled.
	checkable,
}

/**
 * One menu command.
 *
 * Construct with an id (pass `0` to have one generated), a label (an `&`
 * marks the keyboard mnemonic), and an optional accelerator string. Attach a
 * handler to `onClicked` before appending the item to a `Menu`, or look the
 * stored item up later with `Menu.findItem`.
 */
struct MenuItem
{
	/// Command identifier. Unique within the application's menus.
	int id;

	/// Display label, with `&` marking the mnemonic letter.
	string label;

	/// Accelerator description, for example `"Ctrl+Shift+N"`; empty for none.
	string accelerator;

	/// Whether the item is a normal command, a separator, or checkable.
	MenuItemKind kind = MenuItemKind.normal;

	/// Current checked state (only meaningful for `MenuItemKind.checkable`).
	bool checked;

	/// Whether the item can be invoked.
	bool enabled = true;

	/// Fired when the item is chosen (by mouse, mnemonic, or accelerator).
	Event!() onClicked;

	/**
	 * Build a menu item.
	 *
	 * Params:
	 *   id          = command id, or `0` to auto-generate a unique one.
	 *   label       = display label (`&` marks the mnemonic).
	 *   accelerator = accelerator string such as `"Ctrl+N"`, or empty.
	 *   kind        = item kind.
	 */
	this(int id, string label, string accelerator = "",
		MenuItemKind kind = MenuItemKind.normal)
	{
		this.id = id;
		this.label = label;
		this.accelerator = accelerator;
		this.kind = kind;
	}
}

private __gshared int g_nextMenuId = 30_000;

/// Generate a unique menu command id (used when an item is appended with id 0).
int nextMenuId()
{
	return g_nextMenuId++;
}

/// id → stored item registry, so `WM_COMMAND` can find the originating item.
private __gshared MenuItem*[int] g_menuCommands;

/**
 * Dispatch a menu or accelerator command to its item's `onClicked`.
 *
 * Returns `true` if an enabled item with the given id was found and fired.
 */
bool dispatchMenuCommand(int id)
{
	if (auto item = id in g_menuCommands)
	{
		if ((*item).enabled)
		{
			(*item).onClicked.fire();
			return true;
		}
	}
	return false;
}

private enum string acceleratorSeparator = "\t";

/// The label as shown natively: mnemonic label plus right-aligned accelerator.
private string labelWithAccelerator(ref MenuItem item)
{
	if (item.accelerator.length == 0)
		return item.label;
	return item.label ~ acceleratorSeparator ~ item.accelerator;
}

/**
 * A popup menu — a list of items, separators and submenus.
 *
 * Wraps an `HMENU` from `CreatePopupMenu`. Use as a window menu's child (via
 * `MenuBar.append`), as a submenu (via `appendSubmenu`), or as a standalone
 * context menu (via `showPopupMenu`).
 */
class Menu
{
	private HMENU handle_;
	private MenuItem*[] items_;
	private Menu[] submenus_;
	private bool ownsHandle_ = true;
	private bool disposed_;

	/// Create an empty popup menu.
	this()
	{
		handle_ = CreatePopupMenu();
	}

	/// The native menu handle.
	HMENU handle() @safe pure nothrow @nogc
	{
		return handle_;
	}

	/**
	 * Append a command item.
	 *
	 * If `item.id` is 0 a unique id is generated. A heap copy of the item is
	 * stored (so its `onClicked` survives) and returned for later wiring.
	 */
	MenuItem* append(MenuItem item)
	{
		if (item.id == 0)
			item.id = nextMenuId();

		auto stored = new MenuItem;
		*stored = item;
		items_ ~= stored;
		g_menuCommands[stored.id] = stored;

		UINT flags = MF_STRING;
		if (stored.checked)
			flags |= MF_CHECKED;
		if (!stored.enabled)
			flags |= MF_GRAYED;

		AppendMenuW(handle_, flags, cast(UINT_PTR) stored.id,
			labelWithAccelerator(*stored).toWStringz);
		return stored;
	}

	/// Append a separator line.
	void appendSeparator()
	{
		AppendMenuW(handle_, MF_SEPARATOR, 0, null);
	}

	/// Append a submenu under `label`.
	void appendSubmenu(Menu submenu, string label)
	{
		submenus_ ~= submenu;
		// The parent now owns the submenu's HMENU: DestroyMenu on this menu frees
		// its submenus recursively, so the submenu must not free its own handle.
		submenu.ownsHandle_ = false;
		AppendMenuW(handle_, MF_POPUP, cast(UINT_PTR) submenu.handle_,
			label.toWStringz);
	}

	/// Find a stored item by id, searching this menu and its submenus.
	MenuItem* findItem(int id)
	{
		foreach (it; items_)
			if (it.id == id)
				return it;
		foreach (sub; submenus_)
			if (auto found = sub.findItem(id))
				return found;
		return null;
	}

	/// Set (or clear) the check mark on item `id`.
	void setChecked(int id, bool checked)
	{
		if (auto it = findItem(id))
			it.checked = checked;
		CheckMenuItem(handle_, id,
			MF_BYCOMMAND | (checked ? MF_CHECKED : MF_UNCHECKED));
	}

	/// Enable or disable item `id`.
	void setEnabled(int id, bool enabled)
	{
		if (auto it = findItem(id))
			it.enabled = enabled;
		EnableMenuItem(handle_, id,
			MF_BYCOMMAND | (enabled ? MF_ENABLED : MF_GRAYED));
	}

	/**
	 * Change the visible label of item `id` (its accelerator text is preserved),
	 * searching this menu and its submenus. Returns `true` if the item was found.
	 * Useful for retranslating menus when the UI language changes at runtime.
	 */
	bool setItemText(int id, string label)
	{
		foreach (it; items_)
			if (it.id == id)
			{
				it.label = label;
				ModifyMenuW(handle_, id, MF_BYCOMMAND | MF_STRING,
					cast(UINT_PTR) id, labelWithAccelerator(*it).toWStringz);
				return true;
			}
		foreach (sub; submenus_)
			if (sub.setItemText(id, label))
				return true;
		return false;
	}

	/// Append every accelerator-bearing item in this menu tree to `accels`.
	private void collectAccelerators(ref ACCEL[] accels)
	{
		foreach (it; items_)
		{
			auto parsed = parseAccelerator(it.accelerator);
			if (parsed.valid)
			{
				ACCEL a;
				a.fVirt = cast(BYTE)(parsed.fVirt | FVIRTKEY);
				a.key = parsed.key;
				a.cmd = cast(WORD) it.id;
				accels ~= a;
			}
		}
		foreach (sub; submenus_)
			sub.collectAccelerators(accels);
	}

	/// Remove this menu's (and its submenus') items from the command registry.
	private void unregisterCommands()
	{
		foreach (it; items_)
			g_menuCommands.remove(it.id);
		foreach (sub; submenus_)
			sub.unregisterCommands();
	}

	/**
	 * Release the menu's native resources: drop its items from the command
	 * registry and destroy its `HMENU` (which frees any submenu handles too).
	 *
	 * Call this on a standalone context menu (one shown with `showPopupMenu`) when
	 * you are finished with it — an app that rebuilds context menus per invocation
	 * would otherwise leak an `HMENU` and command-registry entries each time. A
	 * menu attached to a `MenuBar` or as a submenu is owned by its parent and
	 * freed when the parent is disposed; calling `dispose` on it is still safe.
	 * Idempotent.
	 */
	void dispose()
	{
		if (disposed_)
			return;
		disposed_ = true;

		unregisterCommands();
		if (ownsHandle_ && handle_ !is null)
			DestroyMenu(handle_);
		handle_ = null;
	}
}

/**
 * A window menu bar — the horizontal strip of top-level menus.
 *
 * Wraps an `HMENU` from `CreateMenu`. Build it with `append`, then attach it to
 * a window with `Window.setMenuBar`, which also installs its accelerator table.
 */
class MenuBar
{
	private HMENU handle_;
	private Menu[] menus_;
	private bool disposed_;

	/// Create an empty menu bar.
	this()
	{
		handle_ = CreateMenu();
	}

	/// The native menu handle.
	HMENU handle() @safe pure nothrow @nogc
	{
		return handle_;
	}

	/// Append a top-level menu under `label`.
	void append(Menu menu, string label)
	{
		menus_ ~= menu;
		// The bar owns the menu's HMENU now (DestroyMenu on the bar frees it).
		menu.ownsHandle_ = false;
		AppendMenuW(handle_, MF_POPUP, cast(UINT_PTR) menu.handle,
			label.toWStringz);
	}

	/// Find a stored item by id across every menu in the bar.
	MenuItem* findItem(int id)
	{
		foreach (m; menus_)
			if (auto found = m.findItem(id))
				return found;
		return null;
	}

	/// Set (or clear) the check mark on item `id`.
	void setChecked(int id, bool checked)
	{
		foreach (m; menus_)
			if (m.findItem(id) !is null)
			{
				m.setChecked(id, checked);
				return;
			}
	}

	/// Enable or disable item `id`.
	void setEnabled(int id, bool enabled)
	{
		foreach (m; menus_)
			if (m.findItem(id) !is null)
			{
				m.setEnabled(id, enabled);
				return;
			}
	}

	/**
	 * Change the label of item `id` anywhere in the bar (accelerator preserved).
	 * Call `DrawMenuBar(window.handle)` afterward if a top-level item changed.
	 */
	void setItemText(int id, string label)
	{
		foreach (m; menus_)
			if (m.setItemText(id, label))
				return;
	}

	/**
	 * Change the title of the top-level menu at `index` (e.g. retranslating
	 * "File"/"Edit"). Call `DrawMenuBar(window.handle)` afterward to repaint.
	 */
	void setMenuTitle(int index, string label)
	{
		if (index >= 0 && index < menus_.length)
			ModifyMenuW(handle_, index, MF_BYPOSITION | MF_POPUP,
				cast(UINT_PTR) menus_[index].handle, label.toWStringz);
	}

	/**
	 * Build an accelerator table from every accelerator-bearing item in the bar.
	 * Returns null when there are no accelerators.
	 */
	HACCEL buildAcceleratorTable()
	{
		ACCEL[] accels;
		foreach (m; menus_)
			m.collectAccelerators(accels);
		if (accels.length == 0)
			return null;
		return CreateAcceleratorTableW(accels.ptr, cast(int) accels.length);
	}

	/**
	 * Release the menu bar's native resources: drop every item from the command
	 * registry and destroy the bar's `HMENU` (which frees its menus' handles too).
	 *
	 * Call this only when the bar is no longer attached to a live window — a menu
	 * assigned to a window is destroyed automatically when the window is destroyed,
	 * so disposing it again would be a double free. Use it when you build a bar you
	 * never attach, or replace a window's menu bar at runtime. Idempotent.
	 */
	void dispose()
	{
		if (disposed_)
			return;
		disposed_ = true;

		foreach (m; menus_)
			m.unregisterCommands();
		if (handle_ !is null)
			DestroyMenu(handle_);
		handle_ = null;
	}
}

/**
 * Show `menu` as a context menu owned by `parent`.
 *
 * `x`/`y` are screen coordinates; pass `-1, -1` to position the menu at the
 * focused control (for a keyboard-triggered menu via the Apps key or
 * Shift+F10). The chosen command is delivered to `parent` as a `WM_COMMAND`,
 * so it routes through `dispatchMenuCommand` like any other menu command.
 */
void showPopupMenu(Menu menu, Widget parent, int x = -1, int y = -1)
{
	if (menu is null || parent is null || parent.handle is null)
		return;

	if (x == -1 && y == -1)
	{
		// Keyboard-triggered: anchor at the focused control, else the parent.
		HWND focus = GetFocus();
		RECT rc;
		if (focus !is null && GetWindowRect(focus, &rc))
		{
			x = rc.left;
			y = rc.bottom;
		}
		else if (GetWindowRect(parent.handle, &rc))
		{
			x = rc.left + (rc.right - rc.left) / 2;
			y = rc.top + (rc.bottom - rc.top) / 2;
		}
	}

	// Required so the menu dismisses correctly when clicking elsewhere.
	SetForegroundWindow(parent.handle);
	TrackPopupMenu(menu.handle, TPM_LEFTALIGN | TPM_RIGHTBUTTON,
		x, y, 0, parent.handle, null);
}

/**
 * Result of parsing an accelerator string.
 *
 * `valid` is false for an empty or unrecognized string. `fVirt` carries the
 * `FCONTROL`/`FSHIFT`/`FALT` modifier flags (the caller adds `FVIRTKEY`); `key`
 * is the virtual-key code.
 */
struct Accelerator
{
	bool valid;
	ubyte fVirt;
	ushort key;
}

private bool asciiEquals(string a, string b)
{
	if (a.length != b.length)
		return false;
	foreach (i, c; a)
	{
		char ca = c;
		char cb = b[i];
		if (ca >= 'A' && ca <= 'Z')
			ca = cast(char)(ca + 32);
		if (cb >= 'A' && cb <= 'Z')
			cb = cast(char)(cb + 32);
		if (ca != cb)
			return false;
	}
	return true;
}

private string[] splitOnPlus(string s)
{
	string[] parts;
	size_t start = 0;
	foreach (i, c; s)
	{
		if (c == '+')
		{
			parts ~= s[start .. i];
			start = i + 1;
		}
	}
	parts ~= s[start .. $];
	return parts;
}

/// Map a single key token (the part after the modifiers) to a virtual-key code.
private bool keyTokenToVk(string token, out ushort vk)
{
	if (token.length == 0)
		return false;

	if (token.length == 1)
	{
		char c = token[0];
		if (c >= 'a' && c <= 'z')
		{
			vk = cast(ushort)(c - 32); // 'A'..'Z'
			return true;
		}
		if (c >= 'A' && c <= 'Z')
		{
			vk = cast(ushort) c;
			return true;
		}
		if (c >= '0' && c <= '9')
		{
			vk = cast(ushort) c;
			return true;
		}
		switch (c)
		{
		case ',': vk = VK_OEM_COMMA; return true;
		case '.': vk = VK_OEM_PERIOD; return true;
		case ';': vk = 0xBA; return true; // VK_OEM_1
		case '/': vk = 0xBF; return true; // VK_OEM_2
		case '-': vk = VK_OEM_MINUS; return true;
		case '=': vk = VK_OEM_PLUS; return true;
		default: return false;
		}
	}

	// Function keys F1..F24.
	if ((token[0] == 'f' || token[0] == 'F') && token.length <= 3)
	{
		int n = 0;
		bool digits = true;
		foreach (ch; token[1 .. $])
		{
			if (ch < '0' || ch > '9')
			{
				digits = false;
				break;
			}
			n = n * 10 + (ch - '0');
		}
		if (digits && n >= 1 && n <= 24)
		{
			vk = cast(ushort)(VK_F1 + (n - 1));
			return true;
		}
	}

	static struct Named { string name; ushort vk; }
	static immutable Named[] names = [
		Named("up", VK_UP), Named("down", VK_DOWN),
		Named("left", VK_LEFT), Named("right", VK_RIGHT),
		Named("home", VK_HOME), Named("end", VK_END),
		Named("pageup", VK_PRIOR), Named("pagedown", VK_NEXT),
		Named("insert", VK_INSERT), Named("delete", VK_DELETE),
		Named("del", VK_DELETE), Named("space", VK_SPACE),
		Named("tab", VK_TAB), Named("enter", VK_RETURN),
		Named("return", VK_RETURN), Named("escape", VK_ESCAPE),
		Named("esc", VK_ESCAPE), Named("backspace", VK_BACK),
	];
	foreach (n; names)
		if (asciiEquals(token, n.name))
		{
			vk = n.vk;
			return true;
		}

	return false;
}

/**
 * Parse an accelerator string such as `"Ctrl+Shift+N"` or `"F5"`.
 *
 * Recognizes the `Ctrl`/`Control`, `Alt` and `Shift` modifiers (in any order
 * and case), letter and digit keys, function keys `F1`–`F24`, and the common
 * named keys (`Up`, `Delete`, `Enter`, …). Returns a result with `valid` false
 * for an empty or unrecognized string.
 */
Accelerator parseAccelerator(string spec)
{
	Accelerator result;
	if (spec.length == 0)
		return result;

	auto parts = splitOnPlus(spec);
	if (parts.length == 0)
		return result;

	ubyte fVirt = 0;
	foreach (mod; parts[0 .. $ - 1])
	{
		if (asciiEquals(mod, "ctrl") || asciiEquals(mod, "control"))
			fVirt |= FCONTROL;
		else if (asciiEquals(mod, "shift"))
			fVirt |= FSHIFT;
		else if (asciiEquals(mod, "alt"))
			fVirt |= FALT;
		else
			return result; // unknown modifier
	}

	ushort vk;
	if (!keyTokenToVk(parts[$ - 1], vk))
		return result;

	result.valid = true;
	result.fVirt = fVirt;
	result.key = vk;
	return result;
}

unittest
{
	// A single letter with one modifier.
	auto a = parseAccelerator("Ctrl+N");
	assert(a.valid);
	assert(a.fVirt == FCONTROL);
	assert(a.key == 'N');
}

unittest
{
	// Two modifiers, any case.
	auto a = parseAccelerator("ctrl+shift+n");
	assert(a.valid);
	assert(a.fVirt == (FCONTROL | FSHIFT));
	assert(a.key == 'N');
}

unittest
{
	// Alt + Shift with a named arrow key.
	auto a = parseAccelerator("Alt+Shift+Up");
	assert(a.valid);
	assert(a.fVirt == (FALT | FSHIFT));
	assert(a.key == VK_UP);
}

unittest
{
	// A bare function key, no modifiers.
	auto f1 = parseAccelerator("F1");
	assert(f1.valid);
	assert(f1.fVirt == 0);
	assert(f1.key == VK_F1);

	// A modified function key.
	auto sf1 = parseAccelerator("Shift+F1");
	assert(sf1.valid);
	assert(sf1.fVirt == FSHIFT);
	assert(sf1.key == VK_F1);

	// Two-digit function key.
	auto f12 = parseAccelerator("F12");
	assert(f12.valid);
	assert(f12.key == VK_F1 + 11);
}

unittest
{
	// Punctuation key.
	auto comma = parseAccelerator("Ctrl+,");
	assert(comma.valid);
	assert(comma.fVirt == FCONTROL);
	assert(comma.key == VK_OEM_COMMA);
}

unittest
{
	// Empty and malformed strings are rejected, not crashed on.
	assert(!parseAccelerator("").valid);
	assert(!parseAccelerator("Ctrl+").valid);
	assert(!parseAccelerator("Frobnicate+Q").valid);
	assert(!parseAccelerator("Ctrl+Nonsense").valid);
}

unittest
{
	// Generated ids are unique and monotonic.
	auto a = nextMenuId();
	auto b = nextMenuId();
	assert(b == a + 1);
	assert(a >= 30_000);
}

unittest
{
	// buildAcceleratorTable collects one ACCEL per accelerator-bearing item across
	// the whole bar (including submenus) and ignores items without one. These APIs
	// (CreateMenu/AppendMenu/CreateAcceleratorTable) need no window or message loop.
	auto bar = new MenuBar();
	auto file = new Menu();
	file.append(MenuItem(0, "&New", "Ctrl+N"));
	file.append(MenuItem(0, "&Open", "Ctrl+O"));
	file.append(MenuItem(0, "&Close")); // no accelerator
	auto sub = new Menu();
	sub.append(MenuItem(0, "&Recent", "Ctrl+R"));
	file.appendSubmenu(sub, "Recen&t");
	bar.append(file, "&File");

	HACCEL table = bar.buildAcceleratorTable();
	assert(table !is null);
	// CopyAcceleratorTableW with a null buffer returns the entry count.
	assert(CopyAcceleratorTableW(table, null, 0) == 3);
	DestroyAcceleratorTable(table);

	// A bar with no accelerator-bearing items yields a null table.
	auto plain = new MenuBar();
	auto edit = new Menu();
	edit.append(MenuItem(0, "&Undo"));
	plain.append(edit, "&Edit");
	assert(plain.buildAcceleratorTable() is null);
}
