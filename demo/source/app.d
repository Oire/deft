/**
 * Deft framework demo.
 *
 * Creates a window with a label, two proportional panels (2:1) and a Close
 * button, all arranged with sizers. Demonstrates the event system (the button
 * quits the app) and a custom accessible name on the left panel.
 *
 * The concrete controls (Button, Label, Panel) used here are thin local
 * subclasses of the framework's `Control` base — the framework's own control
 * library arrives in a later plan. They show how to build a control over a
 * native window class and wire up its notifications.
 */
module app;

import core.sys.windows.windows;

import deft;

/// A push button that fires `onClicked` on `BN_CLICKED`.
final class Button : Control
{
	Event!() onClicked;

	this(Widget parent, string text)
	{
		super(parent, "BUTTON", BS_PUSHBUTTON | WS_TABSTOP);
		setText(text);
	}

	override bool processCommand(ushort notificationCode)
	{
		if (notificationCode == BN_CLICKED)
		{
			onClicked.fire();
			return true;
		}
		return false;
	}

	override Size getPreferredSize()
	{
		return Size(100, 30);
	}
}

/// A left-aligned static text label.
final class Label : Control
{
	this(Widget parent, string text)
	{
		super(parent, "STATIC", SS_LEFT);
		setText(text);
	}

	override Size getPreferredSize()
	{
		return Size(0, 24);
	}
}

/// A placeholder panel rendered as a sunken, centered static control.
final class Panel : Control
{
	this(Widget parent, string caption)
	{
		super(parent, "STATIC", SS_SUNKEN | SS_CENTER);
		setText(caption);
	}
}

int main()
{
	auto app = Application.instance;
	app.initialize();

	auto window = new Window("Framework Demo", 800, 600);

	// Top-level vertical stack: label, panels (stretch), button.
	auto root = new VBox();

	auto label = new Label(window, "Hello from Deft");
	root.add(label, 0, Padding.all(8));

	// Two panels side by side at 2:1.
	auto panels = new HBox();
	auto leftPanel = new Panel(window, "Left");
	auto rightPanel = new Panel(window, "Right");
	panels.add(leftPanel, 2, Padding.all(4));
	panels.add(rightPanel, 1, Padding.all(4));
	root.addSizer(panels, 1, Padding.symmetric(8, 0));

	auto closeButton = new Button(window, "Close");
	closeButton.onClicked ~= { app.quit(); };
	root.add(closeButton, 0, Padding.all(8));

	window.setSizer(root);

	// Give the unlabeled left panel an accessible name for screen readers.
	setAccessibleName(leftPanel, "Left panel");

	window.show();
	return app.run();
}
