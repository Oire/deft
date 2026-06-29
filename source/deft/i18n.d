/**
 * Localization seam.
 *
 * Deft does not bundle a message-catalog parser — that would drag a dependency
 * (and likely Phobos) into the library and force one catalog format on everyone.
 * Instead it exposes a single pluggable hook: the application installs a
 * `Translator` delegate with `setTranslator`, and every translatable string the
 * framework emits is looked up through `tr`. The delegate is free to be backed by
 * gettext, XLIFF, a plain associative array, or anything else — that choice (and
 * any Phobos it needs) lives in the application, not here.
 *
 * Without a translator installed, `tr` returns its argument unchanged, so an
 * un-localized app behaves exactly as before. The framework's own handful of
 * strings (the standard dialog buttons) additionally fall back to the operating
 * system's localized text, so they are translated even with no catalog at all.
 *
 * Install the translator once, before creating UI; reads are not synchronized.
 */
module deft.i18n;

/**
 * Looks up a translation for `key`, returning the translated string. A delegate
 * may throw to signal "no translation"; callers fall back to `key`.
 */
alias Translator = string delegate(string key);

private __gshared Translator g_translator;

/// Install (or clear, with `null`) the application's translation delegate.
void setTranslator(Translator translator)
{
	g_translator = translator;
}

/// The currently installed translation delegate, or `null`.
Translator translator()
{
	return g_translator;
}

/**
 * Translate `key` through the installed `Translator`.
 *
 * Returns the translated string, or `key` itself when no translator is installed
 * or the translator returns null/empty or throws. `nothrow`: safe to call from
 * anywhere in the UI, including while building controls.
 */
string tr(string key) nothrow
{
	auto t = g_translator;
	if (t !is null)
	{
		try
		{
			auto translated = t(key);
			if (translated.length != 0)
				return translated;
		}
		catch (Exception)
		{
			// Fall through to returning the key unchanged.
		}
	}
	return key;
}

unittest
{
	// Default: no translator installed, tr is the identity.
	setTranslator(null);
	assert(tr("Hello") == "Hello");

	// An installed translator is consulted.
	setTranslator((string k) => k == "Hello" ? "Bonjour" : k);
	assert(tr("Hello") == "Bonjour");
	assert(tr("Unmapped") == "Unmapped"); // unknown key falls back to itself

	// A translator that returns empty falls back to the key.
	setTranslator((string k) => "");
	assert(tr("Keep") == "Keep");

	// A throwing translator must not propagate; it falls back to the key.
	setTranslator(delegate string(string k) { throw new Exception("boom"); });
	assert(tr("Safe") == "Safe");

	setTranslator(null); // don't leak state into other tests
}
