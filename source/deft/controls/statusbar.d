/**
 * Status bar control.
 *
 * `StatusBar` wraps the native `"msctls_statusbar32"` common control. A status
 * bar auto-docks itself to the bottom of its parent's client area in response
 * to `WM_SIZE`; the host window forwards `WM_SIZE` to it and reserves
 * `getHeight()` pixels at the bottom. The bar can show a single line of text or
 * be split into several parts.
 */
module deft.controls.statusbar;

version (Windows):

import core.sys.windows.windows;
import core.sys.windows.commctrl;

import deft.controls.control;
import deft.util.strings;
import deft.widget;

/// A native status bar docked to the bottom of its parent window.
class StatusBar : Control
{
	/**
	 * Create a status bar as a child of `parent`.
	 *
	 * The bar is given a size grip (`SBARS_SIZEGRIP`) and positions itself; an
	 * initial `WM_SIZE` is sent so it docks to the bottom of the parent.
	 */
	this(Widget parent)
	{
		super(parent, "msctls_statusbar32", SBARS_SIZEGRIP);
		SendMessageW(handle, WM_SIZE, 0, 0);
	}

	/// Set the text of the default (single) part.
	override void setText(string text)
	{
		if (handle)
			SendMessageW(handle, SB_SETTEXTW, 0, cast(LPARAM) text.toWStringz);
	}

	/**
	 * Divide the bar into parts.
	 *
	 * `widths` holds the right-edge x coordinate of each part; a final value of
	 * `-1` extends the last part to the right edge of the bar.
	 */
	void setParts(int[] widths)
	{
		if (handle)
			SendMessageW(handle, SB_SETPARTS, cast(WPARAM) widths.length,
				cast(LPARAM) widths.ptr);
	}

	/// Set the text of part `part` (zero-based).
	void setPartText(int part, string text)
	{
		if (handle)
			SendMessageW(handle, SB_SETTEXTW, cast(WPARAM) part,
				cast(LPARAM) text.toWStringz);
	}

	/// The control's current height in pixels, or `0` if it has no handle.
	int getHeight()
	{
		RECT rc;
		if (handle && GetWindowRect(handle, &rc))
			return rc.bottom - rc.top;
		return 0;
	}

	/// Re-dock the bar by forwarding a `WM_SIZE` to it.
	void reposition()
	{
		if (handle)
			SendMessageW(handle, WM_SIZE, 0, 0);
	}

	/// The bar fills its parent's width; its preferred height is its own height.
	override Size getPreferredSize()
	{
		return handle ? Size(0, getHeight()) : Size(0, 22);
	}
}
