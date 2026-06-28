/**
 * The master window procedure and the HWND → Widget registry.
 *
 * Every Deft window class is registered with the single `wndProc` below. It
 * finds the `Widget` that owns the target `HWND` and forwards the message to
 * `Widget.processMessage`, where per-widget handling lives. Lookup is by
 * `GWLP_USERDATA` (set when the widget's handle is created), with the registry
 * associative array as a fallback.
 */
module deft.platform.win32.wndproc;

version (Windows):

import core.sys.windows.windows;

import deft.widget : Widget;

/// HWND → Widget map. Accessed only from the single UI thread.
private __gshared Widget[HWND] g_widgets;

/// Register a widget under its HWND.
void registerWidget(HWND h, Widget w)
{
	g_widgets[h] = w;
}

/// Remove a widget's HWND from the registry.
void unregisterWidget(HWND h)
{
	g_widgets.remove(h);
}

/// Look up the widget that owns an HWND, or null.
Widget lookupWidget(HWND h)
{
	if (auto p = h in g_widgets)
		return *p;
	return null;
}

/**
 * The single window procedure shared by all Deft window classes.
 *
 * `extern(Windows)` callbacks must not let a D exception escape into the OS, so
 * the dispatch is wrapped: any `Throwable` is swallowed and the message falls
 * through to `DefWindowProcW`.
 */
extern (Windows) LRESULT wndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) nothrow
{
	try
	{
		Widget widget;

		auto userData = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
		if (userData != 0)
			widget = cast(Widget) cast(void*) userData;
		else
			widget = lookupWidget(hwnd);

		if (widget !is null)
			return widget.processMessage(msg, wParam, lParam);
	}
	catch (Throwable)
	{
		// Swallow: never propagate a D throwable through the Win32 dispatcher.
	}

	return DefWindowProcW(hwnd, msg, wParam, lParam);
}
