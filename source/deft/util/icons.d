/**
 * Icon loading helpers for the Win32 backend.
 *
 * These load an `HICON` from the executable's own resources (by integer id) or
 * from a `.ico` file on disk. They are used by `Window.setIcon`, `TrayIcon`, and
 * the default window-class icon, and are equally usable from application code.
 */
module deft.util.icons;

version (Windows):

import core.sys.windows.windows;

import deft.util.strings;

/// Load an icon from the application's own resources by integer id.
HICON loadIcon(int resourceId)
{
	auto resource = cast(LPCWSTR) cast(void*) cast(size_t) cast(ushort) resourceId;
	return LoadIconW(GetModuleHandleW(null), resource);
}

/// Load an icon image from a `.ico` file on disk.
HICON loadIconFromFile(string path)
{
	return cast(HICON) LoadImageW(null, path.toWStringz, IMAGE_ICON,
		0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
}
