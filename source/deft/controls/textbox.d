/**
 * Single- and multi-line text entry control.
 *
 * `TextBox` wraps the native Win32 `"EDIT"` control. It supports single-line and
 * multi-line variants, an optional read-only flag, selection helpers, and a
 * delegate-based change/keyboard event surface. Because it is a real native
 * control, it carries MSAA accessibility for free.
 */
module deft.controls.textbox;

version (Windows):

import core.sys.windows.windows;

import deft.controls.control;
import deft.events;
import deft.util.strings;
import deft.widget;

/// The flavor of text box to create.
enum TextBoxStyle
{
	/// One line of text, no wrapping.
	singleLine,
	/// Multiple lines with vertical scrolling and Enter inserting newlines.
	multiLine,
	/// Single line, not user-editable.
	singleLineReadOnly,
	/// Multiple lines, not user-editable.
	multiLineReadOnly,
}

/// A native text entry field built on the Win32 `EDIT` control.
class TextBox : Control
{
	private bool multiline_;

	/// Fired when the text changes (`EN_CHANGE`); carries the new text.
	Event!(string) onTextChanged;

	/// Fired on a key press while the control has focus.
	Event!(KeyEventArgs) onKeyDown;

	/**
	 * Create a text box.
	 *
	 * `initialText` is placed in the control if non-empty. `style` selects the
	 * single/multi-line and read-only behavior.
	 */
	this(Widget parent, string initialText = "", TextBoxStyle style = TextBoxStyle.singleLine)
	{
		multiline_ = (style == TextBoxStyle.multiLine
			|| style == TextBoxStyle.multiLineReadOnly);

		DWORD editStyle = WS_TABSTOP | WS_BORDER;
		if (multiline_)
			editStyle |= ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL;
		else
			editStyle |= ES_AUTOHSCROLL;

		if (style == TextBoxStyle.singleLineReadOnly
			|| style == TextBoxStyle.multiLineReadOnly)
			editStyle |= ES_READONLY;

		super(parent, "EDIT", editStyle);

		if (initialText.length != 0)
			setText(initialText);

		subclass();
	}

	/// Toggle the read-only state of the control.
	void setReadOnly(bool ro)
	{
		SendMessageW(handle, EM_SETREADONLY, ro ? TRUE : FALSE, 0);
	}

	/// Select all the text in the control.
	void selectAll()
	{
		SendMessageW(handle, EM_SETSEL, 0, -1);
	}

	/// Return the current selection as `[start, end]` character offsets.
	int[2] getSelectionRange()
	{
		DWORD start;
		DWORD end;
		SendMessageW(handle, EM_GETSEL, cast(WPARAM)&start, cast(LPARAM)&end);
		return [cast(int) start, cast(int) end];
	}

	/// Append text at the end of the control, moving the caret there first.
	void appendText(string text)
	{
		int len = cast(int) SendMessageW(handle, WM_GETTEXTLENGTH, 0, 0);
		SendMessageW(handle, EM_SETSEL, len, len);
		SendMessageW(handle, EM_REPLACESEL, FALSE, cast(LPARAM) text.toWStringz);
	}

	/// Fire `onTextChanged` on `EN_CHANGE` notifications.
	override bool processCommand(ushort notificationCode)
	{
		if (notificationCode == EN_CHANGE)
		{
			onTextChanged.fire(getText());
			return true;
		}
		return false;
	}

	/// Intercept `WM_KEYDOWN` to surface `onKeyDown` and allow suppression.
	override bool processSubclassed(UINT msg, WPARAM wParam, LPARAM lParam, ref LRESULT result)
	{
		if (msg == WM_KEYDOWN)
		{
			// A multi-line edit reports DLGC_WANTALLKEYS, so the dialog manager
			// hands it the Tab key and it inserts a literal tab — a focus trap for
			// keyboard users. Intercept plain Tab and move focus like a dialog
			// would; Ctrl+Tab still falls through to insert a real tab character.
			if (multiline_ && wParam == VK_TAB
				&& (GetKeyState(VK_CONTROL) & 0x8000) == 0)
			{
				bool back = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
				HWND root = GetAncestor(handle, GA_ROOT);
				if (root !is null)
				{
					HWND next = GetNextDlgTabItem(root, handle, back ? TRUE : FALSE);
					if (next !is null && next !is handle)
						SetFocus(next);
				}
				result = 0;
				return true;
			}

			KeyEventArgs args;
			args.keyCode = cast(uint) wParam;
			args.ctrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
			args.shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
			args.alt = (GetKeyState(VK_MENU) & 0x8000) != 0;

			onKeyDown.fire(args);

			if (args.handled)
			{
				result = 0;
				return true;
			}
		}
		return false;
	}

	/// Preferred size: compact for single-line, taller for multi-line.
	override Size getPreferredSize()
	{
		return multiline_ ? Size(160, 80) : Size(160, 24);
	}
}
