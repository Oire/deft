/**
 * Native checked list box (`SysListView32` with checkboxes).
 *
 * `CheckListBox` wraps the Win32 list-view common control in list mode with the
 * checkbox extended style: a single-column list where every item carries its own
 * checkbox that can be toggled independently of the selection. It exposes item
 * management, per-item checked state, single selection and delegate-based events
 * for check toggles and selection changes. Because it is a real native control,
 * it brings MSAA accessibility for free.
 *
 * Win32 stores the per-item checkbox in the "state image" bits of the item state
 * (mask `LVIS_STATEIMAGEMASK`): state-image index 1 means unchecked and index 2
 * means checked.
 */
module deft.controls.checklistbox;

version (Windows):

import core.sys.windows.windows;
import core.sys.windows.commctrl;

import deft.controls.control;
import deft.events;
import deft.util.strings;
import deft.widget;

/// A native list of items, each with its own checkbox.
class CheckListBox : Control
{
	/// Fired when an item's checkbox is toggled; argument is the item index.
	Event!(int) onItemChecked;
	/// Fired when the selected item changes; argument is the new selected index.
	Event!(int) onSelectionChanged;

	/**
	 * Create a checked list box as a child of `parent`.
	 *
	 * The control is single-select, always shows the selection, takes part in tab
	 * navigation and has a border. Checkboxes are enabled via the
	 * `LVS_EX_CHECKBOXES` extended style.
	 */
	this(Widget parent)
	{
		super(parent, "SysListView32",
			LVS_LIST | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_TABSTOP | WS_BORDER);

		SendMessageW(handle, LVM_SETEXTENDEDLISTVIEWSTYLE, 0, LVS_EX_CHECKBOXES);

		// Subclass so WM_SETFOCUS can move focus onto the first item when nothing
		// is selected yet — keyboard users land on a real, navigable item.
		subclass();
	}

	/// Append an item with the given `text`. Returns the new item's index.
	int addItem(string text)
	{
		LVITEMW item;
		item.mask = LVIF_TEXT;
		item.iItem = getItemCount();
		item.pszText = cast(LPWSTR) text.toWStringz;
		return cast(int) SendMessageW(handle, LVM_INSERTITEMW, 0, cast(LPARAM)&item);
	}

	/// Return the number of items.
	int getItemCount()
	{
		return cast(int) SendMessageW(handle, LVM_GETITEMCOUNT, 0, 0);
	}

	/// Remove all items.
	void clear()
	{
		SendMessageW(handle, LVM_DELETEALLITEMS, 0, 0);
	}

	/// Return the text of the item at `index`.
	string getItemText(int index)
	{
		auto buf = new wchar[512];
		LVITEMW item;
		item.iSubItem = 0;
		item.pszText = buf.ptr;
		item.cchTextMax = cast(int) buf.length;
		SendMessageW(handle, LVM_GETITEMTEXTW, index, cast(LPARAM)&item);
		return fromWStringz(buf.ptr);
	}

	/// Return whether the item at `index` is checked.
	bool isChecked(int index)
	{
		auto st = cast(uint) SendMessageW(handle, LVM_GETITEMSTATE, index,
			LVIS_STATEIMAGEMASK);
		return ((st >> 12) == 2);
	}

	/// Set the checked state of the item at `index`.
	void setChecked(int index, bool checked)
	{
		LVITEMW item;
		item.stateMask = LVIS_STATEIMAGEMASK;
		item.state = (checked ? 2 : 1) << 12;
		SendMessageW(handle, LVM_SETITEMSTATE, index, cast(LPARAM)&item);
	}

	/// Return the index of the selected item, or -1 if nothing is selected.
	int getSelectedIndex()
	{
		return cast(int) SendMessageW(handle, LVM_GETNEXTITEM, cast(WPARAM)-1, LVNI_SELECTED);
	}

	/// Select (and focus) the item at `index`.
	void setSelectedIndex(int index)
	{
		LVITEMW item;
		item.state = LVIS_SELECTED | LVIS_FOCUSED;
		item.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
		SendMessageW(handle, LVM_SETITEMSTATE, index, cast(LPARAM)&item);
	}

	/// Route list-view selection and check-toggle notifications to their events.
	override bool processNotify(NMHDR* header)
	{
		if (header.code == LVN_ITEMCHANGED)
		{
			auto nm = cast(NMLISTVIEW*) header;
			if (nm.uChanged & LVIF_STATE)
			{
				// Selection: fire only on a 0 -> selected transition.
				if ((nm.uNewState & LVIS_SELECTED) && !(nm.uOldState & LVIS_SELECTED))
					onSelectionChanged.fire(nm.iItem);

				// Check toggle: compare the old and new state-image indices. Guard
				// oldImg != 0 so the initial 0 -> state transition on insert (when
				// the checkbox first appears) does not fire a spurious event.
				int oldImg = (nm.uOldState & LVIS_STATEIMAGEMASK) >> 12;
				int newImg = (nm.uNewState & LVIS_STATEIMAGEMASK) >> 12;
				if (oldImg != 0 && newImg != 0 && oldImg != newImg)
					onItemChecked.fire(nm.iItem);
			}
			return true;
		}
		return false;
	}

	/**
	 * Move focus onto the first item when the control gains focus with nothing
	 * selected, so a keyboard user starts on a navigable item. Always returns
	 * false so default processing still runs.
	 */
	override bool processSubclassed(UINT msg, WPARAM wParam, LPARAM lParam,
		ref LRESULT result)
	{
		if (msg == WM_SETFOCUS && getSelectedIndex() < 0 && getItemCount() > 0)
			setSelectedIndex(0);
		return false;
	}

	/// A sensible default size for a checked list.
	override Size getPreferredSize()
	{
		return Size(200, 160);
	}
}
