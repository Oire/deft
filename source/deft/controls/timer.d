/**
 * Periodic and one-shot timers.
 *
 * `Timer` wraps the Win32 `SetTimer`/`KillTimer` pair. A timer is owned by a
 * `Widget` (whose window receives the `WM_TIMER` messages) and fires its
 * `onTick` event on each tick. The master window procedure routes `WM_TIMER`
 * here by timer id.
 *
 * Timer ids are small integers from a process-wide counter, never object
 * pointers — D's garbage collector may relocate an object, which would
 * invalidate a pointer used as an id and misroute ticks.
 */
module deft.controls.timer;

version (Windows):

import core.sys.windows.windows;

import deft.events;
import deft.widget : Widget;

private __gshared Timer[uint] g_timers;
private __gshared uint g_nextTimerId = 1;

/**
 * Dispatch a `WM_TIMER` to its `Timer`'s `onTick`.
 *
 * Returns `true` if a live timer with the given id was found. A one-shot timer
 * stops itself after firing.
 */
bool dispatchTimer(uint id)
{
	if (auto timer = id in g_timers)
	{
		auto t = *timer;
		t.onTick.fire();
		if (t.oneShot_)
			t.stop();
		return true;
	}
	return false;
}

/// A repeating or one-shot timer bound to an owner widget's window.
class Timer
{
	private Widget owner_;
	private uint id_;
	private bool running_;
	private bool oneShot_;

	/// Fired on every tick.
	Event!() onTick;

	/**
	 * Create a timer owned by `owner`.
	 *
	 * The owner's window receives the underlying `WM_TIMER` messages, so the
	 * owner must have a live handle while the timer runs.
	 */
	this(Widget owner)
	{
		owner_ = owner;
		id_ = g_nextTimerId++;
	}

	/// Whether the timer is currently running.
	bool isRunning() const @safe pure nothrow @nogc
	{
		return running_;
	}

	/**
	 * Start (or restart) the timer.
	 *
	 * Params:
	 *   intervalMs = tick interval in milliseconds.
	 *   oneShot    = when true, the timer stops itself after the first tick.
	 */
	void start(int intervalMs, bool oneShot = false)
	{
		if (owner_ is null || owner_.handle is null)
			return;
		oneShot_ = oneShot;
		g_timers[id_] = this;
		SetTimer(owner_.handle, id_, cast(UINT) intervalMs, null);
		running_ = true;
	}

	/// Stop the timer. Safe to call when not running.
	void stop()
	{
		if (!running_)
			return;
		if (owner_ !is null && owner_.handle !is null)
			KillTimer(owner_.handle, id_);
		g_timers.remove(id_);
		running_ = false;
	}
}
