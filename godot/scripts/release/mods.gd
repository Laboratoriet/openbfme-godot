## Lane IOS-28: the Mods folder and the mods enabled in it (NOT RETAIL: RotWK has one -mod on its command line; this is OpenBFME's list of them).
##
## The folder: on iOS Documents/Mods (the Files app shows it under On My iPhone › OpenBFME › Mods); on a desktop "Mods" in the user data folder
## (where a relative "-mod Mods/<name>" resolves too). The engine makes it at every mount and says where (RetailFileSystem.get_mods_folder,
## the mount report's mod.mods_folder).
## A mod is a folder in it (retail's folder mod: its *.big files directly inside, and its other files as loose game files) or a .big file in it.
## Its optional description (the Mods tab shows it): a "mod.txt" in the folder, or "<name>.txt" beside a .big, with "Title = ..." and
## "Description = ..." lines ("Title: ..." works too; other lines are ignored).
## Options.ini keeps the enabled ones as OpenBFMEMods = <name>;<name>... in mount order: the first is mounted first, so a later one wins a file
## both have. The engine mounts them over the verified game files when no -mod is given (Common/ModMount.h MountRetailMods).
extends RefCounted

const KEY := "OpenBFMEMods"
const INFO_FILE := "mod.txt"
const SEPARATOR := ";"
const TITLE_MAX := 40        # the Mods tab's row label stays on one line
const DESCRIPTION_MAX := 200


## The enabled names of an OpenBFMEMods value, in order: empty parts and a second spelling of a name (without case) are left out.
static func parse_list(value: String) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for part in value.split(SEPARATOR, false):
		var name := part.strip_edges()
		if name.is_empty() or seen.has(name.to_lower()):
			continue
		seen[name.to_lower()] = true
		out.append(name)
	return out


## The OpenBFMEMods value of `names` ("" = no mod: the entry is removed from Options.ini).
static func list_text(names: PackedStringArray) -> String:
	return SEPARATOR.join(names)


## The enabled mods of the Options.ini at `path` (the shell's own reader, before the shell boots): {ok, names, error}.
static func enabled_in_options(path: String) -> Dictionary:
	var read: Dictionary = ClassDB.class_call_static("AptMenuPlayer", "read_options_file", path)
	if not read.get("ok", false):
		return {"ok": false, "names": PackedStringArray(), "error": "Options.ini: " + str(read.get("error", "unreadable"))}
	return {"ok": true, "names": parse_list(str(read.get("values", {}).get(KEY, ""))), "error": ""}


## The mods in `folder`, by name without case: [{name, kind ("folder" / "archive"), title, description, problem}]. A name with the list's
## separator in it cannot be enabled (problem). Hidden entries (".DS_Store", ".Trash") and other files are not mods.
static func scan(folder: String) -> Array:
	var out := []
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return out
	var names := []
	for d in DirAccess.get_directories_at(folder):
		if not d.begins_with("."):
			names.append([d, "folder"])
	for f in DirAccess.get_files_at(folder):
		if not f.begins_with(".") and f.get_extension().to_lower() == "big":
			names.append([f, "archive"])
	names.sort_custom(func(a, b): return a[0].naturalnocasecmp_to(b[0]) < 0)
	for n in names:
		var name: String = n[0]
		var info_path := folder.path_join(name).path_join(INFO_FILE) if n[1] == "folder" else folder.path_join(name.get_basename() + ".txt")
		var info := read_info(info_path)
		out.append({
			"name": name,
			"kind": n[1],
			"title": info.title if not info.title.is_empty() else (name if n[1] == "folder" else name.get_basename()),
			"description": info.description,
			"problem": "Its name has a \"%s\" in it, which the list of enabled mods cannot hold: rename it." % SEPARATOR if name.contains(SEPARATOR) else "",
		})
	return out


## The title and description of a mod.txt (absent file: both ""). Values are cut at TITLE_MAX / DESCRIPTION_MAX characters.
static func read_info(path: String) -> Dictionary:
	var info := {"title": "", "description": ""}
	if not FileAccess.file_exists(path):
		return info
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		var cut := -1
		for sep in ["=", ":"]:
			var i := line.find(sep)
			if i > 0 and (cut < 0 or i < cut):
				cut = i
		if cut < 0:
			continue
		var key := line.substr(0, cut).strip_edges().to_lower()
		var value := line.substr(cut + 1).strip_edges()
		if key == "title" and info.title.is_empty():
			info.title = _cut(value, TITLE_MAX)
		elif key == "description" and info.description.is_empty():
			info.description = _cut(value, DESCRIPTION_MAX)
	return info


static func _cut(text: String, most: int) -> String:
	return text if text.length() <= most else text.substr(0, most - 1).strip_edges() + "…"


## The mods a mount report mounted from the Mods folder (its mod.list when the source is the folder), else none.
static func mounted_names(mount: Dictionary) -> PackedStringArray:
	var mod: Dictionary = mount.get("mod", {})
	if not mod.get("mounted", false) or str(mod.get("source", "")) != "mods folder":
		return PackedStringArray()
	var out := PackedStringArray()
	var missing: PackedStringArray = mod.get("missing", PackedStringArray())
	for n in mod.get("list", PackedStringArray()):
		if not missing.has(n):
			out.append(n)
	return out


## "" or why online and LAN play are refused with the mounted mods (lane IOS-28: mods change the simulation, and a lockstep game whose players
## run other data desyncs). Only the Mods folder's mods: a -mod on the command line keeps lane MODS-1's behaviour (the profile identity carries
## the mod, so only players with the same mod meet).
static func multiplayer_refusal(mount: Dictionary) -> String:
	var names := mounted_names(mount)
	if names.is_empty():
		return ""
	return "Online and LAN games are off while mods are on (%s): mods change the game, and players with different game data fall out of step. " \
		% ", ".join(names) + "Turn them off in Options › Mods and restart OpenBFME to play with others. Skirmish and the campaigns work with mods."
