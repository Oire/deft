/**
 * Platform abstraction selector.
 *
 * Publicly imports the backend implementation for the current platform.
 * Only the Win32 backend exists today; GTK4 (Linux) and Cocoa (macOS)
 * backends are planned.
 */
module deft.platform;

version (Windows)
{
	public import deft.platform.win32;
}
else
{
	static assert(0, "Deft: unsupported platform. Only Windows is currently supported.");
}
