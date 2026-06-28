/**
 * Top-level windows.
 *
 * `Window` is a `Widget` backed by a `WS_OVERLAPPEDWINDOW`. It exposes the two
 * lifecycle events most applications care about — `onClose` (cancellable) and
 * `onResize` — and acts as the root of a widget tree.
 */
module deft.window;

version (Windows):

import core.sys.windows.windows;

import deft.controls.control : Control, routeCommand, routeNotify;
import deft.controls.statusbar : StatusBar;
import deft.controls.timer : dispatchTimer;
import deft.controls.trayicon : dispatchTrayMessage, trayCallbackMessage;
import deft.events;
import deft.layout : Sizer;
import deft.menu : MenuBar, dispatchMenuCommand, setAcceleratorTable;
import deft.util.strings;
import deft.widget;
import deft.platform.win32.init : deftWindowClassName, ensureWindowClass, hInstance;

/**
 * Arguments passed to `Window.onClose` handlers.
 *
 * A handler may set `cancel = true` to veto the close — used for
 * minimize-to-tray and confirm-before-exit flows.
 */
struct CloseEventArgs
{
	bool cancel = false;
}

/// A top-level application window.
class Window : Widget
{
	/// Fired when the window is about to close; set `args.cancel` to veto.
	Event!(CloseEventArgs*) onClose;

	/// Fired on resize with the new client width and height.
	Event!(int, int) onResize;

	/**
	 * Whether this is the application's main window. When the main window is
	 * destroyed the message loop is asked to quit (`PostQuitMessage`).
	 */
	bool isMainWindow = true;

	/// Optional root sizer that arranges the window's contents on resize.
	private Sizer rootSizer_;

	/// Optional status bar docked at the bottom; its height is reserved in layout.
	private StatusBar statusBar_;

	/// Optional menu bar; retained so the GC keeps its handle alive.
	private MenuBar menuBar_;

	/// Control id of the designated default button (0 = none).
	private int defaultButtonId_;

	/**
	 * Create and show-ready a top-level window with the given title and size
	 * (the size is the outer window size, in pixels).
	 */
	this(string title, int width, int height)
	{
		ensureWindowClass();

		handle = CreateWindowExW(
			WS_EX_CONTROLPARENT, // let the dialog manager recurse into child controls
			deftWindowClassName.ptr,
			title.toWStringz,
			WS_OVERLAPPEDWINDOW,
			CW_USEDEFAULT, CW_USEDEFAULT,
			width, height,
			null, // no parent
			null, // no menu
			hInstance(),
			null);

		registerHandle();

		RECT rc;
		if (handle && GetWindowRect(handle, &rc))
			bounds = Rect.fromRECT(rc);
		else
			bounds = Rect(0, 0, width, height);
	}

	/// Show the window and force an initial paint.
	override void show()
	{
		visible = true;
		if (handle)
		{
			ShowWindow(handle, SW_SHOW);
			UpdateWindow(handle);
		}
	}

	/// Set the window title bar text.
	void setTitle(string title)
	{
		if (handle)
			SetWindowTextW(handle, title.toWStringz);
	}

	/// Ask the window to close (drives the same path as the close button).
	void close()
	{
		if (handle)
			SendMessageW(handle, WM_CLOSE, 0, 0);
	}

	/**
	 * Install the root sizer and immediately lay it out over the client area.
	 */
	void setSizer(Sizer sizer)
	{
		rootSizer_ = sizer;
		relayout();
	}

	/**
	 * Dock a status bar at the bottom of the window. Its height is reserved so
	 * the root sizer's content never overlaps it.
	 */
	void setStatusBar(StatusBar statusBar)
	{
		statusBar_ = statusBar;
		relayout();
	}

	/**
	 * Attach a menu bar to the window and install its keyboard accelerators.
	 * Re-lays out the contents, since the menu reduces the client area.
	 */
	void setMenuBar(MenuBar menuBar)
	{
		menuBar_ = menuBar;
		if (handle && menuBar !is null)
		{
			SetMenu(handle, menuBar.handle);
			DrawMenuBar(handle);
			setAcceleratorTable(menuBar.buildAcceleratorTable());
			relayout();
		}
	}

	/// Re-run the root sizer over the current client area, if one is set.
	void relayout()
	{
		auto rc = getClientRect();
		layoutContents(rc.width, rc.height);
	}

	/// Lay out the root sizer over the client area minus any docked status bar.
	private void layoutContents(int width, int height)
	{
		if (statusBar_ !is null)
		{
			statusBar_.reposition();
			height -= statusBar_.getHeight();
			if (height < 0)
				height = 0;
		}
		if (rootSizer_ !is null)
			rootSizer_.layout(Rect(0, 0, width, height));
	}

	/**
	 * Designate the button activated by Enter when focus is on a non-button
	 * control. A focused push button is always its own default regardless of
	 * this setting (native dialog behavior). Pass null to clear.
	 */
	void setDefaultButton(Control button)
	{
		defaultButtonId_ = button is null ? 0 : button.controlId;
	}

	/// Move keyboard focus to the first focusable child control, if any.
	void focusFirstControl()
	{
		HWND first = firstFocusableChild();
		if (first !is null)
			SetFocus(first);
	}

	/// The handle of the first visible, enabled, tab-stop child, or null.
	private HWND firstFocusableChild()
	{
		foreach (child; children)
		{
			if (child.handle is null)
				continue;
			auto style = GetWindowLongW(child.handle, GWL_STYLE);
			if ((style & WS_TABSTOP)
				&& IsWindowVisible(child.handle)
				&& IsWindowEnabled(child.handle))
				return child.handle;
		}
		return null;
	}

	override LRESULT processMessage(UINT msg, WPARAM wParam, LPARAM lParam)
	{
		switch (msg)
		{
		case WM_CLOSE:
			auto args = CloseEventArgs(false);
			onClose.fire(&args);
			if (!args.cancel && handle)
				DestroyWindow(handle);
			return 0;

		case WM_SIZE:
			immutable int w = LOWORD(cast(DWORD) lParam);
			immutable int h = HIWORD(cast(DWORD) lParam);
			layoutContents(w, h);
			onResize.fire(w, h);
			return 0;

		case WM_COMMAND:
			// Menu and accelerator commands carry a null lParam; controls carry
			// their HWND. Try the menu registry first for the former.
			if (cast(HWND) lParam is null
				&& dispatchMenuCommand(LOWORD(cast(DWORD) wParam)))
				return 0;
			if (routeCommand(wParam, lParam))
				return 0;
			return super.processMessage(msg, wParam, lParam);

		case WM_TIMER:
			if (dispatchTimer(cast(uint) wParam))
				return 0;
			return super.processMessage(msg, wParam, lParam);

		case WM_NOTIFY:
			if (routeNotify(lParam))
				return 0;
			return super.processMessage(msg, wParam, lParam);

		case DM_GETDEFID:
			// The dialog manager (IsDialogMessage) asks for the default command
			// id to activate on Enter. A focused push button is its own default,
			// matching native dialogs; otherwise fall back to the designated
			// default button. Without this, Enter on a button does nothing until
			// the control is re-focused via Tab.
			HWND focused = GetFocus();
			if (focused !is null && IsChild(handle, focused))
			{
				auto code = cast(uint) SendMessageW(focused, WM_GETDLGCODE, 0, 0);
				if (code & (DLGC_DEFPUSHBUTTON | DLGC_UNDEFPUSHBUTTON))
				{
					int id = GetDlgCtrlID(focused);
					if (id != 0)
						return (cast(LRESULT) DC_HASDEFID << 16) | (id & 0xFFFF);
				}
			}
			if (defaultButtonId_ != 0)
				return (cast(LRESULT) DC_HASDEFID << 16) | (defaultButtonId_ & 0xFFFF);
			return super.processMessage(msg, wParam, lParam);

		case DM_SETDEFID:
			defaultButtonId_ = cast(int)(wParam & 0xFFFF);
			return TRUE;

		case WM_SETFOCUS:
			// When the window itself receives focus, hand it to the first
			// focusable child so keyboard users (and screen readers) land on a
			// real control rather than the bare window client.
			HWND first = firstFocusableChild();
			if (first !is null)
			{
				SetFocus(first);
				return 0;
			}
			return super.processMessage(msg, wParam, lParam);

		case WM_DESTROY:
			if (isMainWindow)
				PostQuitMessage(0);
			return 0;

		default:
			if (msg == trayCallbackMessage
				&& dispatchTrayMessage(cast(uint) wParam, cast(uint) lParam))
				return 0;
			return super.processMessage(msg, wParam, lParam);
		}
	}
}
