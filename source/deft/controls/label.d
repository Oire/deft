/**
 * A read-only static text label.
 *
 * `Label` wraps the Win32 `"STATIC"` control class with `SS_LEFT` styling. It
 * displays text and is not interactive (it carries no `WS_TABSTOP`), so it is
 * skipped in the keyboard tab order. Its preferred size is computed from the
 * measured extent of its text in the control's own font.
 */
module deft.controls.label;

version (Windows):

import core.sys.windows.windows;

import deft.controls.control;
import deft.util.strings;
import deft.widget;

/// A non-interactive label that displays a single run of static text.
class Label : Control
{
	private string text_;

	/// Create a label showing `text` inside `parent`.
	this(Widget parent, string text)
	{
		super(parent, "STATIC", SS_LEFT);
		setText(text);
	}

	/// Set the label's text, remembering it for size measurement.
	override void setText(string text)
	{
		text_ = text;
		super.setText(text);
	}

	/**
	 * Compute the preferred size from the text extent.
	 *
	 * The control's current font is selected into its device context and the
	 * UTF-16 form of the stored text is measured with `GetTextExtentPoint32W`.
	 * A small height floor keeps short or empty labels from collapsing.
	 */
	override Size getPreferredSize()
	{
		if (handle is null || text_.length == 0)
			return Size(0, 20);

		const(wchar)* wtext = text_.toWStringz;
		int len = 0;
		while (wtext[len] != '\0')
			++len;

		HDC hdc = GetDC(handle);
		if (hdc is null)
			return Size(0, 20);

		HFONT font = cast(HFONT) SendMessageW(handle, WM_GETFONT, 0, 0);
		HGDIOBJ oldFont = font !is null ? SelectObject(hdc, font) : null;

		SIZE sz;
		GetTextExtentPoint32W(hdc, wtext, len, &sz);

		if (font !is null)
			SelectObject(hdc, oldFont);
		ReleaseDC(handle, hdc);

		int height = sz.cy < 20 ? 20 : sz.cy;
		return Size(sz.cx, height);
	}
}
