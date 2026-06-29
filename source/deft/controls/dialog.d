/**
 * Modal dialogs, built on the native Win32 dialog manager.
 *
 * `Dialog` is a real dialog-class window (`#32770`): it is created from an
 * in-memory dialog template with `CreateDialogIndirectParamW` (the runtime
 * equivalent of an `.rc` `DIALOGEX` resource) and driven through
 * `IsDialogMessageW`/`DefDlgProc`. Using the genuine dialog construct means the
 * OS gives us the things a screen reader and keyboard user need, for free:
 *
 * - oleacc reports the window as `ROLE_SYSTEM_DIALOG`, so JAWS and NVDA announce
 *   it as a dialog on open and read its child controls as dialog contents — no
 *   custom `IAccessible` proxy or role annotation required.
 * - The dialog manager handles Tab/Shift+Tab and arrow-key groups, maps Escape
 *   to Cancel and Enter to the default button, and tracks the default push
 *   button — all natively.
 *
 * Content is arranged with a sizer; `addStandardButtons` appends a right-aligned
 * OK/Cancel-style button row wired to dismiss the dialog with the matching
 * `DialogResult`. Controls are ordinary child windows parented to the dialog.
 */
module deft.controls.dialog;

version (Windows):

import core.sys.windows.windows;

import deft.controls.button : Button;
import deft.controls.control : routeCommand, routeNotify;
import deft.controls.label : Label;
import deft.controls.textbox : TextBox, TextBoxStyle;
import deft.i18n : tr;
import deft.layout : HBox, Sizer, VBox;
import deft.util.strings;
import deft.widget;
import deft.platform.win32.init : hInstance;

/// The outcome of a modal dialog.
enum DialogResult
{
	/// The dialog is still open or was dismissed without a decision.
	none,
	/// The user confirmed (OK).
	ok,
	/// The user canceled.
	cancel,
	/// The user answered yes.
	yes,
	/// The user answered no.
	no,
}

/// The set of standard buttons `addStandardButtons` creates.
enum ButtonSet
{
	/// A single OK button.
	ok,
	/// OK and Cancel.
	okCancel,
	/// Yes and No.
	yesNo,
}

/**
 * A modal dialog window.
 *
 * Build content with `setSizer`, optionally add a standard button row, then
 * call `showModal`, which blocks until the dialog is dismissed and returns the
 * `DialogResult`. The dialog's child controls remain valid after `showModal`
 * returns, so their values can be read; call `dispose` when finished with it.
 */
class Dialog : Widget
{
	private HWND parentHandle_;
	private int width_;
	private int height_;
	private DialogResult result_ = DialogResult.none;
	private bool modalDone_;
	private Sizer rootSizer_;
	private Sizer contentSizer_;
	private Sizer buttonSizer_;

	/**
	 * Create a modal dialog parented to `parent` (any widget; the dialog is
	 * owned by, centered on, and modal to that widget's top-level window).
	 */
	this(Widget parent, string title, int width, int height)
	{
		parentHandle_ = parent !is null && parent.handle !is null
			? GetAncestor(parent.handle, GA_ROOT) : null;
		width_ = width;
		height_ = height;
		this.parent_ = parent;

		auto template_ = buildDialogTemplate(title, width, height);

		handle_ = CreateDialogIndirectParamW(
			hInstance(),
			cast(LPCDLGTEMPLATE) template_.ptr,
			parentHandle_,
			&dialogProc,
			cast(LPARAM) cast(void*) this);

		registerHandle();
	}

	/**
	 * Set the dialog's content sizer. The content is laid out above any standard
	 * button row added with `addStandardButtons`.
	 */
	void setSizer(Sizer sizer)
	{
		contentSizer_ = sizer;
		rebuildRoot();
	}

	/// Re-run the root sizer over the dialog's client area.
	void relayout()
	{
		if (rootSizer_ !is null)
			rootSizer_.layout(getClientRect());
	}

	/**
	 * Add a right-aligned row of standard buttons at the bottom of the dialog,
	 * each wired to dismiss the dialog with the matching `DialogResult`. The
	 * OK/Yes button becomes the dialog's default push button (activated by Enter
	 * via the native dialog manager).
	 *
	 * Button captions are localized automatically: an app translation (looked up
	 * via `tr` under the keys `deft.button.ok` / `.cancel` / `.yes` / `.no`) wins;
	 * otherwise the operating system's own localized text is used, so OK/Cancel/
	 * Yes/No match the user's Windows language even with no catalog installed.
	 */
	void addStandardButtons(ButtonSet set)
	{
		auto row = new HBox();
		// A flexible empty cell pushes the buttons to the right edge.
		row.addSizer(new HBox()).proportion(1);

		final switch (set)
		{
		case ButtonSet.ok:
			addButton(row, okText(), DialogResult.ok, true);
			break;
		case ButtonSet.okCancel:
			addButton(row, okText(), DialogResult.ok, true);
			addButton(row, cancelText(), DialogResult.cancel, false);
			break;
		case ButtonSet.yesNo:
			addButton(row, yesText(), DialogResult.yes, true);
			addButton(row, noText(), DialogResult.no, false);
			break;
		}

		buttonSizer_ = row;
		rebuildRoot();
	}

	private Button addButton(HBox row, string text, DialogResult result, bool isDefault)
	{
		auto button = new Button(this, text);
		if (isDefault)
		{
			// Mark it the default push button so the dialog manager fires it on
			// Enter and a screen reader announces it as the default.
			SendMessageW(button.handle, BM_SETSTYLE, BS_DEFPUSHBUTTON, TRUE);
			SendMessageW(handle, DM_SETDEFID, cast(WPARAM) button.controlId, 0);
		}
		button.onClicked ~= { endModal(result); };
		row.add(button).pad(Padding.all(4));
		return button;
	}

	private void rebuildRoot()
	{
		auto root = new VBox();
		if (contentSizer_ !is null)
			root.addSizer(contentSizer_).proportion(1);
		if (buttonSizer_ !is null)
			root.addSizer(buttonSizer_).pad(Padding.all(8));
		rootSizer_ = root;
		relayout();
	}

	/**
	 * Show the dialog modally: disable the parent window, pump messages through
	 * the dialog manager until `endModal` is called (or the dialog is closed),
	 * then re-enable the parent and return the result.
	 */
	DialogResult showModal()
	{
		centerOnParent();

		if (parentHandle_ !is null)
			EnableWindow(parentHandle_, FALSE);

		ShowWindow(handle, SW_SHOW);
		SetForegroundWindow(handle);
		focusFirstControl();

		modalDone_ = false;
		MSG msg;
		while (!modalDone_)
		{
			int got = GetMessageW(&msg, null, 0, 0);
			if (got <= 0)
			{
				// WM_QUIT: re-post it so the outer loop also exits, then stop.
				if (got == 0)
					PostQuitMessage(cast(int) msg.wParam);
				break;
			}

			// IsDialogMessageW gives native dialog keyboard handling: Tab/arrow
			// groups, Escape -> Cancel, Enter -> default button.
			if (!IsDialogMessageW(handle, &msg))
			{
				TranslateMessage(&msg);
				DispatchMessageW(&msg);
			}
		}

		if (parentHandle_ !is null)
		{
			EnableWindow(parentHandle_, TRUE);
			SetForegroundWindow(parentHandle_);
		}
		ShowWindow(handle, SW_HIDE);
		return result_;
	}

	/// Dismiss the dialog with `result`, breaking out of the modal loop.
	void endModal(DialogResult result)
	{
		result_ = result;
		modalDone_ = true;
		// Wake the modal GetMessage loop so it re-checks `modalDone_`.
		if (handle)
			PostMessageW(handle, WM_NULL, 0, 0);
	}

	/// Dispatch a dialog-procedure message; returns TRUE when handled.
	private INT_PTR handleMessage(UINT msg, WPARAM wParam, LPARAM lParam)
	{
		switch (msg)
		{
		case WM_COMMAND:
			// Control notifications carry the control HWND; route them to the
			// originating control (this is how a default button's Enter press and
			// a Cancel button's click reach their handlers).
			if (cast(HWND) lParam !is null)
				return routeCommand(wParam, lParam) ? TRUE : FALSE;
			// The dialog manager posts IDCANCEL on Escape and IDOK on Enter when
			// no control consumes it.
			switch (LOWORD(cast(DWORD) wParam))
			{
			case IDOK:
				endModal(DialogResult.ok);
				return TRUE;
			case IDCANCEL:
				endModal(DialogResult.cancel);
				return TRUE;
			default:
				return FALSE;
			}

		case WM_NOTIFY:
			return routeNotify(lParam) ? TRUE : FALSE;

		case WM_SIZE:
			relayout();
			return FALSE;

		case WM_CLOSE:
			endModal(DialogResult.cancel);
			return TRUE;

		default:
			return FALSE;
		}
	}

	/// Move focus to the first focusable child control.
	private void focusFirstControl()
	{
		foreach (child; children)
		{
			if (child.handle is null)
				continue;
			auto style = GetWindowLongW(child.handle, GWL_STYLE);
			if ((style & WS_TABSTOP)
				&& IsWindowVisible(child.handle)
				&& IsWindowEnabled(child.handle))
			{
				SetFocus(child.handle);
				return;
			}
		}
	}

	private void centerOnParent()
	{
		RECT prc;
		bool haveParent = parentHandle_ !is null && GetWindowRect(parentHandle_, &prc) != 0;
		if (!haveParent)
			SystemParametersInfoW(SPI_GETWORKAREA, 0, &prc, 0);

		int x = prc.left + ((prc.right - prc.left) - width_) / 2;
		int y = prc.top + ((prc.bottom - prc.top) - height_) / 2;
		SetWindowPos(handle, null, x, y, width_, height_, SWP_NOZORDER);
	}
}

/**
 * The dialog procedure shared by all `Dialog`s. Stores the owning `Dialog` in
 * `GWLP_USERDATA` on `WM_INITDIALOG` and forwards every later message to it.
 * `extern(Windows)` and `nothrow`: a D throwable must never escape into the OS.
 */
private extern (Windows) INT_PTR dialogProc(HWND hwnd, UINT msg, WPARAM wParam,
	LPARAM lParam) nothrow
{
	try
	{
		if (msg == WM_INITDIALOG)
		{
			SetWindowLongPtrW(hwnd, GWLP_USERDATA, cast(LONG_PTR) lParam);
			return TRUE;
		}

		auto dialog = cast(Dialog) cast(void*) GetWindowLongPtrW(hwnd, GWLP_USERDATA);
		if (dialog !is null)
			return dialog.handleMessage(msg, wParam, lParam);
	}
	catch (Throwable)
	{
		// Never propagate a D throwable through the Win32 dialog dispatcher.
	}
	return FALSE;
}

/**
 * Build an in-memory dialog template (the runtime form of an `.rc` `DIALOGEX`)
 * for an empty, non-visible modal dialog with the given title and pixel size.
 *
 * The header layout is the documented `DLGTEMPLATE` byte layout (18 bytes),
 * written at explicit offsets to avoid struct padding, followed by the no-menu
 * marker, the default-class marker, and the null-terminated title. Sizes are
 * converted from pixels to dialog units via `GetDialogBaseUnits`.
 */
private ubyte[] buildDialogTemplate(string title, int widthPx, int heightPx)
{
	immutable int baseUnits = GetDialogBaseUnits();
	immutable int baseX = baseUnits & 0xFFFF;
	immutable int baseY = (baseUnits >> 16) & 0xFFFF;
	immutable short cx = cast(short)(baseX > 0 ? cast(long) widthPx * 4 / baseX : widthPx);
	immutable short cy = cast(short)(baseY > 0 ? cast(long) heightPx * 8 / baseY : heightPx);

	// Convert the title to a null-terminated wide string and measure it.
	auto titleW = title.toWStringz;
	size_t titleLen = 0;
	while (titleW[titleLen] != '\0')
		++titleLen;
	++titleLen; // include the terminating NUL

	enum size_t headerSize = 18; // packed DLGTEMPLATE
	enum size_t menuOffset = 18;
	enum size_t classOffset = 20;
	enum size_t titleOffset = 22;

	auto buf = new ubyte[titleOffset + titleLen * wchar.sizeof];

	void putU32(size_t off, uint v) { *(cast(uint*)(buf.ptr + off)) = v; }
	void putU16(size_t off, ushort v) { *(cast(ushort*)(buf.ptr + off)) = v; }

	immutable DWORD style = WS_POPUP | WS_CAPTION | WS_SYSMENU | DS_MODALFRAME;

	putU32(0, style);          // style
	putU32(4, 0);              // dwExtendedStyle
	putU16(8, 0);              // cdit: zero controls
	putU16(10, 0);             // x (dialog units)
	putU16(12, 0);             // y
	putU16(14, cast(ushort) cx); // cx
	putU16(16, cast(ushort) cy); // cy
	putU16(menuOffset, 0);     // no menu
	putU16(classOffset, 0);    // default dialog class (#32770)

	auto titleDst = cast(wchar*)(buf.ptr + titleOffset);
	foreach (i; 0 .. titleLen)
		titleDst[i] = titleW[i];

	return buf;
}

/**
 * Prompt for a single line of text.
 *
 * Shows a modal dialog with a prompt label, a text field and OK/Cancel buttons.
 * Returns the entered text, or `null` if the user dismisses it.
 */
string showInputDialog(Widget parent, string title, string prompt,
	string initialValue = "")
{
	auto dialog = new Dialog(parent, title, 420, 180);
	scope (exit)
		dialog.dispose();

	auto content = new VBox();
	auto label = new Label(dialog, prompt);
	auto input = new TextBox(dialog, initialValue, TextBoxStyle.singleLine);
	content.add(label).pad(Padding.all(8));
	content.add(input).pad(Padding.symmetric(8, 0));

	dialog.setSizer(content);
	dialog.addStandardButtons(ButtonSet.okCancel);

	input.selectAll();

	if (dialog.showModal() == DialogResult.ok)
		return input.getText();
	return null;
}

// Standard-button caption ids in user32.dll's localized string table
// (800 = OK, 801 = Cancel, 805 = &Yes, 806 = &No), the same strings the native
// message box uses — so Deft's custom dialog buttons match the OS language.
private enum uint sidOK = 800;
private enum uint sidCancel = 801;
private enum uint sidYes = 805;
private enum uint sidNo = 806;

private string okText() { return standardText("deft.button.ok", "OK", sidOK); }
private string cancelText() { return standardText("deft.button.cancel", "Cancel", sidCancel); }
private string yesText() { return standardText("deft.button.yes", "&Yes", sidYes); }
private string noText() { return standardText("deft.button.no", "&No", sidNo); }

/**
 * Resolve a standard button's caption. Precedence: an application translation
 * (via `tr` under `key`) wins; otherwise the operating system's own localized
 * string; otherwise the English default. So the buttons follow the user's
 * Windows language with no catalog, yet an app can still override them.
 */
private string standardText(string key, string english, uint sysId)
{
	auto translated = tr(key);
	if (translated != key)
		return translated;
	auto os = loadSystemString(sysId);
	return os.length != 0 ? os : english;
}

/// Load a localized string from user32.dll's resource table (empty on failure).
private string loadSystemString(uint id)
{
	HMODULE user32 = GetModuleHandleW("user32.dll"w.ptr);
	if (user32 is null)
		return "";
	wchar[256] buf;
	int n = LoadStringW(user32, id, buf.ptr, cast(int) buf.length);
	if (n <= 0)
		return "";
	return fromWString(buf[0 .. n]);
}
