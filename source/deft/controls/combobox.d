/**
 * Native combo box control.
 *
 * `ComboBox` wraps the Win32 `"ComboBox"` window class. It supports three
 * interaction styles (see `ComboBoxStyle`): a non-editable drop-down list, an
 * editable drop-down, and an always-open simple list with an editable field.
 * It exposes item management (add / insert / remove / clear), selection access,
 * per-item user data, and delegate-based events for selection and text changes.
 */
module deft.controls.combobox;

version (Windows):

import core.sys.windows.windows;

import deft.controls.control;
import deft.events;
import deft.util.strings;
import deft.widget;

/// The interaction style of a combo box.
enum ComboBoxStyle
{
	/// A non-editable dropdown: the user can only pick an existing item.
	dropDownList,
	/// An editable dropdown: the user can pick an item or type a new value.
	dropDown,
	/// An always-open list with an editable field above it.
	simple,
}

/// A native Win32 combo box of selectable string items.
class ComboBox : Control
{
	/// Fired when the selection changes; carries the new selected index.
	Event!(int) onSelectionChanged;

	/// Fired when the editable text changes; carries the new text.
	Event!(string) onTextChanged;

	private ComboBoxStyle style_;
	private bool editable_;

	/**
	 * Create a combo box as a child of `parent`.
	 *
	 * The `style` selects the interaction model: `dropDownList` (a non-editable
	 * drop-down list, the default), `dropDown` (an editable drop-down), or
	 * `simple` (an always-open list with an editable field). All styles get a
	 * vertical scroll bar for the list and a tab stop for keyboard navigation.
	 */
	this(Widget parent, ComboBoxStyle style = ComboBoxStyle.dropDownList)
	{
		// super() must be the first statement, so the style is computed by a
		// helper rather than with a switch in the constructor body.
		super(parent, "ComboBox", win32StyleFor(style));
		style_ = style;
		editable_ = style == ComboBoxStyle.dropDown || style == ComboBoxStyle.simple;
		subclass();
	}

	/// Map a `ComboBoxStyle` to its Win32 window style bits.
	private static DWORD win32StyleFor(ComboBoxStyle style)
	{
		DWORD win32Style = WS_VSCROLL | WS_TABSTOP;
		final switch (style)
		{
			case ComboBoxStyle.dropDownList:
				return win32Style | CBS_DROPDOWNLIST;
			case ComboBoxStyle.dropDown:
				return win32Style | CBS_DROPDOWN;
			case ComboBoxStyle.simple:
				return win32Style | CBS_SIMPLE;
		}
	}

	/// Append `text` to the end of the list; returns the new item's index.
	int addItem(string text)
	{
		return cast(int) SendMessageW(handle, CB_ADDSTRING, 0,
			cast(LPARAM) text.toWStringz);
	}

	/// Insert `text` at `index`, shifting later items down.
	void insertItem(int index, string text)
	{
		SendMessageW(handle, CB_INSERTSTRING, index, cast(LPARAM) text.toWStringz);
	}

	/// Remove the item at `index`.
	void removeItem(int index)
	{
		SendMessageW(handle, CB_DELETESTRING, index, 0);
	}

	/// Remove all items.
	void clear()
	{
		SendMessageW(handle, CB_RESETCONTENT, 0, 0);
	}

	/// Return the selected item's index, or -1 (`CB_ERR`) if none is selected.
	int getSelectedIndex()
	{
		return cast(int) SendMessageW(handle, CB_GETCURSEL, 0, 0);
	}

	/// Select the item at `index` (pass -1 to clear the selection).
	void setSelectedIndex(int index)
	{
		SendMessageW(handle, CB_SETCURSEL, index, 0);
	}

	/// Return the number of items in the list.
	int getItemCount()
	{
		return cast(int) SendMessageW(handle, CB_GETCOUNT, 0, 0);
	}

	/// Return the text of the item at `index`, or `""` if it has none.
	string getItemText(int index)
	{
		int len = cast(int) SendMessageW(handle, CB_GETLBTEXTLEN, index, 0);
		if (len <= 0)
			return "";

		auto buf = new wchar[len + 1];
		int got = cast(int) SendMessageW(handle, CB_GETLBTEXT, index,
			cast(LPARAM) buf.ptr);
		return fromWString(buf[0 .. got]);
	}

	/// Associate an opaque `data` pointer with the item at `index`.
	void setItemData(int index, void* data)
	{
		SendMessageW(handle, CB_SETITEMDATA, index, cast(LPARAM) data);
	}

	/// Return the opaque pointer previously stored for the item at `index`.
	void* getItemData(int index)
	{
		return cast(void*) SendMessageW(handle, CB_GETITEMDATA, index, 0);
	}

	/**
	 * Route a `WM_COMMAND` notification. Fires `onSelectionChanged` on
	 * `CBN_SELCHANGE` and `onTextChanged` on `CBN_EDITCHANGE` (the latter is
	 * only meaningful for the editable styles).
	 */
	override bool processCommand(ushort code)
	{
		switch (code)
		{
			case CBN_SELCHANGE:
				onSelectionChanged.fire(getSelectedIndex());
				return true;
			case CBN_EDITCHANGE:
				onTextChanged.fire(getText());
				return true;
			default:
				return false;
		}
	}

	/**
	 * Auto-select the first item when a non-editable drop-down list receives
	 * focus, so a screen reader announces an item as the user tabs in. Never
	 * consumes the focus message.
	 */
	override bool processSubclassed(UINT msg, WPARAM wParam, LPARAM lParam,
		ref LRESULT result)
	{
		if (msg == WM_SETFOCUS
			&& style_ == ComboBoxStyle.dropDownList
			&& getSelectedIndex() < 0
			&& getItemCount() > 0)
			setSelectedIndex(0);

		return false;
	}

	/// A sensible default size for a combo box.
	override Size getPreferredSize()
	{
		if (style_ == ComboBoxStyle.simple)
			return Size(200, 120);

		return Size(200, 26);
	}
}
