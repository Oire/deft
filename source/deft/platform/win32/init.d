/**
 * Process-wide Win32 initialization: the module handle and the default window
 * class registration.
 */
module deft.platform.win32.init;

version (Windows):

import core.sys.windows.windows;

import deft.platform.win32.wndproc : wndProc;

/// The name of Deft's default top-level window class (null-terminated literal).
enum deftWindowClassName = "DeftWindow"w;

private __gshared HINSTANCE g_hInstance;
private __gshared bool g_classRegistered;

/// The process module handle, fetched lazily via `GetModuleHandleW(null)`.
HINSTANCE hInstance()
{
	if (g_hInstance is null)
		g_hInstance = GetModuleHandleW(null);
	return g_hInstance;
}

/**
 * Register the default window class on first use. Idempotent.
 *
 * The class uses the master `wndProc`, redraws on resize (`CS_HREDRAW |
 * CS_VREDRAW`), the standard arrow cursor and the system window background.
 */
void ensureWindowClass()
{
	if (g_classRegistered)
		return;
	g_classRegistered = true;

	// Default the window icon to the executable's first icon resource (id 1, the
	// conventional application-icon id), so an app that embeds an .ico via its .rc
	// gets it in the title bar/taskbar/Alt+Tab with no extra code. Apps can still
	// override per-window with Window.setIcon. Null when no icon resource exists.
	HICON appIcon = LoadIconW(hInstance(), cast(LPCWSTR) cast(void*) cast(size_t) 1);

	WNDCLASSEXW wc;
	wc.cbSize = WNDCLASSEXW.sizeof;
	wc.style = CS_HREDRAW | CS_VREDRAW;
	wc.lpfnWndProc = &wndProc;
	wc.cbClsExtra = 0;
	wc.cbWndExtra = 0;
	wc.hInstance = hInstance();
	wc.hIcon = appIcon;
	wc.hCursor = LoadCursorW(null, IDC_ARROW);
	wc.hbrBackground = cast(HBRUSH)(COLOR_WINDOW + 1);
	wc.lpszMenuName = null;
	wc.lpszClassName = deftWindowClassName.ptr;
	wc.hIconSm = appIcon;

	RegisterClassExW(&wc);
}
