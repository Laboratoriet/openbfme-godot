## Lane IOS-28: the "Mods" tab of the OpenBFME options page: the mods in the Mods folder, each with an on / off box, the folder, OPEN (Files on
## iOS, the file manager on a desktop) and LOOK AGAIN. NOT RETAIL (RotWK has only its -mod switch); the rows are the page's own gadgets
## (openbfme_options_screen.gd draws them, this says what they are). scripts/release/mods.gd has the folder, the list and the mod.txt format.
##
## A box changes the list the page will write (Options.ini OpenBFMEMods, on ACCEPT; CANCEL forgets it, RESET TO DEFAULTS leaves mods alone).
## Turning a mod on puts it last (the highest priority: it wins a file over the ones turned on before it). The mods load when OpenBFME starts,
## so a list that differs from what this start mounted shows "Restart to apply". One column (a two-column row leaves a label about 20 characters):
## the mods (at most MAX_SHOWN boxes; the page holds ten rows), then the state, the folder, OPEN and LOOK AGAIN.
## Not possible (the boxes greyed, the reason in the note): BFME1 mode, a -mod on the command line (it wins over the list), no mount.
## Lane IOS-31: an install-folder mod (Edain) shows its title (openbfme-aio.json) and size; it loads first, under the other mods, wherever it is in
## the list; a second one is refused (its box stays off and the Status row says why).
## Lane IOS-39: small (-mod-style) mods turned on together with an install-folder mod are allowed (docs/MODS.md), but they replace whole game
## files that the install-folder mod usually changes too (the generated test mods replace retail INI files Edain rewrites): the Status row says
## "with a warning", the note, the Status row's help and each small mod's help say what that means. Nothing is refused.
extends RefCounted

const Mods := preload("res://scripts/release/mods.gd")

const TAB := "Mods"
const OPEN := "Mods.open"
const RESCAN := "Mods.rescan"
const PREFIX := "Mod:"          # a mod's box: "Mod:<name>"
const MAX_SHOWN := 6            # mod boxes on the page (with the four fixed rows: the page's ten)
const IOS_FILES_URL := "shareddocuments://" # lane IOS-12's Open in Files (scripts/release/first_run.gd): the app's folder in the Files app

var mount_getter: Callable      # () -> the mount report of this start (Release.last_mount)
var bfme1_getter: Callable      # () -> true in BFME1 mode (no mods there)
var saved := PackedStringArray()   # Options.ini's list when the page opened
var pending := PackedStringArray() # what the boxes show (written on ACCEPT)
var _found := []                # Mods.scan of the folder (LOOK AGAIN reads it again)
var _scanned := false
var _refused := ""              # lane IOS-31: why the last box was not taken (the Status row shows it until the next change)


## The page opened: the list Options.ini holds now (`value`: its OpenBFMEMods text) and a fresh look at the folder.
func begin(value: String) -> void:
	saved = Mods.parse_list(value)
	pending = saved.duplicate()
	rescan()


func rescan() -> void:
	_found = Mods.scan(folder())
	_scanned = true
	print("GAME MODS folder %s: %d mod(s)%s" % [folder(), _found.size(), (": " + ", ".join(_found.map(func(m): return m.name))) if not _found.is_empty() else ""])


## The Mods folder of this start ("" before a RotWK mount).
func folder() -> String:
	return str(_mount().get("mod", {}).get("mods_folder", ""))


## true when the list in the boxes is not what Options.ini holds (ACCEPT writes it)
func changed() -> bool:
	return pending != saved


## The OpenBFMEMods text to write on ACCEPT.
func value() -> String:
	return Mods.list_text(pending)


func rows() -> Array:
	if not _scanned:
		rescan()
	var off := _unavailable()
	var rows := []
	var shown := {}
	var hidden := 0
	for m in _found:
		if rows.size() >= MAX_SHOWN and _index(pending, m.name) < 0:
			hidden += 1
			continue
		var on := _index(pending, m.name) >= 0
		shown[m.name.to_lower()] = true
		var help: String = m.description if not m.description.is_empty() else ("A mod that installs into the game folder: OpenBFME lays it over the game " +
			"files and keeps your game folder as it is." if m.kind == "install" else "No description (add a mod.txt with Title = and Description = lines).")
		help += " · " + {"folder": "folder ", "archive": "file ", "install": "install-folder mod ", "part": "folder "}.get(m.kind, "") + m.name
		help += " · " + Mods.size_text(m.bytes)
		var order := _load_order(pending)
		if on and order.size() > 1:
			help += " · loads %s of %d" % [_ordinal(_index(order, m.name) + 1), order.size()]
		var over := _install_under(m.name)
		if on and not over.is_empty():
			help += " · over %s: where both have a file, this mod's wins and %s's change to it is lost" % [over, over]
		if not m.problem.is_empty():
			help = m.problem
		var r := {"kind": "check", "key": PREFIX + m.name, "label": m.title, "value": 1 if on else 0, "help": help,
			"enabled": off.is_empty() and (m.problem.is_empty() or on)} # a mod with a problem can still be turned off
		rows.append(r)
	# an enabled mod that is not in the folder any more: its box, on, to turn it off
	for n in pending:
		if not shown.has(n.to_lower()):
			rows.append({"kind": "check", "key": PREFIX + n, "label": "%s (not found)" % n, "value": 1,
				"help": "Turned on, but not in the Mods folder any more: it is not loaded. Clear the box to forget it.", "enabled": off.is_empty()})
	if rows.is_empty():
		rows.append(_text("Mods.none", "No mods yet", "", "Put a mod's folder or .big file into the Mods folder, then LOOK AGAIN."))
	if hidden > 0:
		rows.append(_text("Mods.more", "More mods", "%d not shown" % hidden, "The page shows %d mods that are off; turn one off to see others." % MAX_SHOWN))
	rows.append_array([
		_text("Mods.state", "Status", _state_line(), mixed_warning() if not mixed_warning().is_empty() else "Mods are loaded when OpenBFME starts."),
		_text("Mods.folder", "Mods folder", _folder_line(), "Where OpenBFME looks for mods: %s" % (folder() if not folder().is_empty() else "not known yet")),
		{"kind": "button", "key": OPEN, "label": "Open the folder", "value_text": "OPEN",
			"help": "Shows the Mods folder in %s." % ("the Files app" if OS.has_feature("ios") else ("Finder" if OS.get_name() == "macOS" else "the file manager")),
			"enabled": not folder().is_empty()},
		{"kind": "button", "key": RESCAN, "label": "Added or removed a mod?", "value_text": "LOOK AGAIN",
			"help": "Reads the Mods folder again.", "enabled": not folder().is_empty()},
	])
	return rows


## The help line while no row is pointed at: what to do now.
func note() -> String:
	var off := _unavailable()
	if not off.is_empty():
		return off
	if _found.is_empty() and pending.is_empty():
		return "No mods in the Mods folder. Copy a mod (its folder, or one .big file) into it with %s, then LOOK AGAIN." % \
			("the Files app (On My iPhone › OpenBFME › Mods)" if OS.has_feature("ios") else "Finder or your file manager")
	if not _refused.is_empty():
		return _refused + ": each one replaces the game folder's files, so two cannot load together."
	if not mixed_warning().is_empty():
		return mixed_warning() + (" Restart to apply after ACCEPT." if restart_needed() else "")
	if restart_needed():
		return "Restart to apply: close OpenBFME and open it again after ACCEPT. Online and LAN games are off while mods are on."
	if _found.any(func(m): return m.kind == "install"):
		return "An install-folder mod (one at a time) loads first; the other mods go over it, a mod turned on later winning. Online and LAN games are off while mods are on."
	return "A mod turned on later wins over one turned on before it. Online and LAN games are off while mods are on."


## Lane IOS-39: "" or the warning for small mods turned on together with an install-folder mod (allowed, not refused): they load over it, and
## each replaces whole game files that the install-folder mod has usually changed as well, so that mod's version of those files is lost.
func mixed_warning() -> String:
	var install := ""
	var small := PackedStringArray()
	for n in _effective(pending):
		if _is_install(n):
			install = _title_of(n)
		else:
			small.append(_title_of(n))
	if install.is_empty() or small.is_empty():
		return ""
	return "Careful: %s load%s over %s and replace%s whole game files. %s changes many of the same files, so where both have one %s's change is lost and it may not work as it should. Turn %s off if it does not." % [
		", ".join(small), "s" if small.size() == 1 else "", install, "s" if small.size() == 1 else "", install, install, "it" if small.size() == 1 else "them"]


## true when the list in the boxes is not what this start mounted
func restart_needed() -> bool:
	return Mods.list_text(_effective(pending)) != Mods.list_text(Mods.mounted_names(_mount()))


## A box was clicked: `on` turns the mod on (last: highest priority) or off. False when the tab does not take it now.
func set_mod(key: String, on: bool) -> bool:
	if not key.begins_with(PREFIX) or not _unavailable().is_empty():
		return false
	var name := key.trim_prefix(PREFIX)
	var i := _index(pending, name)
	_refused = ""
	if on and i < 0 and _is_install(name):
		# lane IOS-31: one install-folder mod at a time (Common/ModMount.h PlanModsFolder refuses two at the start too)
		for n in pending:
			if _is_install(n):
				_refused = "Only one install-folder mod at a time: turn %s off first" % _title_of(n)
				print("GAME MODS %s not turned on: %s" % [name, _refused])
				return true
	if on and i < 0:
		pending.append(name)
	elif not on and i >= 0:
		pending.remove_at(i)
	print("GAME MODS %s %s: the list is now [%s]%s" % [name, "on" if on else "off", ", ".join(pending), " (restart to apply)" if restart_needed() else ""])
	return true


## A Button row was clicked.
func press(key: String) -> void:
	match key:
		RESCAN:
			rescan()
		OPEN:
			if folder().is_empty():
				return
			DirAccess.make_dir_recursive_absolute(folder())
			# lane IOS-12's way into the Files app (first_run.gd _open_files: shareddocuments:// and the folder's path, each part percent-encoded);
			# a desktop opens the folder itself
			var err := OS.shell_open(files_url(folder())) if OS.has_feature("ios") else OS.shell_open(folder())
			print("GAME MODS open the folder %s: %s" % [folder(), error_string(err)])


## The Files app's URL of a folder of the app (lane IOS-12)
static func files_url(path: String) -> String:
	var parts := path.split("/")
	for i in parts.size():
		parts[i] = parts[i].uri_encode()
	return IOS_FILES_URL + "/".join(parts)


# "" or why the boxes are greyed
func _unavailable() -> String:
	if bfme1_getter.is_valid() and bool(bfme1_getter.call()):
		return "Mods are for The Rise of the Witch-king: OpenBFME runs in Battle for Middle-earth mode now, which loads none."
	var m := _mount()
	if not m.get("ok", false):
		return "OpenBFME has not opened the game folders in this session, so it cannot load mods. Start OpenBFME normally, then come back here."
	if str(m.get("mod", {}).get("source", "")) == "command line":
		return "A mod was given on the command line (-mod), and it wins over this list. Start OpenBFME without -mod to use the Mods folder."
	return ""


func _folder_line() -> String:
	if folder().is_empty():
		return "not known yet"
	if OS.has_feature("ios"):
		return "Files › OpenBFME › Mods"
	var data := folder().get_base_dir().get_file()
	return "…/" + (data if data.length() <= 24 else data.left(23) + "…") + "/Mods" # the help line has the whole path


func _state_line() -> String:
	if not _refused.is_empty():
		return "One install mod at a time" # note() has the whole reason
	var on := _effective(pending).size()
	if restart_needed():
		return "Restart to apply"
	if on == 0:
		return "No mods in use"
	if not mixed_warning().is_empty():
		return "%d mods, with a warning" % on # lane IOS-39: note() and the row's help have it
	return "%d mod%s in use" % [on, "" if on == 1 else "s"]


# the names of `list` that the folder has (what a start would mount)
func _effective(list: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for n in list:
		for m in _found:
			if m.name.to_lower() == n.to_lower():
				out.append(m.name)
	return out


# lane IOS-31: the order a start mounts `list` in: the install-folder mod first (under the others), then the rest as listed
func _load_order(list: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for n in list:
		if _is_install(n):
			out.append(n)
	for n in list:
		if not _is_install(n):
			out.append(n)
	return out


func _is_install(name: String) -> bool:
	for m in _found:
		if m.name.to_lower() == name.to_lower():
			return m.kind == "install"
	return false


# lane IOS-39: the title of the install-folder mod `name` (a small mod, turned on) loads over, "" when none is on or `name` is that mod itself
func _install_under(name: String) -> String:
	if _is_install(name):
		return ""
	for n in _effective(pending):
		if _is_install(n):
			return _title_of(n)
	return ""


func _title_of(name: String) -> String:
	for m in _found:
		if m.name.to_lower() == name.to_lower():
			return m.title
	return name


func _mount() -> Dictionary:
	return mount_getter.call() if mount_getter.is_valid() else {}


static func _index(list: PackedStringArray, name: String) -> int:
	for i in list.size():
		if list[i].to_lower() == name.to_lower():
			return i
	return -1


static func _ordinal(n: int) -> String:
	return str(n) + ({1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th") if not (n % 100 in [11, 12, 13]) else "th")


static func _text(key: String, label: String, value: String, help: String) -> Dictionary:
	return {"kind": "text", "key": key, "label": label, "value_text": value, "help": help}
