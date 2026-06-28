/**
 * Application lifecycle: the singleton that owns process initialization and the
 * Win32 message loop.
 */
module deft.app;

version (Windows):

import core.sys.windows.windows;
import core.sys.windows.commctrl;
import core.sys.windows.objbase;

import deft.platform.win32.init : ensureWindowClass;

// SetProcessDpiAwarenessContext is Win10 1703+; resolved dynamically so the
// framework still loads on older systems (falling back to SetProcessDPIAware).
private alias DpiAwarenessContext = HANDLE;
private enum DpiAwarenessContext perMonitorAwareV2 = cast(HANDLE)-4;
private alias SetProcessDpiAwarenessContextFn =
	extern (Windows) BOOL function(DpiAwarenessContext) nothrow;
private alias SetProcessDpiAwareFn = extern (Windows) BOOL function() nothrow;

/**
 * Make the process DPI-aware so windows are rendered at native resolution
 * instead of being bitmap-stretched by the OS. Bitmap stretching is what makes
 * screen-reader cursors read the wrong screen location on high-DPI displays.
 */
private void enableDpiAwareness() nothrow
{
	auto user32 = GetModuleHandleW("user32.dll"w.ptr);
	if (user32 !is null)
	{
		auto setContext = cast(SetProcessDpiAwarenessContextFn)
			GetProcAddress(user32, "SetProcessDpiAwarenessContext");
		if (setContext !is null && setContext(perMonitorAwareV2))
			return;

		auto setAware = cast(SetProcessDpiAwareFn)
			GetProcAddress(user32, "SetProcessDPIAware");
		if (setAware !is null)
			setAware();
	}
}

/**
 * The application object. Use `Application.instance` to obtain it, call
 * `initialize()` once at startup, then `run()` to enter the message loop.
 */
class Application
{
	private __gshared Application instance_;
	private bool initialized_;

	/// The process-wide application instance (created on first access).
	static Application instance()
	{
		if (instance_ is null)
			instance_ = new Application();
		return instance_;
	}

	/**
	 * Initialize common controls and COM, and register the default window
	 * class. Idempotent; safe to call before creating any windows.
	 */
	void initialize()
	{
		if (initialized_)
			return;
		initialized_ = true;

		// Must run before any window is created.
		enableDpiAwareness();

		INITCOMMONCONTROLSEX icc;
		icc.dwSize = INITCOMMONCONTROLSEX.sizeof;
		icc.dwICC = ICC_LISTVIEW_CLASSES | ICC_TREEVIEW_CLASSES
			| ICC_TAB_CLASSES | ICC_BAR_CLASSES;
		InitCommonControlsEx(&icc);

		// Apartment-threaded COM for shell and accessibility APIs.
		CoInitializeEx(null, COINIT.COINIT_APARTMENTTHREADED);

		ensureWindowClass();
	}

	/**
	 * Run the Win32 message loop until `WM_QUIT`. Returns the exit code carried
	 * by the quit message.
	 */
	int run()
	{
		MSG msg;
		while (GetMessageW(&msg, null, 0, 0) > 0)
		{
			// Route to the dialog manager first so Tab/Shift+Tab, arrow keys and
			// default-button handling move focus between the active window's child
			// controls. Without this, child controls are unreachable by keyboard.
			HWND active = GetActiveWindow();
			if (active is null || !IsDialogMessageW(active, &msg))
			{
				TranslateMessage(&msg);
				DispatchMessageW(&msg);
			}
		}
		return cast(int) msg.wParam;
	}

	/// Post a quit request to the message loop with the given exit code.
	void quit(int exitCode = 0)
	{
		PostQuitMessage(exitCode);
	}
}
