/**
 * Layout engine — box sizers.
 *
 * A `Sizer` arranges child widgets (and nested sizers) within a rectangle.
 * `HBox` lays children out horizontally, `VBox` vertically. Each child carries
 * a *proportion*: children with proportion 0 keep their preferred size along the
 * main axis, while the leftover space is shared among the proportional children
 * in proportion to their weights. Per-child `Padding` is reserved around the
 * child's cell.
 *
 * The layout math is pure integer arithmetic with no dependency on a running
 * message loop, so it is exercised directly by unit tests.
 */
module deft.layout;

version (Windows):

import deft.widget : Padding, Rect, Size, Widget;

/**
 * One entry in a sizer: either a widget or a nested sizer, together with its
 * proportion and surrounding padding.
 */
struct SizerItem
{
	/// The child widget, or null when this item holds a nested sizer.
	Widget widget;

	/// The nested sizer, or null when this item holds a widget.
	Sizer sizer;

	/// Main-axis weight; 0 means "use the preferred size" (non-stretching).
	int proportion;

	/// Padding reserved around the child within its cell.
	Padding padding;

	/// Explicit size override; when non-zero it wins over the child's preferred size.
	Size minSize;

	/// The child's content size, before padding.
	private Size contentSize()
	{
		if (minSize != Size.init)
			return minSize;
		if (widget !is null)
			return widget.getPreferredSize();
		if (sizer !is null)
			return sizer.preferredSize();
		return Size.init;
	}

	/// The child's content size plus its padding.
	Size outerSize()
	{
		auto c = contentSize();
		return Size(
			c.width + padding.left + padding.right,
			c.height + padding.top + padding.bottom);
	}

	/// Place the child into `cell`, insetting by the padding.
	void place(Rect cell)
	{
		Rect inner = Rect(
			cell.x + padding.left,
			cell.y + padding.top,
			cell.width - padding.left - padding.right,
			cell.height - padding.top - padding.bottom);
		if (inner.width < 0)
			inner.width = 0;
		if (inner.height < 0)
			inner.height = 0;

		if (widget !is null)
			widget.setBounds(inner);
		else if (sizer !is null)
			sizer.layout(inner);
	}
}

/// Abstract base for box sizers.
abstract class Sizer
{
	protected SizerItem[] items;

	/// Arrange the children within `availableArea`.
	abstract void layout(Rect availableArea);

	/// The natural size this sizer would like, given its children.
	abstract Size preferredSize();

	/// Add a widget child.
	void add(Widget widget, int proportion = 0, Padding padding = Padding.init)
	{
		items ~= SizerItem(widget, null, proportion, padding);
	}

	/// Add a nested sizer.
	void addSizer(Sizer sizer, int proportion = 0, Padding padding = Padding.init)
	{
		items ~= SizerItem(null, sizer, proportion, padding);
	}

	/// Number of child items.
	size_t length() const @safe pure nothrow @nogc
	{
		return items.length;
	}
}

/// Lays children out left to right.
class HBox : Sizer
{
	override void layout(Rect area)
	{
		if (items.length == 0)
			return;

		int totalProp = 0;
		int fixedMain = 0;
		ptrdiff_t lastProp = -1;
		foreach (i, ref it; items)
		{
			if (it.proportion > 0)
			{
				totalProp += it.proportion;
				fixedMain += it.padding.left + it.padding.right;
				lastProp = i;
			}
			else
			{
				fixedMain += it.outerSize().width;
			}
		}

		int flexible = area.width - fixedMain;
		if (flexible < 0)
			flexible = 0;

		int x = area.x;
		int allocated = 0;
		foreach (i, ref it; items)
		{
			int outerW;
			if (it.proportion == 0)
			{
				outerW = it.outerSize().width;
			}
			else
			{
				int content;
				if (i == lastProp)
					content = flexible - allocated;
				else
				{
					content = flexible * it.proportion / totalProp;
					allocated += content;
				}
				outerW = content + it.padding.left + it.padding.right;
			}

			it.place(Rect(x, area.y, outerW, area.height));
			x += outerW;
		}
	}

	override Size preferredSize()
	{
		Size total;
		foreach (ref it; items)
		{
			auto s = it.outerSize();
			total.width += s.width;
			if (s.height > total.height)
				total.height = s.height;
		}
		return total;
	}
}

/// Lays children out top to bottom.
class VBox : Sizer
{
	override void layout(Rect area)
	{
		if (items.length == 0)
			return;

		int totalProp = 0;
		int fixedMain = 0;
		ptrdiff_t lastProp = -1;
		foreach (i, ref it; items)
		{
			if (it.proportion > 0)
			{
				totalProp += it.proportion;
				fixedMain += it.padding.top + it.padding.bottom;
				lastProp = i;
			}
			else
			{
				fixedMain += it.outerSize().height;
			}
		}

		int flexible = area.height - fixedMain;
		if (flexible < 0)
			flexible = 0;

		int y = area.y;
		int allocated = 0;
		foreach (i, ref it; items)
		{
			int outerH;
			if (it.proportion == 0)
			{
				outerH = it.outerSize().height;
			}
			else
			{
				int content;
				if (i == lastProp)
					content = flexible - allocated;
				else
				{
					content = flexible * it.proportion / totalProp;
					allocated += content;
				}
				outerH = content + it.padding.top + it.padding.bottom;
			}

			it.place(Rect(area.x, y, area.width, outerH));
			y += outerH;
		}
	}

	override Size preferredSize()
	{
		Size total;
		foreach (ref it; items)
		{
			auto s = it.outerSize();
			total.height += s.height;
			if (s.width > total.width)
				total.width = s.width;
		}
		return total;
	}
}

version (unittest)
{
	/// A headless widget for layout tests: no native handle, records its bounds.
	private final class FakeWidget : Widget
	{
		private Size pref;

		this(Size preferred)
		{
			pref = preferred;
		}

		override Size getPreferredSize()
		{
			return pref;
		}
	}
}

unittest
{
	// A single proportional child fills the available area.
	auto w = new FakeWidget(Size(10, 10));
	auto box = new VBox();
	box.add(w, 1);
	box.layout(Rect(0, 0, 100, 50));
	assert(w.bounds == Rect(0, 0, 100, 50));
}

unittest
{
	// Two equal-proportion children split the width evenly.
	auto a = new FakeWidget(Size(0, 0));
	auto b = new FakeWidget(Size(0, 0));
	auto box = new HBox();
	box.add(a, 1);
	box.add(b, 1);
	box.layout(Rect(0, 0, 100, 20));
	assert(a.bounds == Rect(0, 0, 50, 20));
	assert(b.bounds == Rect(50, 0, 50, 20));
}

unittest
{
	// A 2:1 proportion ratio splits 90px into 60 and 30.
	auto a = new FakeWidget(Size(0, 0));
	auto b = new FakeWidget(Size(0, 0));
	auto box = new HBox();
	box.add(a, 2);
	box.add(b, 1);
	box.layout(Rect(0, 0, 90, 10));
	assert(a.bounds == Rect(0, 0, 60, 10));
	assert(b.bounds == Rect(60, 0, 30, 10));
}

unittest
{
	// A fixed (proportion 0) child keeps its preferred size; the proportional
	// child takes the rest.
	auto fixed = new FakeWidget(Size(30, 10));
	auto flex = new FakeWidget(Size(0, 0));
	auto box = new HBox();
	box.add(fixed, 0);
	box.add(flex, 1);
	box.layout(Rect(0, 0, 100, 10));
	assert(fixed.bounds == Rect(0, 0, 30, 10));
	assert(flex.bounds == Rect(30, 0, 70, 10));
}

unittest
{
	// Nested sizers: a VBox inside an HBox lays out within its allotted column.
	auto left = new FakeWidget(Size(0, 0));
	auto top = new FakeWidget(Size(0, 0));
	auto bottom = new FakeWidget(Size(0, 0));

	auto inner = new VBox();
	inner.add(top, 1);
	inner.add(bottom, 1);

	auto outer = new HBox();
	outer.add(left, 1);
	outer.addSizer(inner, 1);

	outer.layout(Rect(0, 0, 100, 40));

	// Left column: x 0..50.
	assert(left.bounds == Rect(0, 0, 50, 40));
	// Right column (the VBox) occupies x 50..100 and stacks its children.
	assert(top.bounds == Rect(50, 0, 50, 20));
	assert(bottom.bounds == Rect(50, 20, 50, 20));
}

unittest
{
	// Padding is reserved around the child.
	auto w = new FakeWidget(Size(0, 0));
	auto box = new VBox();
	box.add(w, 1, Padding.all(5));
	box.layout(Rect(0, 0, 100, 100));
	assert(w.bounds == Rect(5, 5, 90, 90));
}

unittest
{
	// Zero available space must not crash and yields empty bounds.
	auto w = new FakeWidget(Size(0, 0));
	auto box = new HBox();
	box.add(w, 1);
	box.layout(Rect(0, 0, 0, 0));
	assert(w.bounds == Rect(0, 0, 0, 0));
}

unittest
{
	// An empty sizer has a zero preferred size and lays out without error.
	auto box = new VBox();
	assert(box.preferredSize() == Size(0, 0));
	box.layout(Rect(0, 0, 100, 100));

	// preferredSize sums the main axis and maxes the cross axis.
	auto h = new HBox();
	h.add(new FakeWidget(Size(20, 8)));
	h.add(new FakeWidget(Size(30, 12)));
	assert(h.preferredSize() == Size(50, 12));
}
