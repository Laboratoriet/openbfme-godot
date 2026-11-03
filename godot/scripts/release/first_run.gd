## Lane RELEASE-1: the first-run screen. OpenBFME runs on the player's own copies of The Rise of the Witch-king 2.01 and The Battle for
## Middle-earth II 1.06; this screen finds them (InstallSetup.discover: the registry keys retail and the community installers write, Wine / Proton
## prefixes on Linux, the installers' default folders), lets the player confirm or choose the two folders, checks them (every 2.01 / 1.06 archive
## present with its size; a clear message naming what is wrong) and, once the full mount (every archive's md5) succeeded, remembers them in
## user://install-paths.cfg. Nothing found is never silently replaced by a guess: the player always confirms.
##
## Shown by Release.mount_retail (scripts/release/release.gd) before the retail shell exists, so it is plain Godot UI, not an Apt movie
## (UI-2's menus start after it). run() returns the mount report; {ok: false, quit: true} when the player quits.
##
## Test hooks (the fresh-user test, godot/tests/first_run_test.gd), also headless: test_pick {accept: true} takes the first discovered folders
## that pass the check; {rotwk, bfme2} picks those folders. Every step prints a FIRST RUN line; a rejected pick ends the run with ok false.
## --first-run-shot=FILE (windowed): save the screen as it first appears to FILE and quit (the media, the layout check).
##
## Lane IOS-4, iPhone / iPad: an app reads only its own folders and Godot's folder dialog cannot pick one elsewhere, so there is no Browse.
## The screen says how to copy the two game folders into the app's Documents folder (the Files app's "On My iPhone > OpenBFME") as RotWK
## and BFME2, shows the check of what is there, and looks again when the player comes back to the app (or taps Look again). They are not
## remembered as paths: Release finds them on every start (InstallLocator.h "iOS"). No Quit button: an iOS app is not quit by itself.
##
## Lane IOS-9: the screen leads with ONE file instead: OpenBFME-GameData.obfme, made on the Mac by tools/ios/make_game_file.py and copied into
## the app (Finder, AirDrop + Save to Files, the Files app). When one is in the app's folder the screen offers to install it (game_file_import.gd:
## free space first, then every file streamed into RotWK / BFME2 and checked, with progress; the file is deleted afterwards) and then goes on to the
## check and mount by itself. Copying the two folders stays as the other way, below it.
extends CanvasLayer

const GameFileImport := preload("res://scripts/release/game_file_import.gd")

signal finished(result: Dictionary)

var _fs: RefCounted
var _setup: RefCounted
var _found: Array = []
var _rotwk_edit: LineEdit
var _bfme2_edit: LineEdit
var _rotwk_found: OptionButton
var _bfme2_found: OptionButton
var _status: RichTextLabel
var _start: Button
var _dialog: FileDialog
var _dialog_target: LineEdit
var _checked_ok := false
# lane IOS-4
var _ios := OS.has_feature("ios") or OS.get_cmdline_user_args().has("--first-run-ios") # the dev switch: the iOS screen on a desktop (layout checks)
var _frame: Control            # iOS: the screen laid out in points and scaled to the display's pixels
var _margin: MarginContainer   # iOS: kept clear of the notch / home indicator (the display's safe area)
var _mounting := false         # the full check is running: coming back to the app must not look again over it
# lane IOS-9: the one-file install
var _import: GameFileImport    # the game file offered, null when none
var _importing := false        # the install is running: coming back to the app must not look again over it
var _import_box: VBoxContainer
var _import_title: Label
var _import_note: RichTextLabel
var _import_bar: ProgressBar
var _import_button: Button
var _again: Button


func run(fs: RefCounted, setup: RefCounted, problem: String, test_pick: Dictionary) -> Dictionary:
	_fs = fs
	_setup = setup
	layer = 90
	_found = setup.discover()
	# lane AIO-1: a launcher record of downloaded folders that cannot be read is said on the screen, not only in the log
	var marker: String = setup.downloaded_problem()
	if not marker.is_empty():
		print(Release.info.redact("FIRST RUN " + marker))
		problem = marker if problem.is_empty() else problem + "\n" + marker
	for c in _found:
		print(Release.info.redact("FIRST RUN found %s: %s (%s) %s" % [c.game, c.path, c.source, "ok" if c.ok else "rejected: " + "; ".join(c.errors)]))
	if DisplayServer.get_name() != "headless":
		_build_ui(problem)
	if not test_pick.is_empty():
		return await _run_test(test_pick)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--first-run-shot=") and DisplayServer.get_name() != "headless":
			for i in 20:
				await get_tree().process_frame
			var shot := arg.substr(17)
			get_viewport().get_texture().get_image().save_png(shot)
			print("FIRST RUN screenshot: ", shot)
			return {"ok": false, "quit": true, "errors": ["screenshot taken"]}
	return await finished


func _run_test(pick: Dictionary) -> Dictionary:
	var rotwk: String = pick.get("rotwk", "")
	var bfme2: String = pick.get("bfme2", "")
	if pick.get("accept", false):
		rotwk = _first_ok("rotwk")
		bfme2 = _first_ok("bfme2")
		if rotwk.is_empty() or bfme2.is_empty():
			print("FIRST RUN nothing to accept: rotwk '%s', bfme2 '%s'" % [Release.info.redact(rotwk), Release.info.redact(bfme2)])
			return {"ok": false, "errors": ["the first-run test found no usable game folders to accept"]}
	var checked: Dictionary = _setup.check(rotwk, bfme2)
	print("FIRST RUN check: ok %s" % str(checked.ok))
	for e in checked.errors:
		print("FIRST RUN rejected: ", e)
	if not checked.ok:
		return {"ok": false, "errors": Array(checked.errors)}
	return _mount_and_remember(rotwk, bfme2)


func _first_ok(game: String) -> String:
	for c in _found:
		if c.game == game and c.ok:
			return c.path
	return ""


func _mount_and_remember(rotwk: String, bfme2: String) -> Dictionary:
	var mount: Dictionary = _fs.mount_retail_paths(rotwk, bfme2)
	print("FIRST RUN mount: ok %s" % str(mount.ok))
	if not mount.ok:
		for e in mount.errors:
			print("FIRST RUN mount error: ", e)
		return mount
	if _ios:
		# lane IOS-4: found again on every start instead (iOS may move the app's container, which would break a remembered path)
		print("FIRST RUN not remembered: on iOS the folders in the app's Documents folder are found on every start")
		return mount
	var saved: Dictionary = _setup.remember(rotwk, bfme2)
	print("FIRST RUN remembered: %s %s" % [str(saved.ok), saved.error])
	if not saved.ok:
		return {"ok": false, "errors": ["the game folders work but could not be saved: " + saved.error]}
	return mount


# ---- the screen ----------------------------------------------------------------------------------------------------------------------------

func _build_ui(problem: String) -> void:
	var root: Node = self
	if _ios:
		_frame = Control.new()
		add_child(_frame)
		root = _frame
	var back := ColorRect.new()
	back.color = Color(0.06, 0.06, 0.07)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	root.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	if _ios:
		# lane IOS-4: the steps are longer than a phone held upright is tall
		_margin = margin
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		margin.add_child(scroll)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(box)
		_fit_frame()
		get_viewport().size_changed.connect(_fit_frame)
	else:
		margin.add_child(box)

	var title := Label.new()
	title.text = "OpenBFME - choose your game folders"
	if _ios:
		title.text = "OpenBFME - add your game files"
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _ios:
		intro.text = _ios_steps()
	else:
		intro.text = ("OpenBFME plays on your own copy of the game: The Rise of the Witch-king patched to 2.01 and The Battle for Middle-earth II "
			+ "patched to 1.06, in any language. They stay where they are; OpenBFME only reads them and never changes them.\n"
			+ "Choose the two folders that hold the games' .big files. Folders found on this computer are offered below.")
	box.add_child(intro)
	if not problem.is_empty():
		var warn := Label.new()
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
		warn.text = problem
		box.add_child(warn)
	if _ios:
		_build_import(box)

	var rows := [["The Rise of the Witch-king 2.01", "rotwk", "RotWK"], ["The Battle for Middle-earth II 1.06", "bfme2", "BFME2"]]
	for row in rows:
		var label := Label.new()
		label.text = row[0]
		label.add_theme_font_size_override("font_size", 18)
		box.add_child(label)
		if _ios:
			# lane IOS-4: each game has one place; the edit (hidden: the container path means nothing to the player) holds the folder found
			var place := Label.new()
			place.text = "%s > OpenBFME > %s" % [_ios_place(), row[2]]
			place.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
			box.add_child(place)
			var held := LineEdit.new()
			held.visible = false
			held.text = _first_found(row[1])
			box.add_child(held)
			if row[1] == "rotwk":
				_rotwk_edit = held
			else:
				_bfme2_edit = held
			continue
		var found := OptionButton.new()
		found.fit_to_longest_item = false # a long path must not push the screen wider than the window
		found.clip_text = true
		found.add_item("Found on this computer: choose one" if _count(row[1]) > 0 else "Not found automatically: use Browse")
		found.set_item_disabled(0, true)
		for c in _found:
			if c.game == row[1]:
				found.add_item(("OK   " if c.ok else "not usable   ") + c.path)
				found.set_item_metadata(found.item_count - 1, c.path)
				found.set_item_tooltip(found.item_count - 1, c.source + ("" if c.ok else "\n" + "\n".join(c.errors)))
		box.add_child(found)
		var line := HBoxContainer.new()
		var edit := LineEdit.new()
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.placeholder_text = "folder of " + row[0]
		var browse := Button.new()
		browse.text = "Browse..."
		line.add_child(edit)
		line.add_child(browse)
		box.add_child(line)
		# checked when the player is done typing (Enter, leaving the field), not per key: a half-typed "/" is not worth a folder walk
		edit.text_changed.connect(func(_t): _start.disabled = true)
		edit.text_submitted.connect(func(_t): _recheck())
		edit.focus_exited.connect(_recheck)
		browse.pressed.connect(_browse.bind(edit, row[0]))
		found.item_selected.connect(func(i): edit.text = str(found.get_item_metadata(i)); _recheck())
		if row[1] == "rotwk":
			_rotwk_edit = edit
			_rotwk_found = found
		else:
			_bfme2_edit = edit
			_bfme2_found = found
		# preselect the first usable folder found
		for i in range(1, found.item_count):
			if str(found.get_item_text(i)).begins_with("OK"):
				found.select(i)
				edit.text = str(found.get_item_metadata(i))
				break

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status.selection_enabled = true
	box.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	if _ios:
		_again = Button.new()
		_again.text = "Look again"
		_again.pressed.connect(_look_again)
		buttons.add_child(_again)
	else:
		var quit := Button.new()
		quit.text = "Quit"
		quit.pressed.connect(func(): finished.emit({"ok": false, "quit": true, "errors": ["the player quit on the first-run screen"]}))
		buttons.add_child(quit)
	_start = Button.new()
	_start.text = "Use these folders"
	_start.pressed.connect(_on_start)
	buttons.add_child(_start)
	box.add_child(buttons)
	var version := Label.new()
	version.text = Release.display_line()  # lane VERSION-1: "OpenBFME Alpha 0.4.5 (<date>)"
	version.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # lane IOS-4: a nightly's long version line must not widen the screen past a phone's width
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	box.add_child(version)

	if _ios:
		_recheck()
		_refresh_import()
		return
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.dir_selected.connect(func(d): _dialog_target.text = d; _recheck())
	add_child(_dialog)
	_recheck()


func _count(game: String) -> int:
	var n := 0
	for c in _found:
		if c.game == game:
			n += 1
	return n


func _browse(edit: LineEdit, what: String) -> void:
	_dialog_target = edit
	_dialog.title = "Folder of " + what
	if not edit.text.is_empty():
		_dialog.current_dir = edit.text
	_dialog.popup_centered_ratio(0.7)


func _recheck() -> void:
	var r: Dictionary = _setup.check(_rotwk_edit.text, _bfme2_edit.text)
	_checked_ok = r.ok
	_start.disabled = not r.ok
	var t := ""
	for game in [["rotwk", "The Rise of the Witch-king", "RotWK"], ["bfme2", "The Battle for Middle-earth II", "BFME2"]]:
		var g: Dictionary = r[game[0]]
		var held: LineEdit = _rotwk_edit if game[0] == "rotwk" else _bfme2_edit
		if _ios and held.text.is_empty():
			# lane IOS-4: not copied yet (or under another name): the check's "no folder chosen" would ask for a choice there is no way to make
			t += "[color=#f98]%s: no folder named %s in %s > OpenBFME yet[/color]\n" % [game[1], game[2], _ios_place()]
		elif g.ok:
			# issue #49: the language the folder holds (the game plays in it; the launcher's Game files screen downloads another)
			# PR #77: the language and file names come from the disk: "[" is escaped so a name cannot add BBCode to this RichTextLabel
			var lang := String(g.get("language", "")).replace("[", "[lb]")
			var voice := String(g.get("voice", "")).replace("[", "[lb]")
			if voice != "" and voice != lang:
				lang = "%s, %s voices" % [lang, voice]
			t += "[color=#8f8]%s: found, %d of %d archives%s[/color]\n" % [game[1], g.present, g.expected, (", " + lang) if lang != "" else ""]
			if not g.get("unpinned_language_archives", PackedStringArray()).is_empty():
				var files := ", ".join(g.unpinned_language_archives).replace("[", "[lb]")
				t += "[color=#fd8]%s: OpenBFME has not checked this language yet (%s); it can be played, and the game explains what that means when it starts[/color]\n" % [game[1], files]
		else:
			for e in g.errors:
				t += "[color=#f98]%s: %s[/color]\n" % [game[1], e]
	_status.text = t


func _on_start() -> void:
	if not _checked_ok:
		return
	_start.disabled = true
	_mounting = true
	_status.text = "Checking every game file (the first time this can take a minute)..."
	await get_tree().process_frame
	await get_tree().process_frame
	var mount := _mount_and_remember(_rotwk_edit.text, _bfme2_edit.text)
	_mounting = false
	if mount.ok:
		finished.emit(mount)
		return
	var t := "[color=#f98]The folders could not be used:[/color]\n"
	for e in mount.errors:
		t += "[color=#f98]%s[/color]\n" % e
	_status.text = t
	_start.disabled = false


# ---- lane IOS-4: iPhone / iPad -------------------------------------------------------------------------------------------------------------

func _notification(what: int) -> void:
	# back from the Files app or Finder (iOS sends this when the app becomes active again): look again by itself
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _ios and _status != null:
		_look_again()


func _look_again() -> void:
	if _mounting or _importing:
		return
	_found = _setup.discover()
	print("FIRST RUN looking again: %d folders found" % _found.size())
	for c in _found:
		print(Release.info.redact("FIRST RUN found %s: %s (%s) %s" % [c.game, c.path, c.source, "ok" if c.ok else "rejected: " + "; ".join(c.errors)]))
	_rotwk_edit.text = _first_found("rotwk")
	_bfme2_edit.text = _first_found("bfme2")
	_recheck()
	_refresh_import()


# the folder discover() found for `game`, usable or not (on iOS there is one place per game: its check says what is wrong); "" = none
func _first_found(game: String) -> String:
	for c in _found:
		if c.game == game:
			return c.path
	return ""


# the Files app's name for the device's own storage (OS.get_model_name() is the hardware id, e.g. "iPhone17,1" or "iPad16,3")
func _ios_device() -> String:
	return "iPad" if OS.get_model_name().begins_with("iPad") else "iPhone"


func _ios_place() -> String:
	return "On My " + _ios_device()


func _ios_steps() -> String:
	var device := _ios_device()
	return ("OpenBFME plays on your own copy of the game: The Rise of the Witch-king patched to 2.01 and The Battle for Middle-earth II "
		+ "patched to 1.06, in any language. OpenBFME only reads the files and never changes them.\n"
		+ "1. On your Mac, make the game file: python3 tools/ios/make_game_file.py --rotwk <RotWK folder> --bfme2 <BFME2 folder>. "
		+ "It writes OpenBFME-GameData.obfme.\n"
		+ "2. Connect this %s, select it in Finder, open Files and drag OpenBFME-GameData.obfme onto OpenBFME. "
		+ "Or AirDrop it to this %s and save it to %s > OpenBFME.\n"
		+ "3. Come back here and tap Install. OpenBFME checks every file, sets the game up and deletes the game file.") % [
		device, device, _ios_place()]


# lane IOS-9: the other way, under the install panel: the two folders copied by hand (lane IOS-4)
func _ios_folder_steps() -> String:
	return ("Copy each game's whole folder (the one with its .big files, and every folder in it) into %s > OpenBFME, named exactly RotWK "
		+ "and BFME2. Together they need about 9 GB. Then come back here (or tap Look again) and tap Use these folders.") % _ios_place()


# ---- lane IOS-9: the one-file install -----------------------------------------------------------------------------------------------------

# The install panel (shown when a game file is in the app's folder), then the heading of the other way: the two folders.
func _build_import(box: VBoxContainer) -> void:
	_import_box = VBoxContainer.new()
	_import_box.add_theme_constant_override("separation", 10)
	_import_box.visible = false
	box.add_child(_import_box)
	_import_title = Label.new()
	_import_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_import_title.add_theme_font_size_override("font_size", 18)
	_import_box.add_child(_import_title)
	_import_bar = ProgressBar.new()
	_import_bar.max_value = 1.0
	_import_bar.step = 0.0
	_import_bar.visible = false
	_import_box.add_child(_import_bar)
	_import_note = RichTextLabel.new()
	_import_note.bbcode_enabled = true
	_import_note.fit_content = true
	_import_note.scroll_active = false
	_import_note.selection_enabled = true
	_import_box.add_child(_import_note)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_END
	_import_button = Button.new()
	_import_button.text = "Install"
	_import_button.custom_minimum_size = Vector2(160, 44) # a finger's target (Apple's 44 points)
	_import_button.pressed.connect(_on_install)
	line.add_child(_import_button)
	_import_box.add_child(line)
	var other := Label.new()
	other.text = "Or copy the two game folders"
	other.add_theme_font_size_override("font_size", 22)
	box.add_child(other)
	var steps := Label.new()
	steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steps.text = _ios_folder_steps()
	box.add_child(steps)


# Looks for a game file and says what installing it needs. Nothing is installed until the player taps Install.
func _refresh_import() -> void:
	if _importing or _import_box == null:
		return
	_import = null
	_import_bar.visible = false
	_import_button.visible = true
	_import_button.disabled = true
	var found := GameFileImport.find()
	var pending := GameFileImport.pending()
	if found.is_empty():
		_import_box.visible = pending
		if pending:
			# the folders hold part of an install: say so instead of letting their check read as a broken copy
			_import_title.text = "The install from the game file did not finish"
			_import_note.text = "[color=#fd8]Copy OpenBFME-GameData.obfme into OpenBFME again (step 2) and tap Install: it carries on where it stopped.[/color]"
			_import_button.visible = false
		return
	_import_box.visible = true
	var imp := GameFileImport.new()
	var shown_name := found[0].get_file().replace("[", "[lb]")
	var others := "" if found.size() == 1 else "\n[color=#aaa]%d other .obfme files in OpenBFME's folder are not used; delete them in the Files app.[/color]" % (found.size() - 1)
	if not imp.open(found[0]):
		print("FIRST RUN game file: ", imp.error)
		_import_title.text = "This game file cannot be used"
		_import_note.text = "[color=#f98]%s[/color]%s" % [imp.error.replace("[", "[lb]"), others]
		_import_button.visible = false
		return
	print("FIRST RUN game file: %s, %d files, %d bytes (%d still to install)" % [found[0].get_file(), imp.files.size(), imp.total, imp.remaining])
	if _checked_ok and not pending:
		_import_title.text = "The game folders are already here"
		_import_note.text = "[color=#aaa]%s is not needed. Delete it in the Files app to get its %s back.[/color]%s" % [
			shown_name, GameFileImport.gb(imp.archive_size), others]
		_import_button.visible = false
		return
	_import = imp
	_import_title.text = "Install the game files from %s (%s)" % [found[0].get_file(), GameFileImport.gb(imp.archive_size)]
	_import_button.text = "Continue installing" if imp.resuming else "Install"
	var free: int = imp.space_left()
	var need: int = imp.space_needed()
	if free > 0 and free < need:
		_import_note.text = ("[color=#f98]Not enough space: installing needs %s free and this %s has %s. Free some space (Settings > General > "
			+ "%s Storage), then come back here.[/color]%s") % [GameFileImport.gb(need), _ios_device(), GameFileImport.gb(free), _ios_device(), others]
		return
	var space := ("%s free, %s needed" % [GameFileImport.gb(free), GameFileImport.gb(need)]) if free > 0 else (
		"needs %s free (OpenBFME could not read how much is free)" % GameFileImport.gb(need))
	_import_note.text = ("[color=#aaa]%s. Takes a few minutes: keep OpenBFME open. The game file is deleted when the game files are in place.[/color]%s"
		% [space, others])
	_import_button.disabled = false


func _on_install() -> void:
	if _import == null or _importing or _mounting:
		return
	_importing = true
	_import_button.disabled = true
	_again.disabled = true
	_start.disabled = true
	_import_bar.visible = true
	_import_bar.value = 0.0
	var kept_on := DisplayServer.screen_is_kept_on()
	DisplayServer.screen_set_keep_on(true) # the screen must not lock (and the app stop) halfway through
	_import.progress.connect(_on_import_progress)
	print("FIRST RUN installing the game file %s" % _import.file_name)
	var ok: bool = await _import.run()
	_import.progress.disconnect(_on_import_progress)
	DisplayServer.screen_set_keep_on(kept_on)
	_importing = false
	_again.disabled = false
	if not ok:
		print("FIRST RUN game file install stopped: ", _import.error)
		_import_note.text = "[color=#f98]Installing stopped: %s[/color]" % _import.error.replace("[", "[lb]")
		_import_button.text = "Try again"
		_import_button.disabled = false
		_recheck()
		return
	print("FIRST RUN game file installed: %d files" % _import.files.size())
	_import = null
	_import_box.visible = false
	_look_again()
	if _checked_ok:
		_on_start() # straight on to the full check and the game, as Use these folders would


func _on_import_progress(done_bytes: int, total_bytes: int, file_index: int, file_count: int, file_path: String) -> void:
	_import_bar.value = float(done_bytes) / maxf(1.0, float(total_bytes))
	_import_note.text = "[color=#aaa]%s of %s, file %d of %d\n%s[/color]" % [GameFileImport.gb(done_bytes), GameFileImport.gb(total_bytes), file_index,
		file_count, file_path.replace("[", "[lb]")]


# The window is the display's own pixels (IOS-3: native size), so this screen is laid out in points (pixels / the display's scale) and
# scaled up, its margins widened by the safe area's insets (the notch / Dynamic Island, the home indicator). Again on rotation.
func _fit_frame() -> void:
	var s := maxf(1.0, DisplayServer.screen_get_scale())
	var view := get_viewport().get_visible_rect().size
	_frame.scale = Vector2(s, s)
	_frame.size = view / s
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var insets := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if safe.has_area():
		insets = {"left": safe.position.x, "top": safe.position.y, "right": view.x - safe.end.x, "bottom": view.y - safe.end.y}
	for side in insets:
		_margin.add_theme_constant_override("margin_" + side, int(24.0 + maxf(0.0, insets[side]) / s))
