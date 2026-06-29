# Demo localization

The demo is localized with GNU gettext catalogs (`.po` → `.mo`) loaded at runtime
through the [`mofile`](https://code.dlang.org/packages/mofile) package and fed to
Deft's `setTranslator` hook. Every user-facing string in `source/app.d` is marked
with Deft's `tr("...")` seam; the standard dialog buttons (OK/Cancel/Yes/No)
localize themselves from the operating system and need no catalog entry.

Languages shipped: **fr**, **de**, **ru**, **uk** (plus the source language,
English, which needs no catalog). The `Language` menu switches the UI live.

## Layout

```
locale/
  messages.pot            extraction template (generated)
  <lang>/deft-demo.mo     compiled catalog the demo loads at runtime
  <lang>/deft-demo.po     editable translation source
  scripts/                the localization workflow (PowerShell)
```

The catalog file name (`deft-demo`) is the dub package name, read from `dub.json`.
At runtime the demo loads `locale/<lang>/deft-demo.mo` from beside the executable.

## Workflow (scripts/)

Adapted from the Sic project's localization scripts for D/dub. They locate the
GNU gettext tools (`xgettext`/`msgmerge`/`msgfmt`/`msginit`) on `PATH` or under a
GnuWin32 install.

```powershell
# 1. Extract tr("...") calls from the D sources into messages.pot
scripts/Extract-Strings.ps1

# 2. Start a new language (creates locale/<lang>/deft-demo.po)
scripts/New-Language.ps1 -Language es

# 3. After editing the source, merge new/changed strings into every .po
scripts/Update-Translations.ps1

# 4. Compile every .po to .mo (run this before launching the demo)
scripts/Compile-Translations.ps1            # or -Language es for one
```

Then build and run the demo (`dub run` from `demo/`) and use the **Language** menu.

## Notes

- `.po` files are UTF-8; keep the `Content-Type: ... charset=UTF-8` header.
- Translators set their own keyboard mnemonics with `&` in each `msgstr`.
- Autonyms in the `Language` menu (English, Français, Deutsch, Русский,
  Українська) are intentionally **not** translated — each shows in its own
  language.
- xgettext has no native D mode; the scripts use `--language=C++`, which parses
  D's C-like string and call syntax well enough for `tr("...")` extraction.
