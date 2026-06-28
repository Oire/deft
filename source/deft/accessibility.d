/**
 * Accessibility — custom accessible names for controls.
 *
 * Standard Win32 common controls (ListView, TreeView, Button, …) already expose
 * MSAA accessibility to screen readers such as JAWS and NVDA — items, roles and
 * navigation all work with no extra code. The one thing missing for controls
 * that lack a visible text label (for example a bare TreeView used as a category
 * panel) is a human-readable *name*.
 *
 * `setAccessibleName` supplies one. Rather than implementing a full `IAccessible`
 * proxy and intercepting `WM_GETOBJECT`, it uses MSAA Direct Annotation
 * (`IAccPropServices::SetHwndPropStr`) to override just the name property on the
 * control's default accessible object. oleacc then serves that name through the
 * standard accessibility path automatically. This is the same mechanism WinForms
 * uses to implement `Control.AccessibleName`.
 *
 * COM must be initialized on the calling (UI) thread first — `Application.initialize`
 * does this.
 */
module deft.accessibility;

version (Windows):

import core.sys.windows.windows;
import core.sys.windows.oaidl : VARIANT;
import core.sys.windows.objbase : CoCreateInstance;
import core.sys.windows.unknwn : IUnknown;
import core.sys.windows.wtypes : CLSCTX;

import deft.util.strings;
import deft.widget : Widget;

/// MSAA annotated property identifier — a GUID, passed by value.
private alias MSAAPROPID = GUID;

/// `OBJID_CLIENT` from WinUser — the client area object id.
private enum DWORD objIdClient = 0xFFFF_FFFC;

/// `CHILDID_SELF` — the object itself rather than a child element.
private enum DWORD childIdSelf = 0;

// CLSID_AccPropServices {b5f8350b-0548-48b1-a6ee-88bd00b4a5e7}
private static immutable GUID clsidAccPropServices =
	GUID(0xb5f8350b, 0x0548, 0x48b1,
		[0xa6, 0xee, 0x88, 0xbd, 0x00, 0xb4, 0xa5, 0xe7]);

// IID_IAccPropServices {6e26e776-04f0-495d-80e4-3330352e3169}
private static immutable GUID iidAccPropServices =
	GUID(0x6e26e776, 0x04f0, 0x495d,
		[0x80, 0xe4, 0x33, 0x30, 0x35, 0x2e, 0x31, 0x69]);

// PROPID_ACC_NAME {608d3df8-8128-4aa7-a428-f55e49267291}
private static immutable MSAAPROPID propIdAccName =
	GUID(0x608d3df8, 0x8128, 0x4aa7,
		[0xa4, 0x28, 0xf5, 0x5e, 0x49, 0x26, 0x72, 0x91]);

/**
 * Minimal binding for `IAccPropServices`.
 *
 * Only `SetHwndPropStr` is called, but every method must be declared in IDL
 * order so the COM vtable layout is correct. `IAccPropServer` arguments are
 * declared as `IUnknown` (a pointer-compatible placeholder) since they are
 * never used here.
 */
private interface IAccPropServices : IUnknown
{
extern (Windows):
	HRESULT SetPropValue(const(BYTE)* pIDString, DWORD dwIDStringLen,
		MSAAPROPID idProp, VARIANT var);
	HRESULT SetPropServer(const(BYTE)* pIDString, DWORD dwIDStringLen,
		const(MSAAPROPID)* paProps, int cProps, IUnknown pServer, int annoScope);
	HRESULT ClearProps(const(BYTE)* pIDString, DWORD dwIDStringLen,
		const(MSAAPROPID)* paProps, int cProps);
	HRESULT SetHwndProp(HWND hwnd, DWORD idObject, DWORD idChild,
		MSAAPROPID idProp, VARIANT var);
	HRESULT SetHwndPropStr(HWND hwnd, DWORD idObject, DWORD idChild,
		MSAAPROPID idProp, const(wchar)* str);
	HRESULT SetHwndPropServer(HWND hwnd, DWORD idObject, DWORD idChild,
		const(MSAAPROPID)* paProps, int cProps, IUnknown pServer, int annoScope);
	HRESULT ClearHwndProps(HWND hwnd, DWORD idObject, DWORD idChild,
		const(MSAAPROPID)* paProps, int cProps);
	HRESULT ComposeHwndIdentityString(HWND hwnd, DWORD idObject, DWORD idChild,
		BYTE** ppIDString, DWORD* pdwIDStringLen);
	HRESULT DecomposeHwndIdentityString(const(BYTE)* pIDString,
		DWORD dwIDStringLen, HWND* phwnd, DWORD* pidObject, DWORD* pidChild);
}

/**
 * Set the accessible name a screen reader announces for a control.
 *
 * Has no effect on a null widget or one without a native handle, and fails
 * silently if the annotation service is unavailable (the control then keeps its
 * default accessibility, which is correct for most controls).
 */
void setAccessibleName(Widget widget, string name)
{
	if (widget is null || widget.handle is null)
		return;

	IAccPropServices services;
	HRESULT hr = CoCreateInstance(
		&clsidAccPropServices,
		null,
		CLSCTX.CLSCTX_INPROC_SERVER,
		&iidAccPropServices,
		cast(void**)&services);

	if (hr < 0 || services is null)
		return;
	scope (exit)
		services.Release();

	services.SetHwndPropStr(
		widget.handle,
		objIdClient,
		childIdSelf,
		propIdAccName,
		name.toWStringz);
}
