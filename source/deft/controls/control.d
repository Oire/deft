/**
 * Base class for native common controls.
 *
 * `Control` creates a child window of a given Win32 class (`"Button"`,
 * `"SysListView32"`, …) and provides the operations common to all controls:
 * text get/set, font assignment, a preferred size, parent message routing
 * (`WM_COMMAND` / `WM_NOTIFY`), and opt-in subclassing for controls that need
 * to intercept their own messages.
 */
module deft.controls.control;

version (Windows):

import core.sys.windows.windows;
import core.sys.windows.commctrl : DefSubclassProc, SetWindowSubclass, SUBCLASSPROC;

import deft.util.strings;
import deft.widget;
import deft.platform.win32.init : hInstance;
import deft.platform.win32.wndproc : lookupWidget;

private __gshared int g_nextControlId = 1000;

private int nextControlId()
{
	return g_nextControlId++;
}

/// The system default GUI font, used for all controls. Cached stock object.
HFONT defaultFont()
{
	return cast(HFONT) GetStockObject(DEFAULT_GUI_FONT);
}

/// Base class for all Win32 common-control wrappers.
class Control : Widget
{
	private int controlId_;
	private bool subclassed_;

	/// The control's command identifier (the `hMenu` child id at creation).
	int controlId() const @safe pure nothrow @nogc
	{
		return controlId_;
	}

	/**
	 * Create the control as a child window.
	 *
	 * `className` is a Win32 window class name (for example `"Button"`).
	 * `WS_CHILD | WS_VISIBLE` are added to the supplied `style`. The control is
	 * registered with its parent and given the system default GUI font.
	 */
	this(Widget parent, string className, DWORD style, DWORD exStyle = 0)
	{
		this.parent = parent;
		controlId_ = nextControlId();

		HWND parentHandle = parent !is null ? parent.handle : null;

		// WS_GROUP makes each control start its own keyboard navigation group, so
		// arrow keys stay within a control rather than bleeding to the next one.
		// Radio buttons that continue a group clear it again (see RadioButton).
		handle = CreateWindowExW(
			exStyle,
			className.toWStringz,
			""w.ptr,
			WS_CHILD | WS_VISIBLE | WS_GROUP | style,
			0, 0, 0, 0,
			parentHandle,
			cast(HMENU) cast(size_t) controlId_,
			hInstance(),
			null);

		registerHandle();

		if (parent !is null)
			parent.addChild(this);

		setFont(defaultFont());
	}

	/// Set the control's text.
	void setText(string text)
	{
		if (handle)
			SetWindowTextW(handle, text.toWStringz);
	}

	/// Get the control's text.
	string getText()
	{
		if (!handle)
			return "";

		int len = GetWindowTextLengthW(handle);
		if (len <= 0)
			return "";

		auto buf = new wchar[len + 1];
		int got = GetWindowTextW(handle, buf.ptr, cast(int) buf.length);
		return fromWString(buf[0 .. got]);
	}

	/// Assign a font to the control and request a repaint.
	void setFont(HFONT font)
	{
		if (handle)
			SendMessageW(handle, WM_SETFONT, cast(WPARAM) font, cast(LPARAM) TRUE);
	}

	/// A reasonable default preferred size; override per control type.
	override Size getPreferredSize()
	{
		return Size(80, 24);
	}

	/**
	 * Handle a `WM_COMMAND` notification routed from the parent.
	 *
	 * `notificationCode` is the high word of the command's `wParam`. Return
	 * `true` if the notification was handled. The default does nothing.
	 */
	bool processCommand(ushort notificationCode)
	{
		return false;
	}

	/**
	 * Handle a `WM_NOTIFY` notification routed from the parent. Return `true`
	 * if it was handled. The default does nothing.
	 */
	bool processNotify(NMHDR* header)
	{
		return false;
	}

	/**
	 * Install a subclass window procedure so the control can intercept its own
	 * messages (for example, swallowing the Enter key in a text field).
	 * Idempotent. Subclasses override `processSubclassed` to do the work.
	 */
	void subclass()
	{
		if (handle && !subclassed_)
		{
			SetWindowSubclass(handle, &controlSubclassProc, 1,
				cast(DWORD_PTR) cast(void*) this);
			subclassed_ = true;
		}
	}

	/**
	 * Intercept a message while subclassed. Set `result` and return `true` to
	 * consume the message; return `false` to let default processing continue.
	 */
	bool processSubclassed(UINT msg, WPARAM wParam, LPARAM lParam, ref LRESULT result)
	{
		return false;
	}
}

/**
 * Route a parent's `WM_COMMAND` to the originating control. Returns `true` if a
 * control handled it.
 */
bool routeCommand(WPARAM wParam, LPARAM lParam)
{
	auto controlHwnd = cast(HWND) lParam;
	if (controlHwnd is null)
		return false; // menu or accelerator command, not a control

	if (auto widget = lookupWidget(controlHwnd))
		if (auto control = cast(Control) widget)
			return control.processCommand(HIWORD(cast(DWORD) wParam));

	return false;
}

/**
 * Route a parent's `WM_NOTIFY` to the originating control. Returns `true` if a
 * control handled it.
 */
bool routeNotify(LPARAM lParam)
{
	auto header = cast(NMHDR*) lParam;
	if (header is null)
		return false;

	if (auto widget = lookupWidget(header.hwndFrom))
		if (auto control = cast(Control) widget)
			return control.processNotify(header);

	return false;
}

/// The shared subclass procedure; dispatches to `Control.processSubclassed`.
private extern (Windows) LRESULT controlSubclassProc(HWND hwnd, UINT msg,
	WPARAM wParam, LPARAM lParam, UINT_PTR idSubclass, DWORD_PTR refData) nothrow
{
	try
	{
		auto control = cast(Control) cast(void*) refData;
		if (control !is null)
		{
			LRESULT result;
			if (control.processSubclassed(msg, wParam, lParam, result))
				return result;
		}
	}
	catch (Throwable)
	{
		// Never propagate a D throwable through the Win32 dispatcher.
	}

	return DefSubclassProc(hwnd, msg, wParam, lParam);
}
