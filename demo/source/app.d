/**
 * Deft framework demo — a widget gallery.
 *
 * Exercises every control type the framework provides: menus and accelerators,
 * a status bar, a tab control whose pages hold labels, buttons, check boxes, a
 * radio group, single- and multi-line text boxes, a list view, a tree view, a
 * list box and a combo box, plus a one-second timer, a tray icon, a modal
 * dialog and a message box. Cross-control wiring updates the status bar from
 * list/tree selections and opens a dialog from a button.
 *
 * Each tab page is a framework `Panel` — a container that lays its children out
 * with a sizer and forwards their notifications.
 */
module app;

import std.conv : to;

import core.sys.windows.windows;

import deft;

/// Command ids for the menu bar.
enum : int
{
	idNew = 40_001,
	idInput = 40_002,
	idExit = 40_003,
	idPreview = 40_010,
	idAbout = 40_020,
	idTrayShow = 40_030,
	idTrayExit = 40_031,
}

int main()
{
	auto app = Application.instance;
	app.initialize();

	auto window = new Window("Deft Widget Gallery", 900, 640);

	auto status = new StatusBar(window);
	status.setText("Ready");
	window.setStatusBar(status);

	// --- Tab control with two pages, each a Panel laid out with a VBox. ---
	auto tabs = new TabControl(window);

	auto root = new VBox();
	root.add(tabs).proportion(1).pad(Padding.all(8));
	window.setSizer(root);

	// Page 1: basic controls.
	auto basics = new Panel(window);
	auto basicsBox = new VBox();

	auto hello = new Label(basics, "Hello from Deft");
	basicsBox.add(hello).pad(Padding.all(6));

	auto clock = new Label(basics, "Elapsed: 0s");
	basicsBox.add(clock).pad(Padding.all(6));

	auto dialogButton = new Button(basics, "Open Dialog...");
	// Fluent box placement + cross-axis alignment: keep the button's own width
	// and center it horizontally instead of stretching it across the column.
	basicsBox.add(dialogButton).pad(Padding.all(6)).alignH(HAlign.center);

	auto feature = new CheckBox(basics, "Enable feature");
	basicsBox.add(feature).pad(Padding.all(6));

	auto optionA = new RadioButton(basics, "Option A", true);
	auto optionB = new RadioButton(basics, "Option B");
	optionA.setChecked(true);
	basicsBox.add(optionA).pad(Padding.all(6));
	basicsBox.add(optionB).pad(Padding.all(6));

	auto search = new TextBox(basics, "", TextBoxStyle.singleLine);
	basicsBox.add(search).pad(Padding.all(6));

	auto notes = new TextBox(basics, "Multi-line text...", TextBoxStyle.multiLine);
	basicsBox.add(notes).proportion(1).pad(Padding.all(6));

	basics.setSizer(basicsBox);
	tabs.addPage("Basics", basics);

	// Page 2: list-style controls.
	auto lists = new Panel(window);
	auto listsBox = new VBox();

	auto listView = new ListView(lists);
	listView.addColumn("Title", 260);
	listView.addColumn("Updated", 140);
	listView.addColumn("Created", 140);
	listView.addItem(["My first note", "2026-05-01", "2026-04-15"]);
	listView.addItem(["Shopping list", "2026-04-30", "2026-04-20"]);
	listView.addItem(["Meeting agenda", "2026-04-28", "2026-04-10"]);
	// Autosize the data columns to their content, then let the last one fill the
	// remaining width — done after the rows are added (autosize measures content).
	listView.autoSizeColumn(0, ColumnAutoSize.content);
	listView.autoSizeColumn(1, ColumnAutoSize.content);
	listView.autoSizeColumn(2, ColumnAutoSize.header);
	setAccessibleName(listView, "Notes list");
	listsBox.add(listView).proportion(2).pad(Padding.all(6));

	auto tree = new TreeView(lists);
	auto work = tree.addRoot("Work");
	tree.addChild(work, "Project Alpha");
	tree.addChild(work, "Project Beta");
	auto personal = tree.addRoot("Personal");
	tree.addChild(personal, "Shopping");
	tree.addChild(personal, "Travel");
	tree.expandItem(work);
	setAccessibleName(tree, "Categories");
	listsBox.add(tree).proportion(2).pad(Padding.all(6));

	auto listBox = new ListBox(lists);
	listBox.addItem("Apples");
	listBox.addItem("Oranges");
	listBox.addItem("Pears");
	setAccessibleName(listBox, "Fruit list");
	listsBox.add(listBox).proportion(1).pad(Padding.all(6));

	auto checks = new CheckListBox(lists);
	checks.addItem("Bold");
	checks.addItem("Italic");
	checks.addItem("Underline");
	checks.setChecked(0, true);
	setAccessibleName(checks, "Text style");
	checks.onItemChecked ~= (int index) {
		status.setText((checks.isChecked(index) ? "Checked: " : "Unchecked: ")
			~ checks.getItemText(index));
	};
	listsBox.add(checks).proportion(1).pad(Padding.all(6));

	auto combo = new ComboBox(lists);
	combo.addItem("Small");
	combo.addItem("Medium");
	combo.addItem("Large");
	combo.setSelectedIndex(1);
	setAccessibleName(combo, "Size");
	listsBox.add(combo).pad(Padding.all(6));

	lists.setSizer(listsBox);
	tabs.addPage("Lists", lists);

	// --- Cross-control wiring. ---
	search.onTextChanged ~= (string text) {
		status.setText("Search: " ~ text);
	};

	listView.onSelectionChanged ~= (int index) {
		status.setText("Selected: " ~ listView.getItemText(index, 0));
	};
	listView.onItemActivated ~= (int index) {
		showMessageBox(window,
			"You activated: " ~ listView.getItemText(index, 0),
			"Note", MessageBoxStyle.info);
	};

	// Right-click context menu on the list (coordinates are screen-relative).
	auto listMenu = new Menu();
	auto ctxView = MenuItem(0, "&View");
	ctxView.onClicked ~= {
		int sel = listView.getSelectedIndex();
		if (sel >= 0)
			status.setText("View: " ~ listView.getItemText(sel, 0));
	};
	listMenu.append(ctxView);
	listView.onContextMenu ~= (int index, MouseEventArgs m) {
		if (index >= 0)
			listView.setSelectedIndex(index);
		showPopupMenu(listMenu, window, m.x, m.y);
	};

	tree.onSelectionChanged ~= (TreeItem item) {
		status.setText("Category: " ~ tree.getItemText(item));
	};

	// Context menu on the tree — works from right-click and the Apps key / Shift+F10.
	auto treeMenu = new Menu();
	auto ctxExpand = MenuItem(0, "&Expand");
	ctxExpand.onClicked ~= {
		auto sel = tree.getSelectedItem();
		if (!sel.isNull)
			tree.expandItem(sel);
	};
	treeMenu.append(ctxExpand);
	tree.onContextMenu ~= (TreeItem item, MouseEventArgs m) {
		if (!item.isNull)
			tree.setSelectedItem(item);
		showPopupMenu(treeMenu, window, m.x, m.y);
	};

	listBox.onSelectionChanged ~= (int index) {
		status.setText("Fruit: " ~ listBox.getItemText(index));
	};

	feature.onToggled ~= {
		status.setText(feature.isChecked() ? "Feature on" : "Feature off");
	};

	dialogButton.onClicked ~= { openEditDialog(window, status); };

	// --- Menu bar with accelerators. ---
	auto fileMenu = new Menu();
	auto newItem = MenuItem(idNew, "&New Note...", "Ctrl+N");
	newItem.onClicked ~= { status.setText("New note"); };
	fileMenu.append(newItem);

	auto inputItem = MenuItem(idInput, "&Input...", "Ctrl+I");
	inputItem.onClicked ~= {
		auto answer = showInputDialog(window, "Your name", "Enter your name:");
		if (answer !is null)
			status.setText("Hello, " ~ answer);
	};
	fileMenu.append(inputItem);

	fileMenu.appendSeparator();

	auto exitItem = MenuItem(idExit, "E&xit", "Ctrl+Q");
	exitItem.onClicked ~= { window.close(); };
	fileMenu.append(exitItem);

	auto editMenu = new Menu();
	auto previewItem = MenuItem(idPreview, "Show &Preview", "", MenuItemKind.checkable);
	previewItem.onClicked ~= {
		bool now = !editMenu.findItem(idPreview).checked;
		editMenu.setChecked(idPreview, now);
		status.setText(now ? "Preview on" : "Preview off");
	};
	editMenu.append(previewItem);

	auto helpMenu = new Menu();
	auto aboutItem = MenuItem(idAbout, "&About", "F1");
	aboutItem.onClicked ~= {
		showMessageBox(window,
			"Deft Widget Gallery\nA native UI framework for D.",
			"About", MessageBoxStyle.info);
	};
	helpMenu.append(aboutItem);

	auto menuBar = new MenuBar();
	menuBar.append(fileMenu, "&File");
	menuBar.append(editMenu, "&Edit");
	menuBar.append(helpMenu, "&Help");
	window.setMenuBar(menuBar);

	// --- One-second timer updating the clock label. ---
	int elapsed = 0;
	auto timer = new Timer(window);
	timer.onTick ~= {
		++elapsed;
		clock.setText("Elapsed: " ~ elapsed.to!string ~ "s");
	};
	timer.start(1000);

	// --- Tray icon with a context menu. ---
	auto trayMenu = new Menu();
	auto trayShow = MenuItem(idTrayShow, "&Show");
	trayShow.onClicked ~= {
		window.show();
		SetForegroundWindow(window.handle);
	};
	trayMenu.append(trayShow);
	trayMenu.appendSeparator();
	auto trayExit = MenuItem(idTrayExit, "E&xit");
	auto tray = new TrayIcon(window, "Deft Widget Gallery");
	trayExit.onClicked ~= {
		tray.destroy();
		app.quit();
	};
	trayMenu.append(trayExit);

	tray.setIcon(LoadIconW(null, IDI_APPLICATION));
	tray.setContextMenu(trayMenu);
	tray.onDoubleClicked ~= {
		window.show();
		SetForegroundWindow(window.handle);
	};

	// Remove the tray icon before the window is destroyed.
	window.onClose ~= (CloseEventArgs* args) { tray.destroy(); };

	window.show();
	return app.run();
}

/// Open a modal note editor and report the result to the status bar.
void openEditDialog(Window parent, StatusBar status)
{
	auto dialog = new Dialog(parent, "Edit Note", 480, 360);
	scope (exit)
		dialog.dispose();

	// A table layout: a fixed label column with right-aligned labels, and a
	// stretching field column; the title row sizes to the field, the content row
	// fills the rest. Note the fluent placement — span/aligned/pad read clearly.
	auto grid = new Grid(2, 2);
	grid.setColumn(0, GridTrack.pixels(90));
	grid.setColumn(1, GridTrack.percent(100));
	grid.setRow(0, GridTrack.autoSize);
	grid.setRow(1, GridTrack.percent(100));
	grid.setSpacing(8, 8);

	auto titleLabel = new Label(dialog, "Title:");
	auto titleInput = new TextBox(dialog, "Untitled");
	auto bodyLabel = new Label(dialog, "Content:");
	auto bodyInput = new TextBox(dialog, "", TextBoxStyle.multiLine);

	grid.add(titleLabel, 0, 0).aligned(HAlign.right, VAlign.middle).pad(Padding.all(4));
	grid.add(titleInput, 1, 0).pad(Padding.all(4));
	grid.add(bodyLabel, 0, 1).aligned(HAlign.right, VAlign.top).pad(Padding.all(4));
	grid.add(bodyInput, 1, 1).pad(Padding.all(4));

	dialog.setSizer(grid);
	dialog.addStandardButtons(ButtonSet.okCancel);

	if (dialog.showModal() == DialogResult.ok)
		status.setText("Saved: " ~ titleInput.getText());
	else
		status.setText("Edit canceled");
}
