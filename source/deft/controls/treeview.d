/**
 * A hierarchical tree view (`"SysTreeView32"`).
 *
 * `TreeView` wraps the Win32 tree-view common control, exposing root and child
 * node insertion, selection get/set, per-item text and user data, and delegate
 * events for selection changes and context-menu (right-click) requests. Nodes
 * are referred to by the opaque `TreeItem` handle returned at insertion time.
 */
module deft.controls.treeview;

version (Windows):

import core.sys.windows.windows;
import core.sys.windows.commctrl;

import deft.controls.control;
import deft.events;
import deft.util.strings;
import deft.widget;

/// Opaque handle to a tree node.
struct TreeItem
{
	/// The underlying Win32 tree-item handle.
	HTREEITEM handle;

	/// Whether this handle refers to no node.
	bool isNull() const { return handle is null; }

	/// Two `TreeItem`s are equal when they wrap the same handle.
	bool opEquals(const TreeItem other) const { return handle is other.handle; }
}

/// A hierarchical tree of selectable, expandable nodes.
class TreeView : Control
{
	/// Fired when the selected node changes, carrying the newly selected item.
	Event!(TreeItem) onSelectionChanged;

	/**
	 * Fired when a context menu is requested, carrying the relevant item and the
	 * screen position to show the menu at. Raised both by a mouse right-click
	 * (item under the cursor) and by the keyboard — the Apps key or Shift+F10 —
	 * in which case the item is the selected node and the position is anchored to
	 * it. The screen coordinates can be passed straight to `showPopupMenu`.
	 */
	Event!(TreeItem, MouseEventArgs) onContextMenu;

	/// Create a tree view inside `parent`.
	this(Widget parent)
	{
		super(parent, "SysTreeView32",
			TVS_HASLINES | TVS_LINESATROOT | TVS_HASBUTTONS |
			TVS_SHOWSELALWAYS | WS_TABSTOP | WS_BORDER);
		// Subclass so WM_CONTEXTMENU (mouse right-click and the Apps/Shift+F10
		// keys) can be turned into onContextMenu — keyboard access is essential.
		subclass();
	}

	/// Insert a node captioned `text` as the last child of `parent`.
	private TreeItem insert(HTREEITEM parent, string text)
	{
		TVINSERTSTRUCTW tis;
		tis.hParent = parent;
		tis.hInsertAfter = TVI_LAST;
		tis.item.mask = TVIF_TEXT;
		tis.item.pszText = cast(LPWSTR) text.toWStringz;

		auto h = cast(HTREEITEM) SendMessageW(handle, TVM_INSERTITEMW, 0,
			cast(LPARAM)&tis);
		return TreeItem(h);
	}

	/// Add a top-level node captioned `text`.
	TreeItem addRoot(string text)
	{
		return insert(TVI_ROOT, text);
	}

	/// Add a node captioned `text` as the last child of `parent`.
	TreeItem addChild(TreeItem parent, string text)
	{
		return insert(parent.handle, text);
	}

	/// Remove every node from the tree.
	void clear()
	{
		SendMessageW(handle, TVM_DELETEITEM, 0, cast(LPARAM) TVI_ROOT);
	}

	/// Get the currently selected node (a null `TreeItem` if none).
	TreeItem getSelectedItem()
	{
		auto h = cast(HTREEITEM) SendMessageW(handle, TVM_GETNEXTITEM,
			TVGN_CARET, 0);
		return TreeItem(h);
	}

	/// Get the first top-level node (a null `TreeItem` if the tree is empty).
	TreeItem getFirstRoot()
	{
		auto h = cast(HTREEITEM) SendMessageW(handle, TVM_GETNEXTITEM,
			TVGN_ROOT, 0);
		return TreeItem(h);
	}

	/// Select `item`.
	void setSelectedItem(TreeItem item)
	{
		SendMessageW(handle, TVM_SELECTITEM, TVGN_CARET, cast(LPARAM) item.handle);
	}

	/// Get the caption text of `item`.
	string getItemText(TreeItem item)
	{
		auto buf = new wchar[512];
		TVITEMW tv;
		tv.mask = TVIF_TEXT;
		tv.hItem = item.handle;
		tv.pszText = buf.ptr;
		tv.cchTextMax = cast(int) buf.length;
		SendMessageW(handle, TVM_GETITEMW, 0, cast(LPARAM)&tv);
		return fromWStringz(buf.ptr);
	}

	/// Associate an opaque `data` pointer with `item`.
	void setItemData(TreeItem item, void* data)
	{
		TVITEMW tv;
		tv.mask = TVIF_PARAM;
		tv.hItem = item.handle;
		tv.lParam = cast(LPARAM) data;
		SendMessageW(handle, TVM_SETITEMW, 0, cast(LPARAM)&tv);
	}

	/// Retrieve the opaque pointer previously stored with `setItemData`.
	void* getItemData(TreeItem item)
	{
		TVITEMW tv;
		tv.mask = TVIF_PARAM;
		tv.hItem = item.handle;
		SendMessageW(handle, TVM_GETITEMW, 0, cast(LPARAM)&tv);
		return cast(void*) tv.lParam;
	}

	/// Expand `item` to reveal its children.
	void expandItem(TreeItem item)
	{
		SendMessageW(handle, TVM_EXPAND, TVE_EXPAND, cast(LPARAM) item.handle);
	}

	/// Translate tree-view selection-change notifications into events.
	override bool processNotify(NMHDR* header)
	{
		if (header.code == TVN_SELCHANGEDW)
		{
			auto nm = cast(NMTREEVIEWW*) header;
			onSelectionChanged.fire(TreeItem(nm.itemNew.hItem));
			return true;
		}
		return false;
	}

	/**
	 * Turn `WM_CONTEXTMENU` into `onContextMenu`. The message is raised by a
	 * right-click and by the keyboard (Apps key / Shift+F10); the latter arrives
	 * with a position of `(-1, -1)`, in which case the menu is anchored at the
	 * selected node so a keyboard user gets the menu where focus is.
	 */
	override bool processSubclassed(UINT msg, WPARAM wParam, LPARAM lParam,
		ref LRESULT result)
	{
		// On keyboard focus with nothing selected, select the first root node so
		// a screen reader announces an item instead of silence.
		if (msg == WM_SETFOCUS)
		{
			if (getSelectedItem().isNull)
			{
				auto first = getFirstRoot();
				if (!first.isNull)
					setSelectedItem(first);
			}
			return false;
		}

		if (msg != WM_CONTEXTMENU)
			return false;

		immutable short sx = cast(short)(lParam & 0xFFFF);
		immutable short sy = cast(short)((lParam >> 16) & 0xFFFF);

		TreeItem item;
		int x, y;
		if (sx == -1 && sy == -1)
		{
			// Keyboard: anchor at the selected node (or the control's corner).
			item = getSelectedItem();
			POINT pt;
			if (!item.isNull)
			{
				RECT rc;
				*(cast(HTREEITEM*)&rc) = item.handle;
				if (SendMessageW(handle, TVM_GETITEMRECT, TRUE, cast(LPARAM)&rc))
				{
					pt.x = rc.left;
					pt.y = rc.bottom;
				}
			}
			ClientToScreen(handle, &pt);
			x = pt.x;
			y = pt.y;
		}
		else
		{
			// Mouse: hit-test the click point to find the item under the cursor.
			x = sx;
			y = sy;
			POINT pt = POINT(sx, sy);
			ScreenToClient(handle, &pt);
			TVHITTESTINFO ht;
			ht.pt = pt;
			item = TreeItem(cast(HTREEITEM) SendMessageW(handle, TVM_HITTEST, 0,
				cast(LPARAM)&ht));
		}

		onContextMenu.fire(item, MouseEventArgs(x, y, MouseButton.right));
		result = 0;
		return true;
	}

	/// Tree views prefer a generously sized box.
	override Size getPreferredSize()
	{
		return Size(200, 200);
	}
}
