/**
 * A tab control wrapping the native Win32 `SysTabControl32` common control.
 *
 * Each tab page is an arbitrary `Widget` whose bounds track the tab control's
 * display area. Selecting a tab shows its page and hides the others.
 */
module deft.controls.tabcontrol;

version (Windows):

import core.sys.windows.windows;
import core.sys.windows.commctrl;

import deft.controls.control;
import deft.events;
import deft.util.strings;
import deft.widget;

/**
 * A native tab control hosting one `Widget` per page.
 *
 * Pages are positioned into the tab control's display rect (the area below the
 * tab strip). The page widgets are expected to be children of the same parent
 * window as the tab control.
 */
class TabControl : Control
{
	private Widget[] pages_;
	private int selected_ = -1;

	/// Fired when the selected page changes, with the new page index.
	Event!(int) onPageChanged;

	/// Create a tab control as a child of `parent`.
	this(Widget parent)
	{
		super(parent, "SysTabControl32", WS_TABSTOP);
	}

	/**
	 * Add a page captioned `title` showing `pageContent` when selected. Returns
	 * the index of the newly inserted page.
	 */
	int addPage(string title, Widget pageContent)
	{
		TCITEMW item;
		item.mask = TCIF_TEXT;
		item.pszText = cast(LPWSTR) title.toWStringz;
		int index = cast(int) SendMessageW(handle, TCM_INSERTITEMW, pages_.length, cast(LPARAM)&item);

		pages_ ~= pageContent;
		layoutPages();

		if (pages_.length == 1)
			setSelectedPage(0);
		else
			pageContent.setVisible(false);

		return index;
	}

	/// Change the label of the tab at `index` (e.g. when the UI language changes).
	void setTabTitle(int index, string title)
	{
		TCITEMW item;
		item.mask = TCIF_TEXT;
		item.pszText = cast(LPWSTR) title.toWStringz;
		SendMessageW(handle, TCM_SETITEMW, index, cast(LPARAM)&item);
	}

	/// The index of the currently selected page, or -1 if none.
	int getSelectedPage()
	{
		return cast(int) SendMessageW(handle, TCM_GETCURSEL, 0, 0);
	}

	/// Select the page at `index`, showing its content and hiding the rest.
	void setSelectedPage(int index)
	{
		SendMessageW(handle, TCM_SETCURSEL, index, 0);
		foreach (i, p; pages_)
			p.setVisible(i == index);
		selected_ = index;
		layoutPages();
	}

	/// The display rect (content area below the tab strip), in client coordinates.
	Rect getDisplayRect()
	{
		RECT rc;
		GetClientRect(handle, &rc);
		SendMessageW(handle, TCM_ADJUSTRECT, FALSE, cast(LPARAM)&rc);
		return Rect.fromRECT(rc);
	}

	private void layoutPages()
	{
		auto r = getDisplayRect();
		r.x += bounds.x;
		r.y += bounds.y;
		foreach (p; pages_)
			p.setBounds(r);
	}

	/// Re-positions all pages into the current display rect; call on window resize.
	void relayout()
	{
		layoutPages();
	}

	/// Move/resize the tab control (bounds `r`, parent-relative), then re-lay out its pages.
	override void setBounds(Rect r)
	{
		super.setBounds(r);
		layoutPages();
	}

	/// Translate tab-selection-change notifications into `onPageChanged`.
	override bool processNotify(NMHDR* header)
	{
		if (header.code == TCN_SELCHANGE)
		{
			int idx = getSelectedPage();
			setSelectedPage(idx);
			onPageChanged.fire(idx);
			return true;
		}
		return false;
	}

	/// The preferred size of the tab control.
	override Size getPreferredSize()
	{
		return Size(400, 300);
	}
}
