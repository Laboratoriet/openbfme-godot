// OpenBFME. GPL-3.0.
//
// Lane IOS-36: IOSDocumentPicker (GodotIOSDocumentPicker.h), over IOSDocumentPickerBridge.mm.

#include "GodotDevice/GodotIOSDocumentPicker.h"

#include "GodotDevice/IOSDocumentPickerBridge.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot
{

namespace
{

std::string Utf8(const String &s)
{
	return std::string(s.utf8().get_data());
}

Dictionary ToDictionary(const IOSDocumentPickerBridge::Status &s)
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

bool IOSDocumentPicker::pick(const String &kind, const String &extension, const String &bookmark_file)
{
	return IOSDocumentPickerBridge::pick(Utf8(kind), Utf8(extension), Utf8(bookmark_file));
}

Dictionary IOSDocumentPicker::status()
{
	return ToDictionary(IOSDocumentPickerBridge::status());
}

Dictionary IOSDocumentPicker::restore(const String &bookmark_file)
{
	IOSDocumentPickerBridge::Status s;
	const bool ok = IOSDocumentPickerBridge::restore(Utf8(bookmark_file), s);
	Dictionary d = ToDictionary(s);
	d["ok"] = ok;
	return d;
}

void IOSDocumentPicker::release(const String &path, const String &bookmark_file)
{
	IOSDocumentPickerBridge::release(Utf8(path), Utf8(bookmark_file));
}

void IOSDocumentPicker::_bind_methods()
{
	ClassDB::bind_static_method("IOSDocumentPicker", D_METHOD("pick", "kind", "extension", "bookmark_file"), &IOSDocumentPicker::pick);
	ClassDB::bind_static_method("IOSDocumentPicker", D_METHOD("status"), &IOSDocumentPicker::status);
	ClassDB::bind_static_method("IOSDocumentPicker", D_METHOD("restore", "bookmark_file"), &IOSDocumentPicker::restore);
	ClassDB::bind_static_method("IOSDocumentPicker", D_METHOD("release", "path", "bookmark_file"), &IOSDocumentPicker::release);
}

} // namespace godot
