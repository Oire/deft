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

/// Horizontal placement of a child within the space available to it.
enum HAlign
{
	/// Stretch to fill the width (the default).
	fill,
	/// Keep the preferred width, against the left edge.
	left,
	/// Keep the preferred width, centered.
	center,
	/// Keep the preferred width, against the right edge.
	right,
}

/// Vertical placement of a child within the space available to it.
enum VAlign
{
	/// Stretch to fill the height (the default).
	fill,
	/// Keep the preferred height, against the top edge.
	top,
	/// Keep the preferred height, centered.
	middle,
	/// Keep the preferred height, against the bottom edge.
	bottom,
}

/// The horizontal offset of a `child`-wide box within `available` for `a`.
private int hOffset(HAlign a, int available, int child) @safe pure nothrow @nogc
{
	final switch (a)
	{
	case HAlign.fill:
	case HAlign.left:
		return 0;
	case HAlign.center:
		return (available - child) / 2;
	case HAlign.right:
		return available - child;
	}
}

/// The vertical offset of a `child`-tall box within `available` for `a`.
private int vOffset(VAlign a, int available, int child) @safe pure nothrow @nogc
{
	final switch (a)
	{
	case VAlign.fill:
	case VAlign.top:
		return 0;
	case VAlign.middle:
		return (available - child) / 2;
	case VAlign.bottom:
		return available - child;
	}
}

/**
 * One placed child of a sizer: a widget or a nested sizer, with its proportion,
 * padding and in-cell alignment.
 *
 * Returned by `Sizer.add`/`addSizer` for fluent configuration — chain
 * `proportion`, `pad`, `alignH`/`alignV` (each returns the same item):
 *
 * ---
 * hbox.add(button).proportion(0).alignV(VAlign.middle).pad(Padding.all(4));
 * vbox.add(label).alignH(HAlign.right);
 * ---
 *
 * By default a child fills its cell on both axes. Setting `alignH`/`alignV` to a
 * non-`fill` value keeps the child's preferred extent on that axis and pins it.
 */
final class SizerItem
{
	private Widget widget_;
	private Sizer sizer_;
	private int proportion_;
	private Padding padding_;
	private Size minSize_;
	private HAlign halign_ = HAlign.fill;
	private VAlign valign_ = VAlign.fill;

	private this(Widget widget, Sizer sizer, int proportion, Padding padding)
	{
		widget_ = widget;
		sizer_ = sizer;
		proportion_ = proportion;
		padding_ = padding;
	}

	/// Set the main-axis weight (0 = keep the preferred size, non-stretching).
	SizerItem proportion(int weight) return
	{
		proportion_ = weight;
		return this;
	}

	/**
	 * Keep the child's preferred size on the main axis — it neither grows nor
	 * shrinks as the container resizes. A readable alias for `proportion(0)`
	 * (the default), so `add(button).fixed()` states the intent at the call site.
	 */
	SizerItem fixed() return
	{
		proportion_ = 0;
		return this;
	}

	/**
	 * Make the child grow to share the container's leftover space, with the given
	 * `weight` (default 1). A readable alias for `proportion(weight)`: two
	 * `stretch()` children split the slack evenly, `stretch(2)` versus `stretch(1)`
	 * splits it 2:1. So `add(list).stretch()` reads as "the list takes the slack."
	 */
	SizerItem stretch(int weight = 1) return
	{
		proportion_ = weight < 1 ? 1 : weight;
		return this;
	}

	/// Reserve padding around the child within its cell.
	SizerItem pad(Padding padding) return
	{
		padding_ = padding;
		return this;
	}

	/// Set the horizontal placement within the cell.
	SizerItem alignH(HAlign horizontal) return
	{
		halign_ = horizontal;
		return this;
	}

	/// Set the vertical placement within the cell.
	SizerItem alignV(VAlign vertical) return
	{
		valign_ = vertical;
		return this;
	}

	/// Override the child's content size (wins over its preferred size).
	SizerItem minSize(Size size) return
	{
		minSize_ = size;
		return this;
	}

	/// The child's content size, before padding.
	private Size contentSize()
	{
		if (minSize_ != Size.init)
			return minSize_;
		if (widget_ !is null)
			return widget_.getPreferredSize();
		if (sizer_ !is null)
			return sizer_.preferredSize();
		return Size.init;
	}

	/// The child's content size plus its padding.
	Size outerSize()
	{
		auto c = contentSize();
		return Size(
			c.width + padding_.left + padding_.right,
			c.height + padding_.top + padding_.bottom);
	}

	/// Place the child into `cell`, insetting by padding and applying alignment.
	void place(Rect cell)
	{
		int innerX = cell.x + padding_.left;
		int innerY = cell.y + padding_.top;
		int innerW = cell.width - padding_.left - padding_.right;
		int innerH = cell.height - padding_.top - padding_.bottom;
		if (innerW < 0)
			innerW = 0;
		if (innerH < 0)
			innerH = 0;

		int x = innerX, y = innerY, w = innerW, h = innerH;

		if (halign_ != HAlign.fill || valign_ != VAlign.fill)
		{
			auto content = contentSize();
			if (halign_ != HAlign.fill)
			{
				w = content.width < innerW ? content.width : innerW;
				x = innerX + hOffset(halign_, innerW, w);
			}
			if (valign_ != VAlign.fill)
			{
				h = content.height < innerH ? content.height : innerH;
				y = innerY + vOffset(valign_, innerH, h);
			}
		}

		if (widget_ !is null)
			widget_.setBounds(Rect(x, y, w, h));
		else if (sizer_ !is null)
			sizer_.layout(Rect(x, y, w, h));
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

	/**
	 * Add a widget child and return its `SizerItem` for fluent configuration:
	 * `box.add(w).proportion(1).pad(Padding.all(8)).alignV(VAlign.middle)`. A bare
	 * `add(w)` gives a non-stretching child (proportion 0) with no padding.
	 */
	SizerItem add(Widget widget)
	{
		auto item = new SizerItem(widget, null, 0, Padding.init);
		items ~= item;
		return item;
	}

	/// Add a nested sizer and return its `SizerItem` for fluent configuration.
	SizerItem addSizer(Sizer sizer)
	{
		auto item = new SizerItem(null, sizer, 0, Padding.init);
		items ~= item;
		return item;
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
			if (it.proportion_ > 0)
			{
				totalProp += it.proportion_;
				fixedMain += it.padding_.left + it.padding_.right;
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
			if (it.proportion_ == 0)
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
					content = flexible * it.proportion_ / totalProp;
					allocated += content;
				}
				outerW = content + it.padding_.left + it.padding_.right;
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
			if (it.proportion_ > 0)
			{
				totalProp += it.proportion_;
				fixedMain += it.padding_.top + it.padding_.bottom;
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
			if (it.proportion_ == 0)
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
					content = flexible * it.proportion_ / totalProp;
					allocated += content;
				}
				outerH = content + it.padding_.top + it.padding_.bottom;
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

/// How a grid track (one column or one row) is sized.
enum GridTrackKind
{
	/// Size to the largest preferred size of the cells in the track.
	autoSize,
	/// A fixed size in device pixels.
	absolute,
	/// A weighted share of the space left after auto and absolute tracks.
	percent,
}

/**
 * The size rule for one column or row of a `Grid`.
 *
 * Build with the factory helpers: `GridTrack.autoSize` (fit the content),
 * `GridTrack.pixels(n)` (a fixed width/height), or `GridTrack.percent(w)` (a
 * weighted share of the leftover space — the weights of all percent tracks are
 * summed, so two `percent(50)` tracks split the remainder evenly, exactly like
 * two `percent(1)` tracks would).
 */
struct GridTrack
{
	/// The sizing rule.
	GridTrackKind kind;

	/// Pixels for `absolute`, weight for `percent`, ignored for `autoSize`.
	int value;

	/// A track sized to its content.
	static GridTrack autoSize() @safe pure nothrow @nogc
	{
		return GridTrack(GridTrackKind.autoSize, 0);
	}

	/// A track of fixed pixel size.
	static GridTrack pixels(int px) @safe pure nothrow @nogc
	{
		return GridTrack(GridTrackKind.absolute, px);
	}

	/// A track taking a `weight`-proportioned share of the leftover space.
	static GridTrack percent(int weight) @safe pure nothrow @nogc
	{
		return GridTrack(GridTrackKind.percent, weight);
	}
}

/**
 * A placed grid child, returned by `Grid.add`/`Grid.addSizer` for fluent
 * configuration:
 *
 * ---
 * grid.add(banner, 0, 0).span(2, 1);
 * grid.add(label, 0, 1).aligned(HAlign.right, VAlign.middle).pad(Padding.all(4));
 * ---
 *
 * Every modifier returns the same `GridItem`, so calls chain. The grid reads the
 * item's final state at layout time, so configuration may continue after `add`.
 * Alignment uses the same `HAlign`/`VAlign` as the box sizers.
 */
final class GridItem
{
	private SizerItem item;
	private int column;
	private int row;
	private int columnSpan = 1;
	private int rowSpan = 1;

	/// Make the child cover `columns` columns and `rows` rows from its cell.
	GridItem span(int columns, int rows = 1) return
	{
		columnSpan = columns < 1 ? 1 : columns;
		rowSpan = rows < 1 ? 1 : rows;
		return this;
	}

	/// Set horizontal and vertical alignment within the cell.
	GridItem aligned(HAlign horizontal, VAlign vertical) return
	{
		item.alignH(horizontal);
		item.alignV(vertical);
		return this;
	}

	/// Set the horizontal alignment within the cell.
	GridItem alignH(HAlign horizontal) return
	{
		item.alignH(horizontal);
		return this;
	}

	/// Set the vertical alignment within the cell.
	GridItem alignV(VAlign vertical) return
	{
		item.alignV(vertical);
		return this;
	}

	/// Reserve padding around the child inside its cell.
	GridItem pad(Padding padding) return
	{
		item.pad(padding);
		return this;
	}
}

/**
 * A table layout: a fixed grid of columns and rows, each independently sized to
 * its content (`autoSize`), a fixed pixel size (`absolute`) or a weighted share
 * of the leftover space (`percent`). Widgets and nested sizers are placed into
 * cells by column/row and may span several columns or rows. Within its cell a
 * child fills the available space by default, or keeps its preferred size and
 * aligns (start/center/end) — see `GridItem`.
 *
 * This is Deft's analog of WinForms' `TableLayoutPanel`: pick the column and row
 * counts, mark each track auto or percent (or pixels), and drop children into
 * cells without computing any coordinates. `add` returns a `GridItem` whose
 * fluent `span`/`aligned`/`pad` methods read better than positional arguments:
 *
 * ---
 * auto grid = new Grid(2, 2);
 * grid.setColumn(0, GridTrack.autoSize);
 * grid.setColumn(1, GridTrack.percent(100));
 * grid.add(label, 0, 0).aligned(HAlign.right, VAlign.middle);
 * grid.add(field, 1, 0);                       // fills its cell
 * grid.add(footer, 0, 1).span(2, 1);           // spans both columns
 * ---
 *
 * Tracks default to `autoSize`. Auto track sizes are measured from the cells
 * that do not span (a spanning child is placed across the already-computed
 * tracks but does not enlarge them).
 */
class Grid : Sizer
{
	private GridItem[] cells_;
	private GridTrack[] columns_;
	private GridTrack[] rows_;
	private int hgap_;
	private int vgap_;

	/// Create a grid with `columns` columns and `rows` rows, all `autoSize`.
	this(int columns, int rows)
	{
		if (columns < 0)
			columns = 0;
		if (rows < 0)
			rows = 0;
		columns_ = new GridTrack[columns];
		rows_ = new GridTrack[rows];
		foreach (ref c; columns_)
			c = GridTrack.autoSize;
		foreach (ref r; rows_)
			r = GridTrack.autoSize;
	}

	/// Number of columns.
	int columnCount() const @safe pure nothrow @nogc
	{
		return cast(int) columns_.length;
	}

	/// Number of rows.
	int rowCount() const @safe pure nothrow @nogc
	{
		return cast(int) rows_.length;
	}

	/// Set the sizing rule for column `index`.
	void setColumn(int index, GridTrack track)
	{
		if (index >= 0 && index < columns_.length)
			columns_[index] = track;
	}

	/// Set the sizing rule for row `index`.
	void setRow(int index, GridTrack track)
	{
		if (index >= 0 && index < rows_.length)
			rows_[index] = track;
	}

	/// Set the pixel gap between columns (`horizontal`) and rows (`vertical`).
	void setSpacing(int horizontal, int vertical)
	{
		hgap_ = horizontal < 0 ? 0 : horizontal;
		vgap_ = vertical < 0 ? 0 : vertical;
	}

	/**
	 * Place `widget` in the cell at `column`/`row`. Returns a `GridItem` whose
	 * fluent `span`/`aligned`/`alignH`/`alignV`/`pad` methods configure it.
	 */
	GridItem add(Widget widget, int column, int row)
	{
		auto cell = new GridItem;
		cell.item = new SizerItem(widget, null, 0, Padding.init);
		cell.column = column;
		cell.row = row;
		cells_ ~= cell;
		return cell;
	}

	/// Place a nested `sizer` in the cell at `column`/`row`; see `add`.
	GridItem addSizer(Sizer sizer, int column, int row)
	{
		auto cell = new GridItem;
		cell.item = new SizerItem(null, sizer, 0, Padding.init);
		cell.column = column;
		cell.row = row;
		cells_ ~= cell;
		return cell;
	}

	/// Number of placed children.
	override size_t length() const @safe pure nothrow @nogc
	{
		return cells_.length;
	}

	override void layout(Rect area)
	{
		if (columns_.length == 0 || rows_.length == 0)
			return;

		auto colSizes = resolveTracks(columns_, area.width, hgap_, true);
		auto rowSizes = resolveTracks(rows_, area.height, vgap_, false);

		auto colOffsets = trackOffsets(colSizes, hgap_, area.x);
		auto rowOffsets = trackOffsets(rowSizes, vgap_, area.y);

		foreach (c; cells_)
		{
			if (c.column < 0 || c.row < 0
				|| c.column >= columns_.length || c.row >= rows_.length)
				continue;

			immutable int lastCol = spanEnd(c.column, c.columnSpan, cast(int) columns_.length);
			immutable int lastRow = spanEnd(c.row, c.rowSpan, cast(int) rows_.length);

			immutable int x = colOffsets[c.column];
			immutable int y = rowOffsets[c.row];
			immutable int w = colOffsets[lastCol] + colSizes[lastCol] - x;
			immutable int h = rowOffsets[lastRow] + rowSizes[lastRow] - y;

			// SizerItem.place applies the item's padding and alignment.
			c.item.place(Rect(x, y, w, h));
		}
	}

	override Size preferredSize()
	{
		Size total;
		foreach (i; 0 .. columns_.length)
			total.width += preferredTrackSize(columns_[i], cast(int) i, true);
		foreach (i; 0 .. rows_.length)
			total.height += preferredTrackSize(rows_[i], cast(int) i, false);
		if (columns_.length > 1)
			total.width += hgap_ * (cast(int) columns_.length - 1);
		if (rows_.length > 1)
			total.height += vgap_ * (cast(int) rows_.length - 1);
		return total;
	}

	/// The largest preferred extent of the non-spanning cells in a track.
	private int autoTrackSize(int index, bool horizontal)
	{
		int best;
		foreach (c; cells_)
		{
			immutable int span = horizontal ? c.columnSpan : c.rowSpan;
			immutable int at = horizontal ? c.column : c.row;
			if (span != 1 || at != index)
				continue;
			auto s = c.item.outerSize();
			immutable int extent = horizontal ? s.width : s.height;
			if (extent > best)
				best = extent;
		}
		return best;
	}

	/// The size a track contributes to `preferredSize` (percent uses its content).
	private int preferredTrackSize(GridTrack track, int index, bool horizontal)
	{
		final switch (track.kind)
		{
		case GridTrackKind.absolute:
			return track.value;
		case GridTrackKind.autoSize:
		case GridTrackKind.percent:
			return autoTrackSize(index, horizontal);
		}
	}

	/// Resolve every track to a concrete pixel size within `available`.
	private int[] resolveTracks(GridTrack[] tracks, int available, int gap,
		bool horizontal)
	{
		immutable int n = cast(int) tracks.length;
		auto sizes = new int[n];

		int used = n > 1 ? gap * (n - 1) : 0;
		int totalPercent;
		int lastPercent = -1;
		foreach (i, t; tracks)
		{
			final switch (t.kind)
			{
			case GridTrackKind.absolute:
				sizes[i] = t.value;
				used += sizes[i];
				break;
			case GridTrackKind.autoSize:
				sizes[i] = autoTrackSize(cast(int) i, horizontal);
				used += sizes[i];
				break;
			case GridTrackKind.percent:
				totalPercent += t.value;
				lastPercent = cast(int) i;
				break;
			}
		}

		int remaining = available - used;
		if (remaining < 0)
			remaining = 0;

		int allocated;
		foreach (i, t; tracks)
		{
			if (t.kind != GridTrackKind.percent)
				continue;
			int size;
			if (cast(int) i == lastPercent)
				size = remaining - allocated; // last gets the rounding remainder
			else
			{
				size = totalPercent > 0 ? remaining * t.value / totalPercent : 0;
				allocated += size;
			}
			sizes[i] = size;
		}
		return sizes;
	}

	/// Prefix offsets (in screen/parent coordinates) for a resolved track list.
	private static int[] trackOffsets(int[] sizes, int gap, int origin)
	{
		auto offsets = new int[sizes.length];
		int pos = origin;
		foreach (i, s; sizes)
		{
			offsets[i] = pos;
			pos += s + gap;
		}
		return offsets;
	}

	/// The index of the last track a span covers, clamped to the track count.
	private static int spanEnd(int start, int span, int count)
	{
		int last = start + span - 1;
		if (last >= count)
			last = count - 1;
		if (last < start)
			last = start;
		return last;
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
	box.add(w).proportion(1);
	box.layout(Rect(0, 0, 100, 50));
	assert(w.bounds == Rect(0, 0, 100, 50));
}

unittest
{
	// Two equal-proportion children split the width evenly.
	auto a = new FakeWidget(Size(0, 0));
	auto b = new FakeWidget(Size(0, 0));
	auto box = new HBox();
	box.add(a).proportion(1);
	box.add(b).proportion(1);
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
	box.add(a).proportion(2);
	box.add(b).proportion(1);
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
	box.add(fixed);
	box.add(flex).proportion(1);
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
	inner.add(top).proportion(1);
	inner.add(bottom).proportion(1);

	auto outer = new HBox();
	outer.add(left).proportion(1);
	outer.addSizer(inner).proportion(1);

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
	box.add(w).proportion(1).pad(Padding.all(5));
	box.layout(Rect(0, 0, 100, 100));
	assert(w.bounds == Rect(5, 5, 90, 90));
}

unittest
{
	// Zero available space must not crash and yields empty bounds.
	auto w = new FakeWidget(Size(0, 0));
	auto box = new HBox();
	box.add(w).proportion(1);
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

unittest
{
	// Grid: two 50% columns and one 100% row split the width evenly and fill it.
	auto a = new FakeWidget(Size(10, 10));
	auto b = new FakeWidget(Size(10, 10));
	auto grid = new Grid(2, 1);
	grid.setColumn(0, GridTrack.percent(50));
	grid.setColumn(1, GridTrack.percent(50));
	grid.setRow(0, GridTrack.percent(100));
	grid.add(a, 0, 0);
	grid.add(b, 1, 0);
	grid.layout(Rect(0, 0, 100, 40));
	assert(a.bounds == Rect(0, 0, 50, 40));
	assert(b.bounds == Rect(50, 0, 50, 40));
}

unittest
{
	// Grid: an auto column keeps its content width; a percent column takes the
	// rest. Two auto rows stack at their content heights.
	auto label = new FakeWidget(Size(30, 12));
	auto field = new FakeWidget(Size(0, 12));
	auto grid = new Grid(2, 1);
	grid.setColumn(0, GridTrack.autoSize);
	grid.setColumn(1, GridTrack.percent(100));
	grid.setRow(0, GridTrack.percent(100));
	grid.add(label, 0, 0);
	grid.add(field, 1, 0);
	grid.layout(Rect(0, 0, 200, 20));
	assert(label.bounds == Rect(0, 0, 30, 20));
	assert(field.bounds == Rect(30, 0, 170, 20));
}

unittest
{
	// Grid: absolute pixel column, padding inside a cell, and spacing between
	// columns are all honored.
	auto a = new FakeWidget(Size(0, 0));
	auto b = new FakeWidget(Size(0, 0));
	auto grid = new Grid(2, 1);
	grid.setColumn(0, GridTrack.pixels(40));
	grid.setColumn(1, GridTrack.percent(100));
	grid.setRow(0, GridTrack.percent(100));
	grid.setSpacing(10, 0);
	grid.add(a, 0, 0);
	grid.add(b, 1, 0).pad(Padding.all(5));
	grid.layout(Rect(0, 0, 100, 30));
	// Column 0 = 40px, 10px gap, column 1 = remaining 50px starting at x=50.
	assert(a.bounds == Rect(0, 0, 40, 30));
	assert(b.bounds == Rect(55, 5, 40, 20));
}

unittest
{
	// Grid: a child spanning two columns covers both tracks plus the gap between.
	auto wide = new FakeWidget(Size(0, 0));
	auto grid = new Grid(2, 2);
	grid.setColumn(0, GridTrack.percent(50));
	grid.setColumn(1, GridTrack.percent(50));
	grid.setRow(0, GridTrack.percent(50));
	grid.setRow(1, GridTrack.percent(50));
	grid.setSpacing(10, 10);
	grid.add(wide, 0, 0).span(2, 1);
	grid.layout(Rect(0, 0, 210, 110));
	// Each column = (210-10)/2 = 100; the span covers 100 + 10 gap + 100 = 210.
	// Each row = (110-10)/2 = 50.
	assert(wide.bounds == Rect(0, 0, 210, 50));
}

unittest
{
	// Grid: preferredSize sums absolute/auto track sizes plus spacing; a degenerate
	// grid lays out without crashing.
	auto grid = new Grid(2, 1);
	grid.setColumn(0, GridTrack.pixels(40));
	grid.setColumn(1, GridTrack.autoSize);
	grid.setRow(0, GridTrack.autoSize);
	grid.setSpacing(8, 0);
	grid.add(new FakeWidget(Size(0, 0)), 0, 0);
	grid.add(new FakeWidget(Size(25, 16)), 1, 0);
	assert(grid.preferredSize() == Size(40 + 25 + 8, 16));

	auto empty = new Grid(0, 0);
	empty.layout(Rect(0, 0, 100, 100)); // must not crash
	assert(empty.length == 0);
}

unittest
{
	// Grid alignment: a fixed-size child centered in a larger cell keeps its size
	// and sits in the middle; fill (the default) stretches.
	auto centered = new FakeWidget(Size(20, 10));
	auto grid = new Grid(1, 1);
	grid.setColumn(0, GridTrack.percent(100));
	grid.setRow(0, GridTrack.percent(100));
	grid.add(centered, 0, 0).aligned(HAlign.center, VAlign.middle);
	grid.layout(Rect(0, 0, 100, 50));
	assert(centered.bounds == Rect(40, 20, 20, 10)); // (100-20)/2, (50-10)/2

	// right/top alignment pins to the right/top edges.
	auto pinned = new FakeWidget(Size(20, 10));
	auto g2 = new Grid(1, 1);
	g2.setColumn(0, GridTrack.percent(100));
	g2.setRow(0, GridTrack.percent(100));
	g2.add(pinned, 0, 0).alignH(HAlign.right).alignV(VAlign.top);
	g2.layout(Rect(0, 0, 100, 50));
	assert(pinned.bounds == Rect(80, 0, 20, 10));
}

unittest
{
	// Fluent box placement: proportion set via the returned handle matches the
	// positional form (2:1 split of 90px into 60 and 30).
	auto a = new FakeWidget(Size(0, 0));
	auto b = new FakeWidget(Size(0, 0));
	auto box = new HBox();
	box.add(a).proportion(2);
	box.add(b).proportion(1);
	box.layout(Rect(0, 0, 90, 10));
	assert(a.bounds == Rect(0, 0, 60, 10));
	assert(b.bounds == Rect(60, 0, 30, 10));
}

unittest
{
	// fixed()/stretch() aliases match the equivalent proportion() forms: a fixed
	// child keeps its preferred width and the stretch child takes the rest.
	auto fixedW = new FakeWidget(Size(30, 10));
	auto flex = new FakeWidget(Size(0, 0));
	auto box = new HBox();
	box.add(fixedW).fixed();
	box.add(flex).stretch();
	box.layout(Rect(0, 0, 100, 10));
	assert(fixedW.bounds == Rect(0, 0, 30, 10));
	assert(flex.bounds == Rect(30, 0, 70, 10));

	// Weighted stretch: stretch(2) versus stretch(1) splits 90px into 60 and 30,
	// and stretch(0) is clamped up to weight 1 (it must still grow).
	auto a = new FakeWidget(Size(0, 0));
	auto b = new FakeWidget(Size(0, 0));
	auto two = new HBox();
	two.add(a).stretch(2);
	two.add(b).stretch(0); // clamped to 1
	two.layout(Rect(0, 0, 90, 10));
	assert(a.bounds == Rect(0, 0, 60, 10));
	assert(b.bounds == Rect(60, 0, 30, 10));
}

unittest
{
	// HBox cross-axis (vertical) alignment: a fixed-height child fills the width
	// (proportion 1) but is vertically centered at its preferred height.
	auto w = new FakeWidget(Size(20, 10));
	auto box = new HBox();
	box.add(w).proportion(1).alignV(VAlign.middle);
	box.layout(Rect(0, 0, 100, 50));
	assert(w.bounds == Rect(0, 20, 100, 10)); // y = (50-10)/2

	// VBox cross-axis (horizontal) alignment: right-pinned at preferred width.
	auto w2 = new FakeWidget(Size(20, 10));
	auto vb = new VBox();
	vb.add(w2).proportion(1).alignH(HAlign.right);
	vb.layout(Rect(0, 0, 100, 50));
	assert(w2.bounds == Rect(80, 0, 20, 50)); // x = 100-20
}
