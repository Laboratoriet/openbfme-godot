// OpenBFME. GPL-3.0.
//
// Lane IOS-36: IOSFiles (GodotIOSFiles.h), over IOSFilesBridge.mm.

#include "GodotDevice/GodotIOSFiles.h"

#include "GodotDevice/IOSFilesBridge.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot
{

namespace
{

std::string Utf8(const String &s)
{
	return std::string(s.utf8().get_data());
}

Dictionary ToDictionary(const IOSFilesBridge::Status &s)
{
	Dictionary d;
	d["state"] = String::utf8(s.state.c_str());
	d["kind"] = String::utf8(s.kind.c_str());
	d["path"] = String::utf8(s.path.c_str());
	d["name"] = String::utf8(s.name.c_str());
	d["place"] = String::utf8(s.place.c_str());
	d["error"] = String::utf8(s.error.c_str());
	d["ubiquitous"] = s.ubiquitous;
	d["size"] = s.size;
	d["serial"] = s.serial;
	return d;
}

} // namespace

bool IOSFiles::pick(const String &kind, const String &extension, const String &bookmark_file)
{
	return IOSFilesBridge::pick(Utf8(kind), Utf8(extension), Utf8(bookmark_file));
}

Dictionary IOSFiles::status()
{
	return ToDictionary(IOSFilesBridge::status());
}

Dictionary IOSFiles::restore(const String &bookmark_file)
{
	IOSFilesBridge::Status s;
	const bool ok = IOSFilesBridge::restore(Utf8(bookmark_file), s);
	Dictionary d = ToDictionary(s);
	d["ok"] = ok;
	return d;
}

void IOSFiles::release(const String &path, const String &bookmark_file)
{
	IOSFilesBridge::release(Utf8(path), Utf8(bookmark_file));
}

Dictionary IOSFiles::exclude_from_backup(const String &path)
{
	std::string error;
	Dictionary d;
	d["ok"] = IOSFilesBridge::excludeFromBackup(Utf8(path), error);
	d["error"] = String::utf8(error.c_str());
	return d;
}

void IOSFiles::_bind_methods()
{
	ClassDB::bind_static_method("IOSFiles", D_METHOD("pick", "kind", "extension", "bookmark_file"), &IOSFiles::pick);
	ClassDB::bind_static_method("IOSFiles", D_METHOD("status"), &IOSFiles::status);
	ClassDB::bind_static_method("IOSFiles", D_METHOD("restore", "bookmark_file"), &IOSFiles::restore);
	ClassDB::bind_static_method("IOSFiles", D_METHOD("release", "path", "bookmark_file"), &IOSFiles::release);
	ClassDB::bind_static_method("IOSFiles", D_METHOD("exclude_from_backup", "path"), &IOSFiles::exclude_from_backup);
}

} // namespace godot
