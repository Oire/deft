/**
 * Delegate-based event system.
 *
 * `Event!(T...)` is a lightweight multicast delegate: handlers are added with
 * `event ~= &handler` and invoked together with `event.fire(args)`. This is the
 * spine of Deft's UI notifications — buttons, windows, list selections and so on
 * expose `Event!(...)` fields that user code subscribes to.
 */
module deft.events;

/**
 * A multicast list of `void delegate(T...)` handlers.
 *
 * Add handlers with `~=`, invoke them all with `fire`, and remove one with
 * `disconnect`. Firing with no registered handlers is a no-op. Handlers are
 * invoked in registration order.
 */
struct Event(T...)
{
	private void delegate(T)[] listeners;

	/// Subscribe a handler: `event ~= &handler`.
	ref typeof(this) opOpAssign(string op : "~")(void delegate(T) handler) return
	{
		listeners ~= handler;
		return this;
	}

	/// Subscribe a handler (named-method equivalent of `~=`).
	void connect(void delegate(T) handler)
	{
		listeners ~= handler;
	}

	/// Remove a previously-subscribed handler. Unknown handlers are ignored.
	void disconnect(void delegate(T) handler)
	{
		foreach (i, listener; listeners)
		{
			if (listener == handler)
			{
				listeners = listeners[0 .. i] ~ listeners[i + 1 .. $];
				return;
			}
		}
	}

	/// Invoke every subscribed handler, in order, with the given arguments.
	void fire(T args)
	{
		// Iterate over a snapshot so a handler may safely (dis)connect during
		// dispatch without disturbing this fire.
		auto snapshot = listeners;
		foreach (listener; snapshot)
			listener(args);
	}

	/// Number of currently-subscribed handlers.
	size_t length() const @safe pure nothrow @nogc
	{
		return listeners.length;
	}

	/// Remove all handlers.
	void clear() @safe pure nothrow @nogc
	{
		listeners = null;
	}
}

/// A handler taking no arguments — e.g. a button click.
alias Action = void delegate();

/// A handler receiving a selected item index.
alias SelectionEvent = void delegate(int index);

/// A handler receiving keyboard event details.
alias KeyEvent = void delegate(KeyEventArgs args);

/// A handler receiving mouse event details.
alias MouseEvent = void delegate(MouseEventArgs args);

/// A handler receiving a text payload.
alias TextEvent = void delegate(string text);

/// Mouse buttons reported by `MouseEventArgs`.
enum MouseButton
{
	none,
	left,
	right,
	middle,
}

/**
 * Details of a keyboard event.
 *
 * Set `handled = true` in a handler to indicate the key was consumed and that
 * further default processing should be suppressed.
 */
struct KeyEventArgs
{
	uint keyCode;
	bool ctrl;
	bool shift;
	bool alt;
	bool handled;
}

/// Details of a mouse event, in client coordinates.
struct MouseEventArgs
{
	int x;
	int y;
	MouseButton button;
}

unittest
{
	// Register a handler, fire, verify it was called.
	Event!() ev;
	int count;
	void onFire() { ++count; }

	ev ~= &onFire;
	ev.fire();
	assert(count == 1);
	assert(ev.length == 1);
}

unittest
{
	// Multiple handlers are all invoked, in registration order.
	Event!() ev;
	int[] order;
	void first() { order ~= 1; }
	void second() { order ~= 2; }

	ev ~= &first;
	ev ~= &second;
	ev.fire();
	assert(order == [1, 2]);
}

unittest
{
	// Disconnecting a handler stops it from being called.
	Event!() ev;
	int a, b;
	void ha() { ++a; }
	void hb() { ++b; }

	ev ~= &ha;
	ev ~= &hb;
	ev.disconnect(&ha);
	ev.fire();
	assert(a == 0);
	assert(b == 1);
	assert(ev.length == 1);
}

unittest
{
	// Firing with no handlers does not crash.
	Event!() ev;
	ev.fire();

	Event!(int) evi;
	evi.fire(7);
}

unittest
{
	// Arguments are delivered to handlers.
	Event!(int, string) ev;
	int gotInt;
	string gotStr;
	void handler(int i, string s) { gotInt = i; gotStr = s; }

	ev ~= &handler;
	ev.fire(42, "hello");
	assert(gotInt == 42);
	assert(gotStr == "hello");
}

unittest
{
	// Disconnecting an unknown handler is a harmless no-op.
	Event!() ev;
	void known() {}
	void unknown() {}

	ev ~= &known;
	ev.disconnect(&unknown);
	assert(ev.length == 1);
}
