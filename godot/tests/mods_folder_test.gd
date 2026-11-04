## Lane IOS-28: the Mods folder's list and the Mods tab (scripts/release/mods.gd, scripts/release/mods_tab.gd) on a generated folder: the
## OpenBFMEMods value both ways, mod.txt, what the folder scan counts as a mod, the online / LAN refusal, and the tab's rows and states (empty,
## a mod off, on with "Restart to apply", a mod no longer in the folder, the reasons it is greyed). Headless, no game data, no shell.
extends SceneTree

const Mods := preload("res://scripts/release/mods.gd")
const Tab := preload("res://scripts/release/mods_tab.gd")

var checks := 0
var failed := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("MODS FAIL ", label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_list()
	_info_and_scan()
	_refusal()
	_tab()
	print("MODS %d checks, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)


func _list() -> void:
	check(Mods.parse_list("") == PackedStringArray(), "an empty value is no mod")
	check(Mods.parse_list("A;B") == PackedStringArray(["A", "B"]), "two names in order")
	check(Mods.parse_list(" A ; ;B;a;My Mod.big;") == PackedStringArray(["A", "B", "My Mod.big"]),
		"spaces trimmed, empty parts and a second spelling of a name left out")
	check(Mods.list_text(PackedStringArray(["B", "A"])) == "B;A", "written in order with ';'")
	check(Mods.list_text(PackedStringArray()) == "", "no mod is an empty value (the entry is removed)")


func _info_and_scan() -> void:
	var dir := ProjectSettings.globalize_path("user://mods-test")
	_remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("Beta Mod"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("alpha"))
	DirAccess.make_dir_recursive_absolute(dir.path_join(".hidden"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("Semi;colon"))
	_write(dir.path_join("Beta Mod/mod.txt"), "; a comment\nTitle = Beta, the mod\nDescription: Makes things.\nTitle = ignored\n")
	_write(dir.path_join("Gamma.BIG"), "BIGF")
	_write(dir.path_join("Gamma.txt"), "title: Gamma archive\n")
	_write(dir.path_join("notes.txt"), "not a mod")
	_write(dir.path_join(".DS_Store"), "x")
	var long := "x".repeat(60)
	_write(dir.path_join("alpha/mod.txt"), "Title=" + long + "\n")
	var found := Mods.scan(dir)
	check(found.map(func(m): return m.name) == ["alpha", "Beta Mod", "Gamma.BIG", "Semi;colon"],
		"the folder's mods without case: folders and .big files, nothing hidden, no other file: %s" % str(found.map(func(m): return m.name)))
	if found.size() == 4:
		check(found[1].title == "Beta, the mod" and found[1].description == "Makes things." and found[1].kind == "folder",
			"mod.txt's Title = and Description: (the first of each)")
		check(found[2].title == "Gamma archive" and found[2].kind == "archive", "a .big's <name>.txt beside it")
		check(found[0].title.length() == Mods.TITLE_MAX and found[0].title.ends_with("…"), "a long title is cut")
		check(not found[3].problem.is_empty() and found[1].problem.is_empty(), "a name with ';' cannot be enabled")
	check(Mods.scan(dir.path_join("nowhere")).is_empty(), "a folder that does not exist has no mods")
	check(Mods.read_info(dir.path_join("nothing.txt")) == {"title": "", "description": ""}, "no mod.txt: no title or description")
	_remove_tree(dir)


func _refusal() -> void:
	var none := {"ok": true, "mod": {"mounted": false, "source": ""}}
	check(Mods.multiplayer_refusal(none).is_empty(), "no mod: online and LAN are open")
	var cli := {"ok": true, "mod": {"mounted": true, "source": "command line", "list": PackedStringArray()}}
	check(Mods.multiplayer_refusal(cli).is_empty(), "a -mod keeps lane MODS-1's behaviour (the identity carries it)")
	var folder := {"ok": true, "mod": {"mounted": true, "source": "mods folder", "list": PackedStringArray(["Sauron", "Gone"]),
		"missing": PackedStringArray(["Gone"])}}
	check(Mods.mounted_names(folder) == PackedStringArray(["Sauron"]), "the mounted names leave the missing out")
	check(Mods.multiplayer_refusal(folder).begins_with("Online and LAN games are off while mods are on (Sauron)"), Mods.multiplayer_refusal(folder))


func _tab() -> void:
	var dir := ProjectSettings.globalize_path("user://mods-tab-test")
	_remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("Sauron"))
	_write(dir.path_join("Sauron/mod.txt"), "Title = Sauron at the fortress\n")
	var mount := {"ok": true, "rotwk_install": "/games/RotWK", "mod": {"mounted": false, "source": "", "mods_folder": dir}}
	var tab := Tab.new()
	tab.mount_getter = func(): return mount
	tab.begin("")
	var rows := _keyed(tab.rows())
	check(rows.has("Mod:Sauron") and rows["Mod:Sauron"].value == 0 and rows["Mod:Sauron"].label == "Sauron at the fortress", "a box per mod, off")
	check(rows.has("Mods.state") and rows["Mods.state"].value_text == "No mods in use", "the state: no mods in use")
	check(not tab.restart_needed() and not tab.changed(), "nothing to apply")
	check(tab.set_mod("Mod:Sauron", true) and tab.changed() and tab.restart_needed(), "on: changed, restart needed")
	rows = _keyed(tab.rows())
	check(rows["Mods.state"].value_text == "Restart to apply" and tab.note().begins_with("Restart to apply"), "the state and note ask for a restart")
	check(tab.value() == "Sauron", "ACCEPT would write OpenBFMEMods = Sauron")
	# the next start mounted it: on and in use
	mount.mod = {"mounted": true, "source": "mods folder", "list": PackedStringArray(["Sauron"]), "missing": PackedStringArray(), "mods_folder": dir}
	tab.begin("Sauron")
	rows = _keyed(tab.rows())
	check(rows["Mod:Sauron"].value == 1 and rows["Mods.state"].value_text == "1 mod in use" and not tab.restart_needed(), "mounted: on, 1 mod in use")
	# removed from the folder while enabled: its row says so and a click forgets it
	_remove_tree(dir.path_join("Sauron"))
	tab.rescan()
	rows = _keyed(tab.rows())
	check(rows.has("Mod:Sauron") and rows["Mod:Sauron"].label == "Sauron (not found)" and tab.restart_needed(), "not found: its own row, restart needed")
	check(tab.set_mod("Mod:Sauron", false) and tab.value() == "", "cleared: forgotten")
	rows = _keyed(tab.rows())
	check(rows.has("Mods.none") and tab.note().begins_with("No mods in the Mods folder"), "the empty folder: the row and the note say how to add one")
	# greyed: a -mod on the command line, BFME1 mode, no mount
	DirAccess.make_dir_recursive_absolute(dir.path_join("Other"))
	tab.rescan()
	mount.mod = {"mounted": true, "source": "command line", "mods_folder": dir}
	check(not tab.set_mod("Mod:Other", true) and tab.note().begins_with("A mod was given on the command line"), "-mod: the boxes do nothing, the note says why")
	check(not _keyed(tab.rows())["Mod:Other"].enabled, "-mod: the box is greyed")
	mount.mod = {"mounted": false, "source": "", "mods_folder": dir}
	tab.bfme1_getter = func(): return true
	check(tab.note().begins_with("Mods are for The Rise of the Witch-king"), "BFME1 mode: greyed with the reason")
	tab.bfme1_getter = Callable()
	mount.ok = false
	check(tab.note().begins_with("OpenBFME has not opened the game folders"), "no mount: greyed with the reason")
	check(Tab.files_url("/var/mobile/Data/Documents/My Mods") == "shareddocuments:///var/mobile/Data/Documents/My%20Mods", "the Files app's URL (IOS-12's encoding)")
	_remove_tree(dir)


static func _keyed(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		out[r.key] = r
	return out


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)
