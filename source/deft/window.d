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
import deft.events;
import deft.layout : Sizer;
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

	/// Re-run the root sizer over the current client area, if one is set.
	void relayout()
	{
		if (rootSizer_ !is null)
			rootSizer_.layout(getClientRect());
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
			if (rootSizer_ !is null)
				rootSizer_.layout(Rect(0, 0, w, h));
			onResize.fire(w, h);
			return 0;

		case WM_COMMAND:
			if (routeCommand(wParam, lParam))
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
			return super.processMessage(msg, wParam, lParam);
		}
	}
}
