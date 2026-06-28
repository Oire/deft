/**
 * System tray (notification area) icons.
 *
 * `TrayIcon` wraps `Shell_NotifyIconW`. It shows an icon with a tooltip in the
 * notification area, optionally a balloon notification and a right-click context
 * menu, and fires `onDoubleClicked` when the icon is double-clicked (the usual
 * "restore the window" gesture).
 *
 * The icon sends its mouse notifications to the owner window as a private
 * application message; `Window` routes that message here via
 * `dispatchTrayMessage`. Call `destroy()` before the owner window is torn down —
 * a lingering tray icon can leave screen-reader focus in a bad state.
 */
module deft.controls.trayicon;

version (Windows):

import core.sys.windows.windows;
import core.sys.windows.shellapi;

import deft.events;
import deft.menu : Menu;
import deft.util.strings;
import deft.window : Window;

/// Private window message the tray icon uses to report mouse activity.
enum UINT trayCallbackMessage = WM_APP + 100;

private __gshared TrayIcon[uint] g_trayIcons;
private __gshared uint g_nextTrayId = 1;

/**
 * Route a tray callback message to the matching `TrayIcon`.
 *
 * `id` is the icon id (the `wParam` of the callback message); `mouseMsg` is the
 * mouse message (`lParam`). Returns `true` if a matching icon handled it.
 */
bool dispatchTrayMessage(uint id, uint mouseMsg)
{
	if (auto icon = id in g_trayIcons)
	{
		(*icon).handleMouse(mouseMsg);
		return true;
	}
	return false;
}

/// Copy a D string into a fixed-size wide buffer, NUL-terminating and clipping.
private void copyToWBuffer(string s, WCHAR[] dest)
{
	auto src = s.toWStringz;
	size_t i = 0;
	for (; i + 1 < dest.length && src[i] != '\0'; ++i)
		dest[i] = src[i];
	dest[i] = '\0';
}

/// A notification-area icon owned by a top-level window.
class TrayIcon
{
	private Window owner_;
	private uint id_;
	private HICON icon_;
	private string tooltip_;
	private Menu contextMenu_;
	private bool added_;

	/// Fired when the icon is double-clicked with the left mouse button.
	Event!() onDoubleClicked;

	/**
	 * Create a tray icon for `owner` with the given tooltip.
	 *
	 * The icon is added to the notification area immediately; set an icon image
	 * with `setIcon` (until then the area shows a blank slot).
	 */
	this(Window owner, string tooltip)
	{
		owner_ = owner;
		tooltip_ = tooltip;
		id_ = g_nextTrayId++;
		g_trayIcons[id_] = this;
		add();
	}

	private NOTIFYICONDATAW baseData()
	{
		NOTIFYICONDATAW nid;
		nid.cbSize = NOTIFYICONDATAW.sizeof;
		nid.hWnd = owner_.handle;
		nid.uID = id_;
		return nid;
	}

	private void add()
	{
		auto nid = baseData();
		nid.uFlags = NIF_MESSAGE | NIF_TIP;
		nid.uCallbackMessage = trayCallbackMessage;
		copyToWBuffer(tooltip_, nid.szTip[]);
		if (icon_ !is null)
		{
			nid.uFlags |= NIF_ICON;
			nid.hIcon = icon_;
		}
		Shell_NotifyIconW(NIM_ADD, &nid);
		added_ = true;
	}

	/// Set the icon image shown in the notification area.
	void setIcon(HICON icon)
	{
		icon_ = icon;
		auto nid = baseData();
		nid.uFlags = NIF_ICON;
		nid.hIcon = icon;
		Shell_NotifyIconW(NIM_MODIFY, &nid);
	}

	/// Change the hover tooltip text.
	void setTooltip(string text)
	{
		tooltip_ = text;
		auto nid = baseData();
		nid.uFlags = NIF_TIP;
		copyToWBuffer(text, nid.szTip[]);
		Shell_NotifyIconW(NIM_MODIFY, &nid);
	}

	/// Show a balloon notification with `title` and `text`.
	void showBalloon(string title, string text)
	{
		auto nid = baseData();
		nid.uFlags = NIF_INFO;
		copyToWBuffer(title, nid.szInfoTitle[]);
		copyToWBuffer(text, nid.szInfo[]);
		Shell_NotifyIconW(NIM_MODIFY, &nid);
	}

	/// Set the menu shown on right-click (or Apps key while the icon is active).
	void setContextMenu(Menu menu)
	{
		contextMenu_ = menu;
	}

	/**
	 * Remove the icon from the notification area.
	 *
	 * Call this before destroying the owner window. Idempotent.
	 */
	void destroy()
	{
		if (!added_)
			return;
		auto nid = baseData();
		Shell_NotifyIconW(NIM_DELETE, &nid);
		g_trayIcons.remove(id_);
		added_ = false;
	}

	/// React to a mouse message forwarded from the owner window.
	private void handleMouse(uint mouseMsg)
	{
		switch (mouseMsg)
		{
		case WM_LBUTTONDBLCLK:
			onDoubleClicked.fire();
			break;

		case WM_RBUTTONUP:
		case WM_CONTEXTMENU:
			if (contextMenu_ !is null && owner_ !is null && owner_.handle !is null)
			{
				POINT pt;
				GetCursorPos(&pt);
				// Foreground + the trailing null post are the documented fix for
				// a tray menu that otherwise won't dismiss on an outside click.
				SetForegroundWindow(owner_.handle);
				TrackPopupMenu(contextMenu_.handle,
					TPM_LEFTALIGN | TPM_RIGHTBUTTON,
					pt.x, pt.y, 0, owner_.handle, null);
				PostMessageW(owner_.handle, WM_NULL, 0, 0);
			}
			break;

		default:
			break;
		}
	}
}

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
