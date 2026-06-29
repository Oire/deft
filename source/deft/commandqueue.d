/**
 * Cross-thread UI communication.
 *
 * Background threads cannot touch Win32 controls directly — those belong to the
 * UI thread. `CommandQueue!T` is a thread-safe FIFO; `UiDispatcher!T` pairs a
 * queue with a target window so a worker can `post` a command and wake the UI
 * thread, which then `drain`s and processes the commands on its own turf.
 *
 * The framework supplies only the mechanism. Applications define their own
 * command type (typically an enum) and the WndProc handling for the wake
 * message.
 */
module deft.commandqueue;

version (Windows):

import core.sync.mutex : Mutex;
import core.sys.windows.windows;

/// Default wake message id, in the `WM_APP`..`0xBFFF` application-reserved range.
enum uint defaultWakeMessage = WM_APP + 1;

/// A thread-safe FIFO queue of `T`.
class CommandQueue(T)
{
	private T[] items;
	private Mutex mutex;

	/// Create an empty queue with its own mutex.
	this()
	{
		mutex = new Mutex();
	}

	/// Append an item. Safe to call from any thread.
	void push(T item)
	{
		synchronized (mutex)
			items ~= item;
	}

	/// Atomically remove and return all queued items, in insertion order.
	T[] drainAll()
	{
		synchronized (mutex)
		{
			auto result = items;
			items = null;
			return result;
		}
	}

	/// Whether the queue currently holds no items.
	bool empty()
	{
		synchronized (mutex)
			return items.length == 0;
	}
}

/**
 * Pairs a `CommandQueue!T` with a target window. `post` enqueues a command and
 * wakes the UI thread with `PostMessageW`; the window's WndProc responds to the
 * wake message by calling `drain` and processing the result.
 */
struct UiDispatcher(T)
{
	/// The backing queue (shared; reference type).
	CommandQueue!T queue;

	/// The window woken on `post`.
	HWND targetHwnd;

	/// The wake message id posted to `targetHwnd`.
	uint messageId = defaultWakeMessage;

	/**
	 * Create a dispatcher targeting `hwnd`, with a fresh backing queue. `messageId`
	 * is the wake message posted to the window on `post` (defaults to
	 * `defaultWakeMessage`).
	 */
	this(HWND hwnd, uint messageId = defaultWakeMessage)
	{
		this.queue = new CommandQueue!T();
		this.targetHwnd = hwnd;
		this.messageId = messageId;
	}

	/// Enqueue a command and wake the target window.
	void post(T command)
	{
		if (queue is null)
			queue = new CommandQueue!T();
		queue.push(command);
		if (targetHwnd !is null)
			PostMessageW(targetHwnd, messageId, 0, 0);
	}

	/// Remove and return all queued commands. Call on the UI thread.
	T[] drain()
	{
		if (queue is null)
			return null;
		return queue.drainAll();
	}
}

unittest
{
	// Push then drain returns everything in order; the queue is then empty.
	auto q = new CommandQueue!int();
	q.push(1);
	q.push(2);
	q.push(3);
	assert(q.drainAll() == [1, 2, 3]);
	assert(q.empty());
}

unittest
{
	// Draining an empty queue yields an empty array and does not block.
	auto q = new CommandQueue!int();
	assert(q.empty());
	assert(q.drainAll().length == 0);
}

unittest
{
	// Push/drain roundtrip with a non-trivial element type.
	auto q = new CommandQueue!string();
	q.push("a");
	q.push("b");
	auto drained = q.drainAll();
	assert(drained == ["a", "b"]);
	assert(q.empty());
}

unittest
{
	// Concurrent pushes from many threads: every item must survive.
	import core.thread : Thread;

	enum threadCount = 8;
	enum perThread = 1000;

	auto q = new CommandQueue!int();
	Thread[] threads;
	foreach (t; 0 .. threadCount)
		threads ~= new Thread({
			foreach (i; 0 .. perThread)
				q.push(i);
		}).start();

	foreach (th; threads)
		th.join();

	auto all = q.drainAll();
	assert(all.length == threadCount * perThread);
}
