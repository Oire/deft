/**
 * Push buttons and the two-state / grouped button controls.
 *
 * All four classes here wrap the Win32 `"BUTTON"` class with different styles:
 * `Button` is a plain push button, `CheckBox` an auto check box, and
 * `RadioButton` an auto radio button (optionally starting a new group). Each is
 * interactive (`WS_TABSTOP`) and exposes a delegate event fired on click.
 */
module deft.controls.button;

version (Windows):

import core.sys.windows.windows;

import deft.controls.control;
import deft.events;
import deft.widget;

/// A standard clickable push button.
class Button : Control
{
	/// Fired when the button is clicked (`BN_CLICKED`).
	Event!() onClicked;

	/// Create a push button captioned `text` inside `parent`.
	this(Widget parent, string text)
	{
		super(parent, "BUTTON", BS_PUSHBUTTON | WS_TABSTOP);
		setText(text);
	}

	/// Fire `onClicked` on a `BN_CLICKED` notification.
	override bool processCommand(ushort notificationCode)
	{
		if (notificationCode == BN_CLICKED)
		{
			onClicked.fire();
			return true;
		}
		return false;
	}

	/// Buttons prefer a modest fixed size.
	override Size getPreferredSize()
	{
		return Size(100, 30);
	}
}

/// A labeled two-state check box.
class CheckBox : Control
{
	/// Fired when the check box is toggled (`BN_CLICKED`).
	Event!() onToggled;

	/// Create a check box captioned `text` inside `parent`.
	this(Widget parent, string text)
	{
		super(parent, "BUTTON", BS_AUTOCHECKBOX | WS_TABSTOP);
		setText(text);
	}

	/// Whether the box is currently checked.
	bool isChecked()
	{
		return SendMessageW(handle, BM_GETCHECK, 0, 0) == BST_CHECKED;
	}

	/// Set the checked state.
	void setChecked(bool value)
	{
		SendMessageW(handle, BM_SETCHECK, value ? BST_CHECKED : BST_UNCHECKED, 0);
	}

	/// Fire `onToggled` on a `BN_CLICKED` notification.
	override bool processCommand(ushort notificationCode)
	{
		if (notificationCode == BN_CLICKED)
		{
			onToggled.fire();
			return true;
		}
		return false;
	}

	/// Check boxes prefer room for their caption.
	override Size getPreferredSize()
	{
		return Size(120, 24);
	}
}

/// A labeled radio button; one selection per group.
class RadioButton : Control
{
	/// Fired when the radio button is selected (`BN_CLICKED`).
	Event!() onSelected;

	/**
	 * Create a radio button captioned `text` inside `parent`.
	 *
	 * Pass `firstInGroup = true` for the first button of a group. That button is
	 * the group's single tab stop (`WS_TABSTOP`) and starts the group; the
	 * remaining buttons are reached with the arrow keys, not Tab. A non-first
	 * button therefore drops both its tab stop and the `WS_GROUP` the control base
	 * adds by default, so it continues the previous button's group instead of
	 * starting a new one. End the group by giving the next control `WS_GROUP`
	 * (every Deft control has it by default, so a following non-radio control
	 * terminates the group automatically).
	 */
	this(Widget parent, string text, bool firstInGroup = false)
	{
		DWORD style = BS_AUTORADIOBUTTON;
		if (firstInGroup)
			style |= WS_TABSTOP; // WS_GROUP comes from the control base
		super(parent, "BUTTON", style);

		if (!firstInGroup)
		{
			// Continue the previous radio button's group: a continuation button is
			// not a tab stop and must not start a new group.
			auto s = GetWindowLongW(handle, GWL_STYLE);
			SetWindowLongW(handle, GWL_STYLE, s & ~WS_GROUP);
		}

		setText(text);
	}

	/// Whether this radio button is currently selected.
	bool isChecked()
	{
		return SendMessageW(handle, BM_GETCHECK, 0, 0) == BST_CHECKED;
	}

	/// Set the selected state.
	void setChecked(bool value)
	{
		SendMessageW(handle, BM_SETCHECK, value ? BST_CHECKED : BST_UNCHECKED, 0);
	}

	/// Fire `onSelected` on a `BN_CLICKED` notification.
	override bool processCommand(ushort notificationCode)
	{
		if (notificationCode == BN_CLICKED)
		{
			onSelected.fire();
			return true;
		}
		return false;
	}

	/// Radio buttons prefer room for their caption.
	override Size getPreferredSize()
	{
		return Size(120, 24);
	}
}
