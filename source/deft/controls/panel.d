/**
 * A container widget that groups and lays out child controls.
 *
 * `Panel` is a real child window of Deft's own window class — not a native
 * `STATIC` — so, unlike a bare static control, it forwards the `WM_COMMAND` and
 * `WM_NOTIFY` notifications its children raise. Without this, a button or list
 * placed inside a static container would never deliver its click/selection
 * events (the static control's window procedure drops them). A panel arranges
 * its children with a `Sizer`, making it the natural content host for a tab
 * page or any nested region.
 *
 * `WS_EX_CONTROLPARENT` is set so the dialog manager tabs into the panel's
 * children — keyboard navigation reaches everything inside.
 */
module deft.controls.panel;

version (Windows):

import core.sys.windows.windows;

import deft.controls.control : routeCommand, routeNotify;
import deft.layout : Sizer;
import deft.widget;
import deft.platform.win32.init : deftWindowClassName, ensureWindowClass, hInstance;

/// A sizer-arranged container that forwards its children's notifications.
class Panel : Widget
{
	private Sizer sizer_;

	/// Create a panel as a child of `parent`.
	this(Widget parent)
	{
		ensureWindowClass();
		this.parent_ = parent;

		HWND parentHandle = parent !is null ? parent.handle : null;

		handle_ = CreateWindowExW(
			WS_EX_CONTROLPARENT, // let the dialog manager tab into the children
			deftWindowClassName.ptr,
			""w.ptr,
			WS_CHILD | WS_VISIBLE,
			0, 0, 0, 0,
			parentHandle,
			null,
			hInstance(),
			null);

		registerHandle();

		if (parent !is null)
			parent.addChild(this);
	}

	/// Install the sizer that arranges the panel's children and lay it out now.
	void setSizer(Sizer sizer)
	{
		sizer_ = sizer;
		relayout();
	}

	/// Re-run the sizer over the panel's client area.
	void relayout()
	{
		if (sizer_ !is null)
			sizer_.layout(getClientRect());
	}

	/// Moving/resizing the panel re-lays out its contents.
	override void setBounds(Rect r)
	{
		super.setBounds(r);
		relayout();
	}

	/// The panel's natural size is its sizer's preferred size.
	override Size getPreferredSize()
	{
		return sizer_ !is null ? sizer_.preferredSize() : Size.init;
	}

	/// Forward children's `WM_COMMAND`/`WM_NOTIFY` and relayout on size; else defer.
	override LRESULT processMessage(UINT msg, WPARAM wParam, LPARAM lParam)
	{
		switch (msg)
		{
		case WM_COMMAND:
			// Forward control notifications (non-null lParam) to the originating
			// control, exactly as a top-level Window does.
			if (cast(HWND) lParam !is null && routeCommand(wParam, lParam))
				return 0;
			break;

		case WM_NOTIFY:
			if (routeNotify(lParam))
				return 0;
			break;

		case WM_SIZE:
			relayout();
			return 0;

		default:
			break;
		}
		return super.processMessage(msg, wParam, lParam);
	}
}
