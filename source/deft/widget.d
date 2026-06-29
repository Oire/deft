/**
 * Widget base class and the geometry primitives it works with.
 *
 * A `Widget` owns a single native window handle (`HWND`) and the common
 * operations over it: visibility, bounds, enablement, focus and deterministic
 * teardown. `Window` (top-level windows) and `Control` (common controls) both
 * derive from it.
 *
 * Handle lifetime: a widget owns its `HWND`. Because D's garbage collector is
 * non-deterministic, call `dispose()` for prompt, predictable cleanup — it
 * destroys the native window and unregisters the widget. While a widget's HWND
 * is alive the widget is pinned as a GC root so it cannot be collected out from
 * under the message loop.
 */
module deft.widget;

version (Windows):

import core.memory : GC;
import core.sys.windows.windows;

import deft.platform.win32.wndproc : registerWidget, unregisterWidget;

/// An axis-aligned rectangle in device pixels.
struct Rect
{
	int x;
	int y;
	int width;
	int height;

	/// Build a `Rect` from a Win32 `RECT` (left/top/right/bottom).
	static Rect fromRECT(RECT r) @safe pure nothrow @nogc
	{
		return Rect(r.left, r.top, r.right - r.left, r.bottom - r.top);
	}

	/// Convert to a Win32 `RECT`.
	RECT toRECT() const @safe pure nothrow @nogc
	{
		RECT r;
		r.left = x;
		r.top = y;
		r.right = x + width;
		r.bottom = y + height;
		return r;
	}
}

/// A width/height pair in device pixels.
struct Size
{
	int width;
	int height;
}

/// Per-edge spacing in device pixels.
struct Padding
{
	int left;
	int top;
	int right;
	int bottom;

	/// Equal padding on every edge.
	static Padding all(int n) @safe pure nothrow @nogc
	{
		return Padding(n, n, n, n);
	}

	/// `h` on the left and right edges, `v` on the top and bottom.
	static Padding symmetric(int h, int v) @safe pure nothrow @nogc
	{
		return Padding(h, v, h, v);
	}
}

/**
 * Abstract base for everything that owns a native window.
 */
abstract class Widget
{
	/// The native window handle this widget owns (null until created).
	protected HWND handle_;

	/// The widget this one is parented to, if any.
	protected Widget parent_;

	/// Child widgets, in z/insertion order.
	protected Widget[] children_;

	/// Cached visibility flag.
	protected bool visible_ = true;

	/// Cached bounds (window-relative for children, screen-relative for windows).
	protected Rect bounds_;

	private bool disposed_;

	/**
	 * The native window handle this widget owns (null until created).
	 *
	 * Read-only: a widget owns its handle for its whole lifetime and the framework
	 * relies on that invariant (GC pinning, the HWND→widget registry). Consumers
	 * may read it for interop with raw Win32 calls but cannot reassign it.
	 */
	final HWND handle() @property @safe nothrow @nogc
	{
		return handle_;
	}

	/// The widget this one is parented to, if any. Read-only; see `addChild`.
	final Widget parent() @property @safe nothrow @nogc
	{
		return parent_;
	}

	/// The child widgets, in z/insertion order. Read-only; see `addChild`.
	final Widget[] children() @property @safe nothrow @nogc
	{
		return children_;
	}

	/// Whether the widget is currently visible. Read-only; see `setVisible`.
	final bool visible() @property @safe nothrow @nogc
	{
		return visible_;
	}

	/// The widget's last-known bounds. Read-only; see `setBounds`/`getBounds`.
	final Rect bounds() @property @safe nothrow @nogc
	{
		return bounds_;
	}

	/// Raw handle accessor for subclasses and the backend.
	protected HWND rawHandle() @property @safe nothrow @nogc
	{
		return handle_;
	}

	/// Make the widget visible.
	void show()
	{
		setVisible(true);
	}

	/// Hide the widget.
	void hide()
	{
		setVisible(false);
	}

	/// Set visibility, updating the native window if it exists.
	void setVisible(bool value)
	{
		visible_ = value;
		if (handle)
			ShowWindow(handle, value ? SW_SHOW : SW_HIDE);
	}

	/// Move/resize the widget, updating the native window if it exists.
	void setBounds(Rect r)
	{
		bounds_ = r;
		if (handle)
			MoveWindow(handle, r.x, r.y, r.width, r.height, TRUE);
	}

	/// The widget's last-known bounds.
	Rect getBounds()
	{
		return bounds_;
	}

	/// The widget's client area (origin at 0,0). Empty if not yet created.
	Rect getClientRect()
	{
		if (!handle)
			return Rect.init;
		RECT rc;
		GetClientRect(handle, &rc);
		return Rect.fromRECT(rc);
	}

	/// Enable or disable input for the widget.
	void setEnabled(bool enabled)
	{
		if (handle)
			EnableWindow(handle, enabled ? TRUE : FALSE);
	}

	/// Whether the widget currently accepts input.
	bool isEnabled()
	{
		if (!handle)
			return false;
		return IsWindowEnabled(handle) != FALSE;
	}

	/// Give the widget keyboard focus.
	void setFocus()
	{
		if (handle)
			SetFocus(handle);
	}

	/// Request a repaint of the whole widget.
	void invalidate()
	{
		if (handle)
			InvalidateRect(handle, null, TRUE);
	}

	/**
	 * The widget's preferred size, used by the layout engine for non-stretching
	 * (proportion 0) items. The base widget has no intrinsic size; controls
	 * override this.
	 */
	Size getPreferredSize()
	{
		return Size.init;
	}

	/// Append a child and set its parent to this widget.
	void addChild(Widget child)
	{
		if (child is null)
			return;
		children_ ~= child;
		child.parent_ = this;
	}

	/// Remove a child and clear its parent link. Unknown children are ignored.
	void removeChild(Widget child)
	{
		foreach (i, c; children)
		{
			if (c is child)
			{
				children_ = children_[0 .. i] ~ children_[i + 1 .. $];
				if (child !is null)
					child.parent_ = null;
				return;
			}
		}
	}

	/**
	 * Deterministically tear the widget down: dispose children, detach from the
	 * parent, destroy the native window, unregister it, and release the GC root.
	 * Idempotent — safe to call more than once.
	 */
	void dispose()
	{
		if (disposed_)
			return;
		disposed_ = true;

		foreach (child; children_.dup)
			child.dispose();
		children_ = null;

		if (parent_ !is null)
			parent_.removeChild(this);

		if (handle_)
		{
			unregisterWidget(handle_);
			DestroyWindow(handle_);
			handle_ = null;
		}

		GC.removeRoot(cast(void*) this);
	}

	/**
	 * Associate this widget's freshly-created HWND with the dispatch machinery
	 * and pin it as a GC root. Call once, immediately after `handle` is set.
	 */
	protected void registerHandle()
	{
		if (!handle)
			return;
		GC.addRoot(cast(void*) this);
		SetWindowLongPtrW(handle, GWLP_USERDATA, cast(LONG_PTR) cast(void*) this);
		registerWidget(handle, this);
	}

	/**
	 * Handle a window message routed from the master window procedure.
	 *
	 * The default implementation defers to `DefWindowProcW`. Subclasses override
	 * to handle specific messages and call `super.processMessage` for the rest.
	 */
	LRESULT processMessage(UINT msg, WPARAM wParam, LPARAM lParam)
	{
		return DefWindowProcW(handle, msg, wParam, lParam);
	}
}

unittest
{
	// Rect <-> RECT conversion: a RECT is left/top/right/bottom; a Rect is
	// x/y/width/height. fromRECT computes the extents and toRECT inverts it.
	RECT r;
	r.left = 10;
	r.top = 20;
	r.right = 110;
	r.bottom = 70;

	auto rect = Rect.fromRECT(r);
	assert(rect == Rect(10, 20, 100, 50));

	auto back = rect.toRECT();
	assert(back.left == 10 && back.top == 20 && back.right == 110 && back.bottom == 70);

	// Round-trips for any rectangle.
	auto rt = Rect(3, 7, 40, 9);
	auto rtBack = Rect.fromRECT(rt.toRECT());
	assert(rtBack == rt);
}

unittest
{
	// Padding factory helpers.
	assert(Padding.all(5) == Padding(5, 5, 5, 5));
	assert(Padding.symmetric(8, 4) == Padding(8, 4, 8, 4));
	assert(Padding.all(0) == Padding.init);
}
