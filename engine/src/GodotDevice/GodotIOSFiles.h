// OpenBFME. GPL-3.0.
//
// IOSFiles, the Godot view of IOSFilesBridge (the Files app's document picker, the picked item's security scope and
// bookmark, and leaving the game folders out of backups; after daisyhasacat/openbfme-godot's GodotIOSAssets.mm). Compiled and registered on iOS only (OPENBFME_IOS_FILES, engine/CMakeLists.txt): on every other platform the class does not
// exist, and scripts/release/first_run.gd, which asks ClassDB.class_exists("IOSFiles"), offers no "Choose game file…".
//
// A status Dictionary: { state (idle, waiting, opening, downloading, picked, cancelled, error), kind ("file" / "folder"), path, name, place (where it
// is, in Files' words), error, ubiquitous (in iCloud Drive), size (bytes, -1 not known), serial (counts the picks that ended) }.

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot
{

class IOSFiles : public RefCounted
{
	GDCLASS(IOSFiles, RefCounted)

public:
	// Opens Files' picker for one file whose extension is `extension` (kind "file") or one folder (kind "folder"), in place (no copy). The item's
	// bookmark is written to `bookmark_file` (an absolute path; "" keeps none). False when a picker is already open. The result arrives in status()
	static bool pick(const String &kind, const String &extension, const String &bookmark_file);
	static Dictionary status();
	// A later launch: the item whose bookmark is at `bookmark_file`, its access started again. The status keys plus ok (false: error says why)
	static Dictionary restore(const String &bookmark_file);
	// The item at `path` is no longer read: its access stops; `bookmark_file` (when not "") is deleted
	static void release(const String &path, const String &bookmark_file);
	// The folder at `path` (and what is in it) left out of iCloud / computer backups: { ok, error }
	static Dictionary exclude_from_backup(const String &path);

protected:
	static void _bind_methods();
};

} // namespace godot
