/**
 * Deft framework demo — a localized widget gallery.
 *
 * Exercises every control type the framework provides: menus and accelerators,
 * a status bar, a tab control whose pages hold labels, buttons, check boxes, a
 * radio group, single- and multi-line text boxes, a list view, a tree view, a
 * list box and a combo box, plus a one-second timer, a tray icon, a modal
 * dialog and a message box.
 *
 * It also demonstrates **localization**: every user-facing string is marked with
 * Deft's `tr()` seam, the `Language` menu switches the UI language at runtime,
 * and translations are loaded from gettext `.mo` catalogs (compiled from the
 * `.po` files under `locale/`) via the `mofile` package, installed through
 * `setTranslator`. The standard dialog buttons localize themselves from the OS.
 *
 * Each tab page is a framework `Panel` — a container that lays its children out
 * with a sizer and forwards their notifications.
 */
module app;

import std.conv : to;
import std.file : thisExePath, exists;
import std.format : format;
import std.path : buildPath, dirName;

import core.sys.windows.windows;

import mofile;

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
	idLangEn = 40_040,
	idLangFr = 40_041,
	idLangDe = 40_042,
	idLangRu = 40_043,
	idLangUk = 40_044,
}

int main()
{
	auto app = Application.instance;
	app.initialize();

	auto window = new Window("Deft Widget Gallery", 900, 640);
	window.setIcon(loadIcon(1));
	window.setMinimumSize(640, 480);

	auto status = new StatusBar(window);
	window.setStatusBar(status);

	// --- Tab control with two pages, each a Panel laid out with a VBox. ---
	auto tabs = new TabControl(window);

	auto root = new VBox();
	root.add(tabs).proportion(1).pad(Padding.all(8));
	window.setSizer(root);

	// Page 1: basic controls.
	auto basics = new Panel(window);
	auto basicsBox = new VBox();

	auto hello = new Label(basics, tr("Hello from Deft"));
	basicsBox.add(hello).pad(Padding.all(6));

	auto clock = new Label(basics, "");
	basicsBox.add(clock).pad(Padding.all(6));

	auto dialogButton = new Button(basics, tr("&Open Dialog..."));
	basicsBox.add(dialogButton).pad(Padding.all(6)).alignH(HAlign.center);

	auto feature = new CheckBox(basics, tr("Enable &feature"));
	basicsBox.add(feature).pad(Padding.all(6));

	auto optionA = new RadioButton(basics, tr("Option &A"), true);
	auto optionB = new RadioButton(basics, tr("Option &B"));
	optionA.setChecked(true);
	basicsBox.add(optionA).pad(Padding.all(6));
	basicsBox.add(optionB).pad(Padding.all(6));

	auto search = new TextBox(basics, "", TextBoxStyle.singleLine);
	basicsBox.add(search).pad(Padding.all(6));

	auto notes = new TextBox(basics, tr("Multi-line text..."), TextBoxStyle.multiLine);
	basicsBox.add(notes).proportion(1).pad(Padding.all(6));

	basics.setSizer(basicsBox);
	tabs.addPage(tr("Basics"), basics);

	// Page 2: list-style controls.
	auto lists = new Panel(window);
	auto listsBox = new VBox();

	auto listView = new ListView(lists);
	listView.addColumn(tr("Title"), 260);
	listView.addColumn(tr("Updated"), 140);
	listView.addColumn(tr("Created"), 140);
	listView.addItem(["My first note", "2026-05-01", "2026-04-15"]);
	listView.addItem(["Shopping list", "2026-04-30", "2026-04-20"]);
	listView.addItem(["Meeting agenda", "2026-04-28", "2026-04-10"]);
	listView.autoSizeColumn(0, ColumnAutoSize.content);
	listView.autoSizeColumn(1, ColumnAutoSize.content);
	listView.autoSizeColumn(2, ColumnAutoSize.header);
	setAccessibleName(listView, tr("Notes list"));
	listsBox.add(listView).proportion(2).pad(Padding.all(6));

	auto tree = new TreeView(lists);
	auto work = tree.addRoot("Work");
	tree.addChild(work, "Project Alpha");
	tree.addChild(work, "Project Beta");
	auto personal = tree.addRoot("Personal");
	tree.addChild(personal, "Shopping");
	tree.addChild(personal, "Travel");
	tree.expandItem(work);
	setAccessibleName(tree, tr("Categories"));
	listsBox.add(tree).proportion(2).pad(Padding.all(6));

	auto listBox = new ListBox(lists);
	listBox.addItem("Apples");
	listBox.addItem("Oranges");
	listBox.addItem("Pears");
	setAccessibleName(listBox, tr("Fruit list"));
	listsBox.add(listBox).proportion(1).pad(Padding.all(6));

	auto checks = new CheckListBox(lists);
	checks.addItem("Bold");
	checks.addItem("Italic");
	checks.addItem("Underline");
	checks.setChecked(0, true);
	setAccessibleName(checks, tr("Text style"));
	checks.onItemChecked ~= (int index) {
		status.setText(format(checks.isChecked(index) ? tr("Checked: %s") : tr("Unchecked: %s"),
			checks.getItemText(index)));
	};
	listsBox.add(checks).proportion(1).pad(Padding.all(6));

	auto combo = new ComboBox(lists);
	combo.addItem("Small");
	combo.addItem("Medium");
	combo.addItem("Large");
	combo.setSelectedIndex(1);
	setAccessibleName(combo, tr("Size"));
	listsBox.add(combo).pad(Padding.all(6));

	lists.setSizer(listsBox);
	tabs.addPage(tr("Lists"), lists);

	// --- Localization state and machinery. ---
	int elapsed = 0;
	MoFile catalog;
	bool haveCatalog = false;
	MenuBar menuBar; // assigned once the menu is built; used by retranslate()

	/// Refresh the clock label in the current language.
	void updateClock()
	{
		clock.setText(format(tr("Elapsed: %d s"), elapsed));
	}

	/// Re-apply every translatable caption in the active language. Controls
	/// created on demand (dialogs, message boxes) read `tr()` when shown, so they
	/// need no retranslation here.
	void retranslate()
	{
		window.setTitle(tr("Deft Widget Gallery"));
		status.setText(tr("Ready"));

		tabs.setTabTitle(0, tr("Basics"));
		tabs.setTabTitle(1, tr("Lists"));

		hello.setText(tr("Hello from Deft"));
		updateClock();
		dialogButton.setText(tr("&Open Dialog..."));
		feature.setText(tr("Enable &feature"));
		optionA.setText(tr("Option &A"));
		optionB.setText(tr("Option &B"));

		listView.setColumnTitle(0, tr("Title"));
		listView.setColumnTitle(1, tr("Updated"));
		listView.setColumnTitle(2, tr("Created"));

		if (menuBar !is null)
		{
			menuBar.setMenuTitle(0, tr("&File"));
			menuBar.setMenuTitle(1, tr("&Edit"));
			menuBar.setMenuTitle(2, tr("&Language"));
			menuBar.setMenuTitle(3, tr("&Help"));
			menuBar.setItemText(idNew, tr("&New Note..."));
			menuBar.setItemText(idInput, tr("&Input..."));
			menuBar.setItemText(idExit, tr("E&xit"));
			menuBar.setItemText(idPreview, tr("Show &Preview"));
			menuBar.setItemText(idAbout, tr("&About"));
			if (window.handle)
				DrawMenuBar(window.handle);
		}
	}

	/// Load `code` ("en" for the untranslated source language, otherwise a locale
	/// directory under `locale/`) and re-translate the whole UI.
	void loadLanguage(string code)
	{
		if (code == "en")
		{
			haveCatalog = false;
			setTranslator(null);
		}
		else
		{
			auto path = buildPath(dirName(thisExePath()), "locale", code, "deft-demo.mo");
			if (exists(path))
			{
				try
				{
					catalog = MoFile(path);
					haveCatalog = true;
					setTranslator((string key) => catalog.gettext(key));
				}
				catch (Exception)
				{
					haveCatalog = false;
					setTranslator(null);
				}
			}
			else
			{
				haveCatalog = false;
				setTranslator(null);
			}
		}

		if (menuBar !is null)
		{
			menuBar.setChecked(idLangEn, code == "en");
			menuBar.setChecked(idLangFr, code == "fr");
			menuBar.setChecked(idLangDe, code == "de");
			menuBar.setChecked(idLangRu, code == "ru");
			menuBar.setChecked(idLangUk, code == "uk");
		}

		retranslate();
	}

	// --- Cross-control wiring. ---
	search.onTextChanged ~= (string text) {
		status.setText(format(tr("Search: %s"), text));
	};

	listView.onSelectionChanged ~= (int index) {
		status.setText(format(tr("Selected: %s"), listView.getItemText(index, 0)));
	};
	listView.onItemActivated ~= (int index) {
		showMessageBox(window,
			format(tr("You activated: %s"), listView.getItemText(index, 0)),
			tr("Note"), MessageBoxStyle.info);
	};

	// Right-click context menu on the list (coordinates are screen-relative).
	auto listMenu = new Menu();
	auto ctxView = MenuItem(0, tr("&View"));
	ctxView.onClicked ~= {
		int sel = listView.getSelectedIndex();
		if (sel >= 0)
			status.setText(format(tr("View: %s"), listView.getItemText(sel, 0)));
	};
	listMenu.append(ctxView);
	listView.onContextMenu ~= (int index, MouseEventArgs m) {
		if (index >= 0)
			listView.setSelectedIndex(index);
		showPopupMenu(listMenu, window, m.x, m.y);
	};

	tree.onSelectionChanged ~= (TreeItem item) {
		status.setText(format(tr("Category: %s"), tree.getItemText(item)));
	};

	// Context menu on the tree — works from right-click and the Apps key / Shift+F10.
	auto treeMenu = new Menu();
	auto ctxExpand = MenuItem(0, tr("&Expand"));
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
		status.setText(format(tr("Fruit: %s"), listBox.getItemText(index)));
	};

	feature.onToggled ~= {
		status.setText(feature.isChecked() ? tr("Feature on") : tr("Feature off"));
	};

	dialogButton.onClicked ~= { openEditDialog(window, status); };

	// --- Menu bar with accelerators. ---
	auto fileMenu = new Menu();
	auto newItem = MenuItem(idNew, tr("&New Note..."), "Ctrl+N");
	newItem.onClicked ~= { status.setText(tr("New note")); };
	fileMenu.append(newItem);

	auto inputItem = MenuItem(idInput, tr("&Input..."), "Ctrl+I");
	inputItem.onClicked ~= {
		auto answer = showInputDialog(window, tr("Your name"), tr("Enter your &name:"));
		if (answer !is null)
			status.setText(format(tr("Hello, %s"), answer));
	};
	fileMenu.append(inputItem);

	fileMenu.appendSeparator();

	auto exitItem = MenuItem(idExit, tr("E&xit"), "Ctrl+Q");
	exitItem.onClicked ~= { window.close(); };
	fileMenu.append(exitItem);

	auto editMenu = new Menu();
	auto previewItem = MenuItem(idPreview, tr("Show &Preview"), "", MenuItemKind.checkable);
	previewItem.onClicked ~= {
		bool now = !editMenu.findItem(idPreview).checked;
		editMenu.setChecked(idPreview, now);
		status.setText(now ? tr("Preview on") : tr("Preview off"));
	};
	editMenu.append(previewItem);

	// Language menu: item labels are autonyms, shown in their own language, so
	// they are intentionally NOT passed through tr().
	auto langMenu = new Menu();
	auto langEn = MenuItem(idLangEn, "English", "", MenuItemKind.checkable);
	langEn.onClicked ~= { loadLanguage("en"); };
	langMenu.append(langEn);
	auto langFr = MenuItem(idLangFr, "Français", "", MenuItemKind.checkable);
	langFr.onClicked ~= { loadLanguage("fr"); };
	langMenu.append(langFr);
	auto langDe = MenuItem(idLangDe, "Deutsch", "", MenuItemKind.checkable);
	langDe.onClicked ~= { loadLanguage("de"); };
	langMenu.append(langDe);
	auto langRu = MenuItem(idLangRu, "Русский", "", MenuItemKind.checkable);
	langRu.onClicked ~= { loadLanguage("ru"); };
	langMenu.append(langRu);
	auto langUk = MenuItem(idLangUk, "Українська", "", MenuItemKind.checkable);
	langUk.onClicked ~= { loadLanguage("uk"); };
	langMenu.append(langUk);

	auto helpMenu = new Menu();
	auto aboutItem = MenuItem(idAbout, tr("&About"), "F1");
	aboutItem.onClicked ~= {
		showMessageBox(window,
			tr("Deft Widget Gallery\nA native UI framework for D."),
			tr("About"), MessageBoxStyle.info);
	};
	helpMenu.append(aboutItem);

	menuBar = new MenuBar();
	menuBar.append(fileMenu, tr("&File"));
	menuBar.append(editMenu, tr("&Edit"));
	menuBar.append(langMenu, tr("&Language"));
	menuBar.append(helpMenu, tr("&Help"));
	window.setMenuBar(menuBar);

	// --- One-second timer updating the clock label. ---
	auto timer = new Timer(window);
	timer.onTick ~= {
		++elapsed;
		updateClock();
	};
	timer.start(1000);

	// --- Tray icon with a context menu. ---
	auto trayMenu = new Menu();
	auto trayShow = MenuItem(idTrayShow, tr("&Show"));
	trayShow.onClicked ~= {
		window.show();
		SetForegroundWindow(window.handle);
	};
	trayMenu.append(trayShow);
	trayMenu.appendSeparator();
	auto trayExit = MenuItem(idTrayExit, tr("E&xit"));
	auto tray = new TrayIcon(window, tr("Deft Widget Gallery"));
	trayExit.onClicked ~= {
		tray.remove();
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
	window.onClose ~= (CloseEventArgs* args) { tray.remove(); };

	// Start in the source language (English); checks the English menu item and
	// fills in the dynamic clock/status captions.
	loadLanguage("en");

	window.show();
	return app.run();
}

/// Open a modal note editor and report the result to the status bar.
void openEditDialog(Window parent, StatusBar status)
{
	auto dialog = new Dialog(parent, tr("Edit Note"), 480, 360);
	scope (exit)
		dialog.dispose();

	// A table layout: a fixed label column with right-aligned labels, and a
	// stretching field column; the title row sizes to the field, the content row
	// fills the rest.
	auto grid = new Grid(2, 2);
	grid.setColumn(0, GridTrack.pixels(90));
	grid.setColumn(1, GridTrack.percent(100));
	grid.setRow(0, GridTrack.autoSize);
	grid.setRow(1, GridTrack.percent(100));
	grid.setSpacing(8, 8);

	auto titleLabel = new Label(dialog, tr("&Title:"));
	auto titleInput = new TextBox(dialog, tr("Untitled"));
	auto bodyLabel = new Label(dialog, tr("&Content:"));
	auto bodyInput = new TextBox(dialog, "", TextBoxStyle.multiLine);

	grid.add(titleLabel, 0, 0).aligned(HAlign.right, VAlign.middle).pad(Padding.all(4));
	grid.add(titleInput, 1, 0).pad(Padding.all(4));
	grid.add(bodyLabel, 0, 1).aligned(HAlign.right, VAlign.top).pad(Padding.all(4));
	grid.add(bodyInput, 1, 1).pad(Padding.all(4));

	dialog.setSizer(grid);
	dialog.addStandardButtons(ButtonSet.okCancel);

	if (dialog.showModal() == DialogResult.ok)
		status.setText(format(tr("Saved: %s"), titleInput.getText()));
	else
		status.setText(tr("Edit canceled"));
}
