/**
 * Win32 backend.
 *
 * Aggregates the Win32-specific implementation modules (window class
 * registration and the master window procedure).
 */
module deft.platform.win32;

version (Windows):

public import deft.platform.win32.init;
public import deft.platform.win32.wndproc;
