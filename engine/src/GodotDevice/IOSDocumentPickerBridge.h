// OpenBFME. GPL-3.0.
//
// Lane IOS-36: the Files app's document picker (UIDocumentPickerViewController) for the welcome screen (scripts/release/first_run.gd): the
// player picks OpenBFME-GameData.obfme wherever it is (iCloud Drive, Downloads, another app's folder, a drive) and the streaming importer
// (scripts/release/game_file_import.gd) reads it IN PLACE, through the picked URL's security scope, instead of a 6.5 GB copy into the app.
//
// After daisyhasacat/openbfme-godot (GPL-3.0), engine/src/GodotDevice/GodotIOSAssets.mm ("iOS external-drive folder selection and
// security-scoped bookmarks", Hailey Tribble): the picker presented over the key window's top view controller on the main queue, opened in place
// (asCopy NO), the URL's startAccessingSecurityScopedResource kept while it is used, and a minimal bookmark written to a file so a later launch
// gets the same access back. Generalised here: a file of one extension as well as a folder; several picked items at once (one bookmark file
// each); and a coordinated read after the pick, which makes a file provider (iCloud Drive, a cloud app) bring a file that is not on the device
// yet down before it is opened (the state says "downloading" meanwhile).
//
// Plain C++ on purpose, as IOSPointerBridge.h: IOSDocumentPickerBridge.mm includes no godot-cpp header. The pick and its delegate run on the
// main thread (Godot's iOS main loop runs there; a call from another thread is sent to the main queue); the coordinated read runs on a background
// queue and only changes the state under a lock.

#pragma once

#include <cstdint>
#include <string>

namespace IOSDocumentPickerBridge
{

struct Status
{
	// idle (nothing asked yet), waiting (the picker is open), downloading (picked; the provider is bringing the file down), picked (ready to read
	// at `path`), cancelled (the player closed the picker), error (`error` says why)
	std::string state = "idle";
	std::string kind;          // "file" or "folder": what the last pick asked for
	std::string path;          // the picked item's absolute path (the security scope is held while it is in use)
	std::string name;          // its file or folder name
	std::string place;         // where it is, for the screen: "iCloud Drive", "On My iPhone", "a drive", "OpenBFME's folder", "Files"
	std::string error;         // the reason, for state error (NSError's localizedDescription, or what OpenBFME could not do)
	bool ubiquitous = false;   // in iCloud Drive (NSURLIsUbiquitousItemKey)
	int64_t size = -1;         // a file's size in bytes once it is there (-1: not known yet, or a folder)
	int serial = 0;            // counts the picks that ended (picked, cancelled or error): a poller sees a new result
};

// Opens the picker for `kind` ("file": one file whose extension is `extension`; "folder": one folder). `bookmarkFile`: where to keep the pick's
// bookmark ("" keeps none). False (state error) when there is no window to present it on or a pick is already open.
bool pick(const std::string &kind, const std::string &extension, const std::string &bookmarkFile);
Status status();
// The bookmark at `bookmarkFile` resolved and its scope started again (a later launch). A stale bookmark is written again. True: `out` is
// state picked (or downloading, with the coordinated read under way); false: `out.error` says why (the file gone, the drive not connected).
bool restore(const std::string &bookmarkFile, Status &out);
// Stops the scope of the item at `path` (the import finished, or another item was picked) and deletes `bookmarkFile` when given.
void release(const std::string &path, const std::string &bookmarkFile);

} // namespace IOSDocumentPickerBridge
