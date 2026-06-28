/**
 * Native list box control.
 *
 * `ListBox` wraps the Win32 `"ListBox"` window class: a scrollable, single-column
 * list of selectable string items. It exposes item management (add / insert /
 * remove / clear), selection access, per-item user data, and delegate-based
 * events for selection changes and item activation (double-click).
 */
module deft.controls.listbox;

version (Windows):

import core.sys.windows.windows;

import deft.controls.control;
import deft.events;
import deft.util.strings;
import deft.widget;

/// How many items a list box lets the user select at once.
enum ListBoxSelection
{
	/// One item at a time.
	single,
	/// Several items via click/space toggling.
	multiple,
	/// A contiguous or ctrl-extended range (Shift/Ctrl+click).
	extended,
}

/// A native Win32 list box: a scrollable column of selectable string items.
class ListBox : Control
{
	/// Fired when the selection changes; carries the new selected index.
	Event!(int) onSelectionChanged;

	/// Fired when an item is activated (double-clicked); carries its index.
	Event!(int) onItemActivated;

	private ListBoxSelection selection_;

	/**
	 * Create a list box as a child of `parent`.
	 *
	 * The control is created with `LBS_NOTIFY` (so it reports selection and
	 * double-click notifications), `LBS_HASSTRINGS`, a vertical scroll bar, a
	 * border, and a tab stop for keyboard navigation. `selection` chooses the
	 * selection mode: `single` (one item), `multiple` (toggle several with
	 * click/space), or `extended` (Shift/Ctrl+click ranges).
	 */
	this(Widget parent, ListBoxSelection selection = ListBoxSelection.single)
	{
		// super() must be the first statement, so the style is computed by a
		// helper rather than with a switch in the constructor body.
		super(parent, "ListBox", win32StyleFor(selection));
		selection_ = selection;
		subclass();
	}

	/// Map a `ListBoxSelection` to its Win32 window style bits.
	private static DWORD win32StyleFor(ListBoxSelection selection)
	{
		DWORD style =
			LBS_NOTIFY | LBS_HASSTRINGS | WS_VSCROLL | WS_BORDER | WS_TABSTOP;
		final switch (selection)
		{
			case ListBoxSelection.single:
				return style;
			case ListBoxSelection.multiple:
				return style | LBS_MULTIPLESEL;
			case ListBoxSelection.extended:
				return style | LBS_EXTENDEDSEL;
		}
	}

	/// Append `text` to the end of the list; returns the new item's index.
	int addItem(string text)
	{
		return cast(int) SendMessageW(handle, LB_ADDSTRING, 0,
			cast(LPARAM) text.toWStringz);
	}

	/// Insert `text` at `index`, shifting later items down.
	void insertItem(int index, string text)
	{
		SendMessageW(handle, LB_INSERTSTRING, index, cast(LPARAM) text.toWStringz);
	}

	/// Remove the item at `index`.
	void removeItem(int index)
	{
		SendMessageW(handle, LB_DELETESTRING, index, 0);
	}

	/// Remove all items.
	void clear()
	{
		SendMessageW(handle, LB_RESETCONTENT, 0, 0);
	}

	/// Return the selected item's index, or -1 (`LB_ERR`) if none is selected.
	int getSelectedIndex()
	{
		return cast(int) SendMessageW(handle, LB_GETCURSEL, 0, 0);
	}

	/// Select the item at `index` (pass -1 to clear the selection).
	void setSelectedIndex(int index)
	{
		SendMessageW(handle, LB_SETCURSEL, index, 0);
	}

	/**
	 * Return the indices of every selected item, or `null` if none are selected.
	 *
	 * Only meaningful for `multiple` and `extended` list boxes; on a `single`
	 * list box the underlying messages report no selection.
	 */
	int[] getSelectedIndices()
	{
		int count = cast(int) SendMessageW(handle, LB_GETSELCOUNT, 0, 0);
		if (count <= 0)
			return null;

		auto buf = new int[count];
		SendMessageW(handle, LB_GETSELITEMS, cast(WPARAM) count,
			cast(LPARAM) buf.ptr);
		return buf;
	}

	/**
	 * Select or deselect the item at `index`.
	 *
	 * Only meaningful for `multiple` and `extended` list boxes; use
	 * `setSelectedIndex` for `single` list boxes.
	 */
	void setItemSelected(int index, bool selected)
	{
		SendMessageW(handle, LB_SETSEL, selected ? TRUE : FALSE,
			cast(LPARAM) index);
	}

	/// Return the number of items in the list.
	int getItemCount()
	{
		return cast(int) SendMessageW(handle, LB_GETCOUNT, 0, 0);
	}

	/// Return the text of the item at `index`, or `""` if it has none.
	string getItemText(int index)
	{
		int len = cast(int) SendMessageW(handle, LB_GETTEXTLEN, index, 0);
		if (len <= 0)
			return "";

		auto buf = new wchar[len + 1];
		int got = cast(int) SendMessageW(handle, LB_GETTEXT, index,
			cast(LPARAM) buf.ptr);
		return fromWString(buf[0 .. got]);
	}

	/// Associate an opaque `data` pointer with the item at `index`.
	void setItemData(int index, void* data)
	{
		SendMessageW(handle, LB_SETITEMDATA, index, cast(LPARAM) data);
	}

	/// Return the opaque pointer previously stored for the item at `index`.
	void* getItemData(int index)
	{
		return cast(void*) SendMessageW(handle, LB_GETITEMDATA, index, 0);
	}

	/**
	 * Route a `WM_COMMAND` notification. Fires `onSelectionChanged` on
	 * `LBN_SELCHANGE` and `onItemActivated` on `LBN_DBLCLK`.
	 */
	override bool processCommand(ushort code)
	{
		switch (code)
		{
			case LBN_SELCHANGE:
				onSelectionChanged.fire(getSelectedIndex());
				return true;
			case LBN_DBLCLK:
				onItemActivated.fire(getSelectedIndex());
				return true;
			default:
				return false;
		}
	}

	/**
	 * Auto-select the first item when a single-select list box gains focus and
	 * nothing is selected yet, so a screen reader announces an item on tab-in.
	 * Focus messages are never consumed.
	 */
	override bool processSubclassed(UINT msg, WPARAM wParam, LPARAM lParam,
		ref LRESULT result)
	{
		if (msg == WM_SETFOCUS
			&& selection_ == ListBoxSelection.single
			&& getSelectedIndex() < 0
			&& getItemCount() > 0)
			setSelectedIndex(0);

		return false;
	}

	/// A sensible default size for a list box.
	override Size getPreferredSize()
	{
		return Size(200, 120);
	}
}
