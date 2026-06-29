/**
 * UTF-8 ↔ UTF-16 conversion helpers for the Win32 backend.
 *
 * D strings are UTF-8; the wide Win32 API (`...W`) speaks UTF-16. These helpers
 * bridge the two using the platform's own `MultiByteToWideChar` /
 * `WideCharToMultiByte`, which keeps the library free of any Phobos dependency
 * (smaller binaries) and matches the OS exactly. Conversions are lenient:
 * malformed input (for example a lone surrogate) is replaced with U+FFFD rather
 * than throwing, so a stray value from the OS can never crash the UI.
 */
module deft.util.strings;

import core.sys.windows.winnls : CP_UTF8, MultiByteToWideChar, WideCharToMultiByte;

/**
 * Convert a D UTF-8 string into a null-terminated UTF-16 buffer suitable for
 * passing to wide Win32 APIs.
 *
 * The returned pointer refers to GC-managed memory; it stays valid as long as
 * the caller keeps a reference reachable (in practice, for the duration of the
 * Win32 call it is handed to).
 */
const(wchar)* toWStringz(string s) @trusted
{
	// Shared, immutable terminator for the common empty-string case — every empty
	// control caption, tooltip, etc. would otherwise allocate a fresh wchar[1].
	static immutable wchar[1] emptyWz = ['\0'];
	if (s.length == 0)
		return emptyWz.ptr;

	int needed = MultiByteToWideChar(CP_UTF8, 0, s.ptr, cast(int) s.length, null, 0);
	auto buf = new wchar[needed + 1];
	if (needed > 0)
		MultiByteToWideChar(CP_UTF8, 0, s.ptr, cast(int) s.length, buf.ptr, needed);
	buf[needed] = '\0';
	return buf.ptr;
}

/**
 * Convert a null-terminated UTF-16 buffer (as returned by Win32) into a D
 * UTF-8 string. Stops at the first NUL. A null pointer yields an empty string.
 */
string fromWStringz(const(wchar)* ws) @system
{
	if (ws is null)
		return "";

	size_t len = 0;
	while (ws[len] != '\0')
		++len;

	return fromWString(ws[0 .. len]);
}

/**
 * Convert a known-length UTF-16 slice into a D UTF-8 string. Embedded NUL
 * characters are preserved; malformed code units are replaced with U+FFFD.
 */
string fromWString(const(wchar)[] ws) @trusted
{
	if (ws.length == 0)
		return "";

	int needed = WideCharToMultiByte(
		CP_UTF8, 0, ws.ptr, cast(int) ws.length, null, 0, null, null);
	if (needed <= 0)
		return "";

	auto buf = new char[needed];
	WideCharToMultiByte(
		CP_UTF8, 0, ws.ptr, cast(int) ws.length, buf.ptr, needed, null, null);
	return cast(string) buf;
}

// These roundtrip tests exercise fromWStringz, which is @system (it walks a
// raw pointer), so the blocks themselves cannot be @safe.
@system unittest
{
	// ASCII roundtrip.
	enum ascii = "Hello, world!";
	assert(ascii.toWStringz.fromWStringz == ascii);
}

@system unittest
{
	// Cyrillic roundtrip.
	enum cyrillic = "Привет, мир!";
	assert(cyrillic.toWStringz.fromWStringz == cyrillic);
}

@system unittest
{
	// Hebrew roundtrip (right-to-left script).
	enum hebrew = "שלום עולם";
	assert(hebrew.toWStringz.fromWStringz == hebrew);
}

@system unittest
{
	// CJK roundtrip (BMP) plus an astral-plane code point exercising surrogate
	// pairs (emoji).
	enum cjk = "日本語テスト 🎉";
	assert(cjk.toWStringz.fromWStringz == cjk);
}

@system unittest
{
	// Empty string roundtrips through both directions.
	assert("".toWStringz.fromWStringz == "");
	assert(fromWString([]) == "");
}

@system unittest
{
	// fromWStringz stops at the first embedded NUL.
	const(wchar)[] withNul = ['a', 'b', '\0', 'c', 'd'];
	assert(fromWStringz(withNul.ptr) == "ab");
}

@safe unittest
{
	import std.algorithm.searching : canFind;
	import std.utf : validate;

	// A lone high surrogate is malformed UTF-16. Conversion must not throw, must
	// yield valid UTF-8, and must surface the replacement character (U+FFFD).
	const(wchar)[] lone = ['a', 0xD800, 'b'];
	string decoded = fromWString(lone);
	validate(decoded); // throws if not well-formed UTF-8
	assert(decoded.length >= 1);
	assert(decoded[0] == 'a');
	assert(decoded.canFind('�'));
}
