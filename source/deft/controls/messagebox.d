/**
 * Standard message boxes.
 *
 * A thin wrapper over `MessageBoxW` that maps a small style enum to the right
 * icon and buttons and returns a `DialogResult`. The native message box is
 * fully accessible — screen readers announce the title, icon, message and
 * buttons automatically.
 */
module deft.controls.messagebox;

version (Windows):

import core.sys.windows.windows;

import deft.controls.dialog : DialogResult;
import deft.util.strings;
import deft.widget : Widget;

/// The icon (and, for `question`, the buttons) a message box shows.
enum MessageBoxStyle
{
	/// Informational message with an "i" icon and an OK button.
	info,
	/// Warning with a "!" icon and an OK button.
	warning,
	/// Error with a stop icon and an OK button.
	error,
	/// Question with a "?" icon and Yes/No buttons.
	question,
}

/**
 * Show a modal message box owned by `parent`.
 *
 * `info`, `warning` and `error` show a single OK button (returning
 * `DialogResult.ok`); `question` shows Yes/No (returning `DialogResult.yes` or
 * `DialogResult.no`). Closing the box maps to `cancel`/`no` as the platform
 * dictates.
 */
DialogResult showMessageBox(Widget parent, string text, string title,
	MessageBoxStyle style)
{
	HWND owner = parent !is null && parent.handle !is null
		? GetAncestor(parent.handle, GA_ROOT) : null;

	UINT flags;
	final switch (style)
	{
	case MessageBoxStyle.info:
		flags = MB_OK | MB_ICONINFORMATION;
		break;
	case MessageBoxStyle.warning:
		flags = MB_OK | MB_ICONWARNING;
		break;
	case MessageBoxStyle.error:
		flags = MB_OK | MB_ICONERROR;
		break;
	case MessageBoxStyle.question:
		flags = MB_YESNO | MB_ICONQUESTION;
		break;
	}

	int result = MessageBoxW(owner, text.toWStringz, title.toWStringz, flags);
	switch (result)
	{
	case IDOK:
		return DialogResult.ok;
	case IDYES:
		return DialogResult.yes;
	case IDNO:
		return DialogResult.no;
	default:
		return DialogResult.cancel;
	}
}
