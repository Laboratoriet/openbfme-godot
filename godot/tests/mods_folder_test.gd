## Lane IOS-28: the Mods folder's list and the Mods tab (scripts/release/mods.gd, scripts/release/mods_tab.gd) on a generated folder: the
## OpenBFMEMods value both ways, mod.txt, what the folder scan counts as a mod, the online / LAN refusal, and the tab's rows and states (empty,
## a mod off, on with "Restart to apply", a mod no longer in the folder, the reasons it is greyed). Headless, no game data, no shell.
## Lane IOS-31: install-folder mods (Edain) in the folder: what the scan makes of them (title from openbfme-aio.json, size, a layer of another
## package), the tab's one-at-a-time refusal and load order, and the mounted names / online refusal with one mounted.
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
	_install()
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


# lane IOS-31
func _install() -> void:
	var dir := ProjectSettings.globalize_path("user://mods-install-test")
	_remove_tree(dir)
	for d in ["Edain/install/lang", "Edain_assets", "Unchained/install", "Small", "Game Copy/lang"]:
		DirAccess.make_dir_recursive_absolute(dir.path_join(d))
	_write(dir.path_join("Edain/openbfme-aio.json"), JSON.stringify({"schema": "openbfme.aio-package 2", "guid": "e", "name": "Edain", "version": "4.8.5.4",
		"type": 0, "stack": [{"folder": "Edain_assets", "name": "Edain assets", "guid": "a", "parts": []},
		{"folder": "Edain", "name": "Edain", "guid": "e", "parts": ["install"]}], "engine_edits": []}))
	_write(dir.path_join("Edain/install/__edain_data.big"), "BIGF0123456789") # 14 bytes: the scan does not open archives
	_write(dir.path_join("Edain/install/lang/English.big"), "BIGF")
	_write(dir.path_join("Edain_assets/openbfme-aio.json"), JSON.stringify({"schema": "openbfme.aio-package 2", "guid": "a", "name": "Edain assets",
		"stack": null, "dependency_only": true}))
	_write(dir.path_join("Unchained/install/__edain_data.big"), "BIGF")
	_write(dir.path_join("Small/zzz.big"), "BIGF")
	_write(dir.path_join("Game Copy/lang/English.big"), "BIGF")
	_write(dir.path_join("Game Copy/mod.txt"), "Title = My copy\n")
	var found := {}
	for m in Mods.scan(dir):
		found[m.name] = m
	check(found.size() == 5, "five entries: %s" % str(found.keys()))
	if found.size() != 5:
		_remove_tree(dir)
		return
	var record_bytes := FileAccess.get_file_as_bytes(dir.path_join("Edain/openbfme-aio.json")).size()
	check(found.Edain.kind == "install" and found.Edain.title == "Edain 4.8.5.4" and found.Edain.problem.is_empty(),
		"an AIO package: an install-folder mod titled by its record: %s" % str(found.Edain))
	check(found.Edain.bytes == 14 + 4 + record_bytes, "its size: every file below it (%d)" % found.Edain.bytes)
	check(found.Edain_assets.kind == "part" and not found.Edain_assets.problem.is_empty(), "a dependency-only layer is a part, not a mod")
	check(found.Unchained.kind == "install" and found.Unchained.title == "Unchained", "an install/ folder without a record")
	check(found["Game Copy"].kind == "install" and found["Game Copy"].title == "My copy", "a copy of the game-folder files (lang\\*.big); mod.txt's title wins")
	check(found.Small.kind == "folder", "a -mod folder stays one")
	check(Mods.size_text(4_159_249_628) == "4.2 GB" and Mods.size_text(6_196_473_049) == "6.2 GB" and Mods.size_text(310_000) == "310 KB" \
		and Mods.size_text(12) == "1 KB" and Mods.size_text(25_400_000) == "25 MB", "sizes in decimal units")

	var mount := {"ok": true, "rotwk_install": "/games/RotWK", "mod": {"mounted": false, "source": "", "mods_folder": dir}}
	var tab := Tab.new()
	tab.mount_getter = func(): return mount
	tab.begin("Small")
	check(tab.set_mod("Mod:Edain", true) and tab.value() == "Small;Edain", "Edain on after Small")
	var rows := _keyed(tab.rows())
	check(rows["Mod:Edain"].help.contains("install-folder mod Edain") and rows["Mod:Edain"].help.contains("loads 1st of 2"),
		"Edain loads first, under Small, though turned on last: %s" % rows["Mod:Edain"].help)
	check(rows["Mod:Small"].help.contains("loads 2nd of 2"), "Small loads over it")
	check(tab.set_mod("Mod:Unchained", true) and tab.value() == "Small;Edain", "a second install-folder mod is refused (its box stays off)")
	rows = _keyed(tab.rows())
	check(rows["Mod:Unchained"].value == 0 and rows["Mods.state"].value_text == "One install mod at a time", "the Status row says why")
	check(tab.note().begins_with("Only one install-folder mod at a time: turn Edain 4.8.5.4 off first"), tab.note())
	check(not rows["Mod:Edain_assets"].enabled and rows["Mod:Edain_assets"].help.begins_with("A part of another mod"), "a part's box is greyed, with why")
	check(tab.set_mod("Mod:Edain", false) and tab.set_mod("Mod:Unchained", true) and tab.value() == "Small;Unchained", "after Edain is off, Unchained can be on")
	check(_keyed(tab.rows())["Mods.state"].value_text == "Restart to apply", "the refusal is gone after the next change")

	# a start that mounted Edain from the Mods folder (and Small over it): both mounted, online and LAN off
	mount.mod = {"mounted": true, "source": "mods folder", "list": PackedStringArray(["Small", "Edain"]), "missing": PackedStringArray(),
		"install_mod_name": "Edain", "install_mod_source": "mods folder", "install_mod_skipped": "", "mods_folder": dir}
	check(Mods.mounted_names(mount) == PackedStringArray(["Small", "Edain"]), "both mounted")
	tab.begin("Small;Edain")
	check(not tab.restart_needed() and _keyed(tab.rows())["Mods.state"].value_text == "2 mods in use", "as mounted: 2 mods in use")
	# Edain alone: no -mod-style mod mounted, but Edain is
	mount.mod = {"mounted": false, "source": "mods folder", "list": PackedStringArray(["Edain"]), "missing": PackedStringArray(),
		"install_mod_name": "Edain", "install_mod_source": "mods folder", "install_mod_skipped": "", "mods_folder": dir}
	check(Mods.mounted_names(mount) == PackedStringArray(["Edain"]), "Edain alone is mounted")
	check(Mods.multiplayer_refusal(mount).begins_with("Online and LAN games are off while mods are on (Edain)"), Mods.multiplayer_refusal(mount))
	# a --mod-install on the command line took its place: not mounted from the folder
	mount.mod = {"mounted": true, "source": "mods folder", "list": PackedStringArray(["Small", "Edain"]), "missing": PackedStringArray(),
		"install_mod_name": "", "install_mod_source": "command line", "install_mod_skipped": "Edain", "mods_folder": dir}
	check(Mods.mounted_names(mount) == PackedStringArray(["Small"]), "--mod-install wins over the folder's install-folder mod")
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
