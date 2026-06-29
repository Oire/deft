/**
 * Native report-mode list view (`SysListView32`).
 *
 * `ListView` wraps the Win32 list-view common control in report (details) mode:
 * a grid of rows and columns with single selection, full-row select, grid lines
 * and a clickable header. It exposes column and item management, selection,
 * per-item user data, column ordering, and delegate-based events for selection
 * changes, activation (double-click / Enter) and context-menu requests. Because
 * it is a real native control, it brings MSAA accessibility for free.
 */
module deft.controls.listview;

version (Windows):

import core.sys.windows.windows;
import core.sys.windows.commctrl;

import deft.controls.control;
import deft.events;
import deft.util.strings;
import deft.widget;

/// Horizontal alignment for a list-view column's text.
enum ColumnAlign
{
	/// Left-aligned (`LVCFMT_LEFT`).
	left,
	/// Center-aligned (`LVCFMT_CENTER`).
	center,
	/// Right-aligned (`LVCFMT_RIGHT`).
	right,
}

/**
 * How a column should auto-size itself to fit, for `ListView.autoSizeColumn`.
 *
 * This is the analog of WinForms' negative column-width sentinels: `content`
 * matches `-1` (fit the data) and `header` matches `-2` (fit the header text).
 */
enum ColumnAutoSize
{
	/// Fit the widest cell in the column (`LVSCW_AUTOSIZE`; WinForms `-1`).
	content,
	/**
	 * Fit the header text (`LVSCW_AUTOSIZE_USEHEADER`; WinForms `-2`). Applied to
	 * the *last* column the native control instead stretches it to fill the list's
	 * remaining width — the usual way to make a final column absorb the slack.
	 */
	header,
}

/// Map a `ColumnAlign` to its `LVCFMT_*` flag.
private int columnAlignFmt(ColumnAlign align_) @safe pure nothrow @nogc
{
	final switch (align_)
	{
		case ColumnAlign.left:
			return LVCFMT_LEFT;
		case ColumnAlign.center:
			return LVCFMT_CENTER;
		case ColumnAlign.right:
			return LVCFMT_RIGHT;
	}
}

/// A native list view in report (details) mode.
class ListView : Control
{
	private int columnCount_;

	/// Keeps GC-allocated item data reachable; see `setItemData`.
	private void*[] retainedData_;

	/// Fired when the selected row changes; argument is the new selected index.
	Event!(int) onSelectionChanged;
	/// Fired when a row is activated (double-click or Enter); argument is the row index.
	Event!(int) onItemActivated;
	/**
	 * Fired when a context menu is requested, carrying the relevant row index
	 * (-1 if none) and the screen position to show the menu at. Raised both by a
	 * mouse right-click (row under the cursor) and by the keyboard — the Apps key
	 * or Shift+F10 — in which case the row is the selected one and the position is
	 * anchored to it. The screen coordinates can be passed to `showPopupMenu`.
	 */
	Event!(int, MouseEventArgs) onContextMenu;

	/**
	 * Create a report-mode list view as a child of `parent`.
	 *
	 * The control is single-select, always shows the selection, takes part in tab
	 * navigation and has a border. Full-row selection and grid lines are enabled.
	 */
	this(Widget parent)
	{
		super(parent, "SysListView32",
			LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_TABSTOP | WS_BORDER);

		SendMessageW(handle, LVM_SETEXTENDEDLISTVIEWSTYLE, 0,
			LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES);

		// Subclass so WM_CONTEXTMENU (mouse right-click and the Apps/Shift+F10
		// keys) can be turned into onContextMenu — keyboard access is essential.
		subclass();
	}

	/**
	 * Append a column with the given header `title`, pixel `width` and text
	 * alignment. Returns the new column's index.
	 */
	int addColumn(string title, int width, ColumnAlign align_ = ColumnAlign.left)
	{
		LVCOLUMNW col;
		col.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_FMT | LVCF_SUBITEM;
		col.fmt = columnAlignFmt(align_);
		col.cx = width;
		col.pszText = cast(LPWSTR) title.toWStringz;
		col.iSubItem = columnCount_;

		SendMessageW(handle, LVM_INSERTCOLUMNW, columnCount_, cast(LPARAM)&col);
		return columnCount_++;
	}

	/// Change the header text of column `col` (e.g. when the UI language changes).
	void setColumnTitle(int col, string title)
	{
		LVCOLUMNW c;
		c.mask = LVCF_TEXT;
		c.pszText = cast(LPWSTR) title.toWStringz;
		SendMessageW(handle, LVM_SETCOLUMNW, col, cast(LPARAM)&c);
	}

	/// Set the pixel width of column `col`. For autosizing, use `autoSizeColumn`.
	void setColumnWidth(int col, int width)
	{
		SendMessageW(handle, LVM_SETCOLUMNWIDTH, col, width);
	}

	/**
	 * Size column `col` to fit its content (`ColumnAutoSize.content`) or its header
	 * text (`ColumnAutoSize.header`) — the equivalents of WinForms' `-1` and `-2`
	 * column widths.
	 *
	 * This is a *one-shot* measurement of the column's current contents, not a
	 * persistent mode: call it **after** the rows are populated, and again if the
	 * data changes. As a special case, `ColumnAutoSize.header` on the last column
	 * stretches that column to fill the list's remaining width, so a common recipe
	 * is fixed/auto widths for the leading columns and `header` on the last.
	 */
	void autoSizeColumn(int col, ColumnAutoSize mode = ColumnAutoSize.content)
	{
		immutable int sentinel = mode == ColumnAutoSize.header
			? LVSCW_AUTOSIZE_USEHEADER : LVSCW_AUTOSIZE;
		SendMessageW(handle, LVM_SETCOLUMNWIDTH, col, sentinel);
	}

	/// Get the pixel width of column `col`.
	int getColumnWidth(int col)
	{
		return cast(int) SendMessageW(handle, LVM_GETCOLUMNWIDTH, col, 0);
	}

	/**
	 * Append a row. `cells[0]` is the main item text; `cells[1 .. $]` fill the
	 * subsequent columns. Returns the new row index, or -1 if `cells` is empty.
	 */
	int addItem(string[] cells)
	{
		if (cells.length == 0)
			return -1;

		LVITEMW item;
		item.mask = LVIF_TEXT;
		item.iItem = getItemCount();
		item.iSubItem = 0;
		item.pszText = cast(LPWSTR) cells[0].toWStringz;

		int row = cast(int) SendMessageW(handle, LVM_INSERTITEMW, 0, cast(LPARAM)&item);

		foreach (c; 1 .. cells.length)
		{
			LVITEMW sub;
			sub.iSubItem = cast(int) c;
			sub.pszText = cast(LPWSTR) cells[c].toWStringz;
			SendMessageW(handle, LVM_SETITEMTEXTW, row, cast(LPARAM)&sub);
		}

		return row;
	}

	/// Remove all rows (and release any retained item data; see `setItemData`).
	void clear()
	{
		SendMessageW(handle, LVM_DELETEALLITEMS, 0, 0);
		retainedData_ = null;
	}

	/// Return the number of rows.
	int getItemCount()
	{
		return cast(int) SendMessageW(handle, LVM_GETITEMCOUNT, 0, 0);
	}

	/// Return the index of the selected row, or -1 if nothing is selected.
	int getSelectedIndex()
	{
		return cast(int) SendMessageW(handle, LVM_GETNEXTITEM, cast(WPARAM)-1, LVNI_SELECTED);
	}

	/// Select (and focus) the row at `index`.
	void setSelectedIndex(int index)
	{
		LVITEMW item;
		item.state = LVIS_SELECTED | LVIS_FOCUSED;
		item.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
		SendMessageW(handle, LVM_SETITEMSTATE, index, cast(LPARAM)&item);
	}

	/// Scroll the row at `index` into view.
	void ensureVisible(int index)
	{
		SendMessageW(handle, LVM_ENSUREVISIBLE, index, FALSE);
	}

	/// Return the text of the cell at the given `row` and `col`.
	string getItemText(int row, int col)
	{
		// LVM_GETITEMTEXTW returns the number of characters copied; a result that
		// fills the buffer (cap-1) may have been truncated, so grow and retry.
		for (int cap = 256;; cap *= 2)
		{
			auto buf = new wchar[cap];
			LVITEMW item;
			item.iSubItem = col;
			item.pszText = buf.ptr;
			item.cchTextMax = cap;
			int got = cast(int) SendMessageW(handle, LVM_GETITEMTEXTW, row,
				cast(LPARAM)&item);
			if (got < cap - 1 || cap >= 1 << 16)
				return fromWString(buf[0 .. got]);
		}
	}

	/**
	 * Associate an opaque user pointer with the row at `index`.
	 *
	 * The pointer is stored inside the native control, where the D garbage
	 * collector cannot see it. To keep GC-allocated `data` from being collected
	 * out from under the control, Deft also retains a reference internally for the
	 * control's lifetime; the retained references are released by `clear()`. (The
	 * native control owns the canonical copy returned by `getItemData`.)
	 */
	void setItemData(int index, void* data)
	{
		if (data !is null)
			retainedData_ ~= data;
		LVITEMW item;
		item.mask = LVIF_PARAM;
		item.iItem = index;
		item.lParam = cast(LPARAM) data;
		SendMessageW(handle, LVM_SETITEM, 0, cast(LPARAM)&item);
	}

	/// Retrieve the user pointer associated with the row at `index`.
	void* getItemData(int index)
	{
		LVITEMW item;
		item.mask = LVIF_PARAM;
		item.iItem = index;
		SendMessageW(handle, LVM_GETITEM, 0, cast(LPARAM)&item);
		return cast(void*) item.lParam;
	}

	/// Set the left-to-right display order of the columns.
	void setColumnsOrder(int[] order)
	{
		SendMessageW(handle, LVM_SETCOLUMNORDERARRAY, order.length, cast(LPARAM) order.ptr);
	}

	/// Get the current left-to-right display order of the columns.
	int[] getColumnsOrder()
	{
		auto arr = new int[columnCount_];
		SendMessageW(handle, LVM_GETCOLUMNORDERARRAY, columnCount_, cast(LPARAM) arr.ptr);
		return arr;
	}

	/// Route list-view selection and activation notifications to their events.
	override bool processNotify(NMHDR* header)
	{
		switch (header.code)
		{
			case LVN_ITEMCHANGED:
				auto nm = cast(NMLISTVIEW*) header;
				if ((nm.uChanged & LVIF_STATE)
					&& (nm.uNewState & LVIS_SELECTED)
					&& !(nm.uOldState & LVIS_SELECTED))
					onSelectionChanged.fire(nm.iItem);
				return true;

			case LVN_ITEMACTIVATE:
				auto nm = cast(NMITEMACTIVATE*) header;
				onItemActivated.fire(nm.iItem);
				return true;

			default:
				return false;
		}
	}

	/**
	 * Turn `WM_CONTEXTMENU` into `onContextMenu`. The message is raised by a
	 * right-click and by the keyboard (Apps key / Shift+F10); the latter arrives
	 * with a position of `(-1, -1)`, in which case the menu is anchored at the
	 * selected row so a keyboard user gets the menu where focus is.
	 */
	override bool processSubclassed(UINT msg, WPARAM wParam, LPARAM lParam,
		ref LRESULT result)
	{
		// On keyboard focus with nothing selected, select the first row so a
		// screen reader announces an item instead of silence.
		if (msg == WM_SETFOCUS)
		{
			if (getSelectedIndex() < 0 && getItemCount() > 0)
				setSelectedIndex(0);
			return false;
		}

		if (msg != WM_CONTEXTMENU)
			return false;

		immutable short sx = cast(short)(lParam & 0xFFFF);
		immutable short sy = cast(short)((lParam >> 16) & 0xFFFF);

		int index;
		int x, y;
		if (sx == -1 && sy == -1)
		{
			// Keyboard: anchor at the selected row (or the control's corner).
			index = getSelectedIndex();
			POINT pt;
			RECT rc;
			rc.left = LVIR_LABEL;
			if (index >= 0
				&& SendMessageW(handle, LVM_GETITEMRECT, index, cast(LPARAM)&rc))
			{
				pt.x = rc.left;
				pt.y = rc.bottom;
			}
			ClientToScreen(handle, &pt);
			x = pt.x;
			y = pt.y;
		}
		else
		{
			// Mouse: hit-test the click point to find the row under the cursor.
			x = sx;
			y = sy;
			POINT pt = POINT(sx, sy);
			ScreenToClient(handle, &pt);
			LVHITTESTINFO ht;
			ht.pt = pt;
			index = cast(int) SendMessageW(handle, LVM_HITTEST, 0, cast(LPARAM)&ht);
		}

		onContextMenu.fire(index, MouseEventArgs(x, y, MouseButton.right));
		result = 0;
		return true;
	}

	/// A sensible default size for a report-mode list.
	override Size getPreferredSize()
	{
		return Size(300, 200);
	}
}
