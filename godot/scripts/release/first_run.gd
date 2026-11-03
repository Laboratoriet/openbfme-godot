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
##
## Lane IOS-12: the iOS screen is a step-by-step welcome in the game menus' colours: a header, the status card (the live part: looking for
## the game file, found + Install, installing, checking, errors with what to do), three numbered step cards (make the file on the Mac, send
## it to the device, install), Open in Files + Look again, the two-folder way folded away under "Other ways to add the game", the version.
## Wider than WIDE_FROM points (the iPhone Duo's inner screen in landscape) it is two columns: the header and status card on the left, the
## steps on the right, each column scrolling on its own. Colours, type, spacing and radii are the tokens below; the art goes in
## res://assets/setup/ (its README: logo.png, step-1.png .. step-3.png, each shown only when it is there). The desktop screen is unchanged.
extends CanvasLayer

const GameFileImport := preload("res://scripts/release/game_file_import.gd")

# ---- lane IOS-12: the iOS screen's tokens (points: the iOS frame is laid out in points, _fit_frame) ------------------------------------------
# colour
const C_BG := Color(0.06, 0.06, 0.07)                # the screen
const C_CARD := Color(0.09, 0.09, 0.10)              # a step card: one step lighter than the screen
const C_CARD_LIVE := Color(0.11, 0.10, 0.09)         # the status card: a little warmer, it is the live part
const C_CODE := Color(0.0, 0.0, 0.0, 0.35)           # the command block, sunk into its card
const C_BORDER := Color(1, 1, 1, 0.12)               # every card's 1 px edge
const C_BORDER_LIVE := Color(0.784, 0.635, 0.353, 0.4) # the status card's edge: the accent at 40 %
const C_ACCENT := Color("c8a25a")                    # BFME's menu gold: headings, the primary button, step numbers
const C_ACCENT_HOVER := Color("d6b679")
const C_ACCENT_PRESSED := Color("a8853f")
const C_ACCENT_DISABLED := Color(0.784, 0.635, 0.353, 0.25)
const C_ON_ACCENT := Color(0.06, 0.06, 0.07)         # text on the gold button
const C_HEADING := C_ACCENT                          # the title and the step headings (C_TEXT for white headings)
const C_TEXT := Color(1, 1, 1, 1.0)                  # primary
const C_TEXT_2 := Color(1, 1, 1, 0.7)                # secondary
const C_TEXT_3 := Color(1, 1, 1, 0.5)                # tertiary
const C_FILL := Color(1, 1, 1, 0.06)                 # a secondary button
const C_FILL_HOVER := Color(1, 1, 1, 0.10)
const C_FILL_PRESSED := Color(1, 1, 1, 0.16)
const C_BUTTON_EDGE := Color(1, 1, 1, 0.24)          # a secondary button's 1 px edge
const C_FOCUS := Color(1, 1, 1, 0.85)                # the keyboard focus ring (an iPad with a keyboard)
const C_OK := Color("88ff88")                        # the check's colours (_recheck's #8f8 / #fd8 / #f98)
const C_WARN := Color("ffdd88")
const C_ERROR := Color("ff9988")
const C_TRACK := Color(1, 1, 1, 0.10)                # the progress bar's empty part
const C_BADGE := Color(0.784, 0.635, 0.353, 0.16)    # a step number's disc: the accent at 16 %
# type (points)
const TYPE_TITLE := 30
const TYPE_HEADING := 19
const TYPE_BODY := 16
const TYPE_CAPTION := 13
const MONO_FONTS := ["Menlo", "SF Mono", "Consolas", "DejaVu Sans Mono", "monospace"] # the command block (Menlo ships with iOS)
# space (points)
const SPACE_XS := 8
const SPACE_S := 16
const SPACE_M := 24
const SPACE_L := 32
# shape and size (points)
const RADIUS := 12               # cards
const RADIUS_S := 8              # buttons, the command block
const BORDER := 1
const FOCUS_WIDTH := 2
const TOUCH_MIN := 44            # Apple's smallest finger target
const TOUCH_PRIMARY := 52        # the Install button
const BAR_HEIGHT := 8            # the install's progress bar
const BADGE := 32                # a step's number circle
const LOGO_HEIGHT := 40          # res://assets/setup/logo.png is shown this tall, its width from its aspect
const CONTENT_MAX := 560         # one column's widest
const WIDE_FROM := 820           # from this frame width on: two columns
# the art (res://assets/setup/README.md): each is shown only when it is there
const ART_LOGO := "res://assets/setup/logo.png"
const ART_STEP := "res://assets/setup/step-%d.png"
const MAKE_COMMAND := "python3 tools/ios/make_game_file.py --rotwk <RotWK folder> --bfme2 <BFME2 folder>"
# shown one flag a line (a wrap must never split "--bfme2"), still a valid shell command when selected and pasted; Copy copies MAKE_COMMAND
const MAKE_COMMAND_SHOWN := "python3 tools/ios/make_game_file.py \\\n  --rotwk <RotWK folder> \\\n  --bfme2 <BFME2 folder>"

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
var _card: PanelContainer      # lane IOS-12: the status card (the install panel of IOS-9, now always shown)
var _import_title: Label
var _import_note: RichTextLabel
var _import_bar: ProgressBar
var _import_button: Button     # the card's one action: Install / Continue installing / Try again, or Start when the folders are ready
var _again: Button
# lane IOS-12: the welcome screen's layout
var _wide = null               # two columns (null: not laid out yet)
var _scroll_main: ScrollContainer
var _scroll_steps: ScrollContainer
var _col_main: VBoxContainer   # header, status card, (steps when narrow), actions, other ways, version
var _col_steps: VBoxContainer  # the steps when wide
var _steps: Array[Control] = []
var _actions: Control          # Open in Files + Look again: the steps go in front of it when narrow
var _files_hint: Label         # said when the Files app could not be opened
var _other_box: VBoxContainer  # the two-folder way, folded away
var _other_state: Label        # Show / Hide on the fold's button
var _copy: Button
var _end_pads: Array[Control] = [] # each column's last child: the bottom safe area, inside the scroll (it scrolls to the screen's edge)


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
	if _ios:
		_build_ios_ui(problem) # lane IOS-12: the welcome screen (below)
		return
	var root: Node = self
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
	margin.add_child(box)

	var title := Label.new()
	title.text = "OpenBFME - choose your game folders"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

	var rows := [["The Rise of the Witch-king 2.01", "rotwk", "RotWK"], ["The Battle for Middle-earth II 1.06", "bfme2", "BFME2"]]
	for row in rows:
		var label := Label.new()
		label.text = row[0]
		label.add_theme_font_size_override("font_size", 18)
		box.add_child(label)
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
			# lane IOS-12: said in the tertiary colour, not as an error: on the one-file way these folders are not expected yet
			t += "[color=#%s]%s: no folder named %s in %s › OpenBFME yet[/color]\n" % [C_TEXT_3.to_html(), game[1], game[2], _ios_place()]
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
	if _ios:
		# lane IOS-12: said on the status card, where the player is looking (the folders' own status is folded away)
		_import_bar.visible = false
		_show_card("Checking every game file…", _bb("The first time this can take a minute. Keep OpenBFME open.", C_TEXT_3))
	await get_tree().process_frame
	await get_tree().process_frame
	var mount := _mount_and_remember(_rotwk_edit.text, _bfme2_edit.text)
	_mounting = false
	if mount.ok:
		if _ios:
			_show_card("Ready", _bb("Starting OpenBFME…", C_TEXT_3))
		finished.emit(mount)
		return
	var t := "[color=#f98]The folders could not be used:[/color]\n"
	for e in mount.errors:
		t += "[color=#f98]%s[/color]\n" % e
	_status.text = t
	_start.disabled = false
	if _ios:
		_show_card("The game files could not be used", _bb("\n".join(mount.errors), C_ERROR), "Try again")


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




# lane IOS-9: the other way, folded away under "Other ways to add the game" (IOS-12): the two folders copied by hand (lane IOS-4)
func _ios_folder_steps() -> String:
	return ("Copy each game's whole folder (the one with its .big files, and every folder in it) into %s › OpenBFME, named exactly RotWK "
		+ "and BFME2. Together they need about 9 GB. Then come back here (or tap Look again) and tap Use these folders.") % _ios_place()


# ---- lane IOS-12: the welcome screen -------------------------------------------------------------------------------------------------------

# Header, status card, the three steps, Open in Files + Look again, the other ways (folded), the version. _fit_frame lays them out in one
# column or two.
func _build_ios_ui(problem: String) -> void:
	_frame = Control.new()
	# text drawn at the frame's scale, not drawn at 1x and stretched (soft on a 2x / 3x display); the children inherit it
	_frame.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
	add_child(_frame)
	var back := ColorRect.new()
	back.color = C_BG
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(back)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(_margin)
	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", SPACE_L)
	_margin.add_child(columns)
	# lane IOS-4: the steps are longer than a phone held upright is tall. Each column scrolls on its own (two columns: the status card stays
	# in view while the steps scroll); the bars are hidden as iOS hides them, so a column is exactly its width
	_scroll_main = _scroll(columns)
	_col_main = _column(_scroll_main)
	_scroll_steps = _scroll(columns)
	_col_steps = _column(_scroll_steps)

	# 1. the header
	var header := _vbox(SPACE_XS)
	if ResourceLoader.exists(ART_LOGO):
		var logo := TextureRect.new()
		logo.texture = load(ART_LOGO)
		logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.custom_minimum_size.y = LOGO_HEIGHT
		logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # a clean downscale when the import made mipmaps
		header.add_child(logo)
	else:
		header.add_child(_label("OpenBFME", TYPE_HEADING, C_ACCENT))
	header.add_child(_label("Add your game", TYPE_TITLE, C_HEADING))
	header.add_child(_label("OpenBFME plays on your own copy of The Rise of the Witch-king 2.01 and The Battle for Middle-earth II 1.06.",
		TYPE_BODY, C_TEXT_2))
	_col_main.add_child(header)

	# 2. the status card: what OpenBFME sees now and the one thing to do about it (_refresh_import, _on_install, _on_start)
	_card = _panel(C_CARD_LIVE, C_BORDER_LIVE, RADIUS, SPACE_S)
	var live := _vbox(SPACE_S)
	_card.add_child(live)
	if not problem.is_empty():
		live.add_child(_label(problem, TYPE_BODY, C_ERROR))
	var said := _vbox(SPACE_XS) # the line, the bar and the note read as one; the button stands apart
	live.add_child(said)
	_import_title = _label("", TYPE_HEADING, C_TEXT)
	said.add_child(_import_title)
	_import_bar = ProgressBar.new()
	_import_bar.max_value = 1.0
	_import_bar.step = 0.0
	_import_bar.show_percentage = false # the title says it
	_import_bar.custom_minimum_size.y = BAR_HEIGHT
	_import_bar.add_theme_stylebox_override("background", _box(C_TRACK, Color.TRANSPARENT, BAR_HEIGHT / 2, 0, 0))
	_import_bar.add_theme_stylebox_override("fill", _box(C_ACCENT, Color.TRANSPARENT, BAR_HEIGHT / 2, 0, 0))
	_import_bar.visible = false
	said.add_child(_import_bar)
	_import_note = _rich()
	said.add_child(_import_note)
	_import_button = _button("Install", "primary")
	_import_button.pressed.connect(_on_card_button)
	live.add_child(_import_button)
	_col_main.add_child(_card)

	# 3. the steps
	var device := _ios_device()
	var code := _panel(C_CODE, Color.TRANSPARENT, RADIUS_S, SPACE_S)
	var command := _rich(TYPE_CAPTION, C_TEXT)
	command.bbcode_enabled = false
	command.add_theme_font_override("normal_font", _mono())
	command.text = MAKE_COMMAND_SHOWN
	code.add_child(command)
	_copy = _button("Copy command", "secondary")
	_copy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_copy.pressed.connect(_copy_command)
	_steps.append(_step_card(1, "On your Mac", [
		_label("Make the game file from your two game folders:", TYPE_BODY, C_TEXT_2),
		code,
		_label("It writes OpenBFME-GameData.obfme (about 6.5 GB).", TYPE_CAPTION, C_TEXT_3),
		_copy]))
	_steps.append(_step_card(2, "Send it to this %s" % device, [
		_option("With a cable:", "Finder › your %s › Files › drag the file onto OpenBFME." % device),
		_option("Wirelessly:", "AirDrop it, then Save to Files › %s › OpenBFME." % _ios_place())]))
	_steps.append(_step_card(3, "Install", [
		_label("Come back here. OpenBFME finds the file; tap Install and keep it open for a few minutes.", TYPE_BODY, C_TEXT_2),
		_label("The game file is deleted afterwards, to give its space back.", TYPE_CAPTION, C_TEXT_3)]))
	for step in _steps:
		_col_main.add_child(step)

	# 4. the actions
	_actions = _vbox(SPACE_XS)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_S)
	var files := _button("Open in Files", "secondary")
	files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	files.pressed.connect(_open_files)
	row.add_child(files)
	_again = _button("Look again", "secondary")
	_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_again.pressed.connect(_look_again)
	row.add_child(_again)
	_actions.add_child(row)
	_files_hint = _label("Open the Files app and go to %s › OpenBFME." % _ios_place(), TYPE_CAPTION, C_TEXT_3)
	_files_hint.visible = false
	_actions.add_child(_files_hint)
	_col_main.add_child(_actions)

	# 5. the other ways: the two folders copied by hand (lane IOS-4), folded away
	var other := _vbox(SPACE_XS)
	var fold := _button("Other ways to add the game", "flat")
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold.pressed.connect(func(): _set_other_open(not _other_box.visible))
	_other_state = Label.new()
	_other_state.add_theme_font_size_override("font_size", TYPE_CAPTION)
	_other_state.add_theme_color_override("font_color", C_TEXT_3)
	_other_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_other_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_other_state.grow_horizontal = Control.GROW_DIRECTION_BEGIN # Show / Hide grow leftwards from the button's right padding
	fold.add_child(_other_state)
	_other_state.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE, Control.PRESET_MODE_MINSIZE, SPACE_S)
	other.add_child(fold)
	var folded := _panel(C_CARD, C_BORDER, RADIUS, SPACE_S)
	_other_box = _vbox(SPACE_S)
	folded.add_child(_other_box)
	other.add_child(folded)
	_other_box.add_child(_label("Copy the two game folders", TYPE_HEADING, C_HEADING))
	_other_box.add_child(_label(_ios_folder_steps(), TYPE_BODY, C_TEXT_2))
	for game in [["The Rise of the Witch-king 2.01", "rotwk", "RotWK"], ["The Battle for Middle-earth II 1.06", "bfme2", "BFME2"]]:
		var place := _vbox(0)
		place.add_child(_label(game[0], TYPE_BODY, C_TEXT))
		place.add_child(_label("%s › OpenBFME › %s" % [_ios_place(), game[2]], TYPE_CAPTION, C_TEXT_3))
		# lane IOS-4: each game has one place; the edit (hidden: the container path means nothing to the player) holds the folder found
		var held := LineEdit.new()
		held.visible = false
		held.text = _first_found(game[1])
		place.add_child(held)
		_other_box.add_child(place)
		if game[1] == "rotwk":
			_rotwk_edit = held
		else:
			_bfme2_edit = held
	_status = _rich()
	_other_box.add_child(_status)
	_start = _button("Use these folders", "secondary")
	_start.pressed.connect(_on_start)
	_other_box.add_child(_start)
	_col_main.add_child(other)

	# 6. the version
	# lane VERSION-1: "OpenBFME Alpha 0.4.5 (<date>)"; lane IOS-4: wrapped, a nightly's long version line must not widen the screen
	_col_main.add_child(_label(Release.display_line(), TYPE_CAPTION, C_TEXT_3))
	for col in [_col_main, _col_steps]:
		var pad := Control.new()
		col.add_child(pad)
		_end_pads.append(pad)

	_set_other_open(false)
	_recheck()
	_refresh_import()
	_fit_frame()
	get_viewport().size_changed.connect(_fit_frame)


# The status card's one line, its note (BBCode, from _bb) and its button ("" hides it).
func _show_card(title: String, note: String, button := "", enabled := true) -> void:
	_import_title.text = title
	_import_note.text = note
	_import_note.visible = not note.is_empty()
	_import_button.visible = not button.is_empty()
	_import_button.text = button
	_import_button.disabled = not enabled


# No game file in the app's folder: the folders are ready, partly there, or not there at all (the player is on the steps).
func _show_idle() -> void:
	if _checked_ok:
		_show_card("Your game files are in place", _bb("RotWK and BFME2 are in %s › OpenBFME. OpenBFME checks every file before it starts; "
			% _ios_place() + "the first time this can take a minute.", C_TEXT_3, TYPE_CAPTION), "Start")
	elif not (_rotwk_edit.text.is_empty() and _bfme2_edit.text.is_empty()):
		_show_card("Your game folders are not complete", _bb("Other ways to add the game, below, says what is missing.", C_WARN))
		_set_other_open(true)
	else:
		_show_card("Looking for your game file…", _bb("Follow the steps. OpenBFME looks again each time you come back to it.", C_TEXT_3,
			TYPE_CAPTION))


# The card's button: Install (a game file is offered) or Start (the folders checked out), as Use these folders does.
func _on_card_button() -> void:
	if _import != null:
		_on_install()
	elif _checked_ok:
		_on_start()


func _set_other_open(open: bool) -> void:
	_other_box.get_parent().visible = open
	_other_box.visible = open
	_other_state.text = "Hide" if open else "Show"


# The Files app at OpenBFME's folder: shareddocuments:// and the absolute path of the app's Documents (user://, OS_AppleEmbedded::
# get_user_data_dir), each part percent-encoded. Godot's shell_open asks canOpenURL first, which answers only for schemes the Info.plist
# lists under LSApplicationQueriesSchemes (tools/ios/patch_export.sh adds shareddocuments). Not opened: the card says where to go instead.
func _open_files() -> void:
	var parts := ProjectSettings.globalize_path("user://").split("/")
	for i in parts.size():
		parts[i] = parts[i].uri_encode()
	var url := "shareddocuments://" + "/".join(parts)
	var opened := OS.shell_open(url)
	print(Release.info.redact("FIRST RUN open in Files: %s: %s" % [url, error_string(opened)]))
	_files_hint.visible = opened != OK


# Step 1's command to the clipboard (with Universal Clipboard it pastes on the Mac); the button says so for a moment, at its own width.
func _copy_command() -> void:
	DisplayServer.clipboard_set(MAKE_COMMAND)
	_copy.custom_minimum_size.x = _copy.size.x
	_copy.text = "Copied"
	get_tree().create_timer(1.5).timeout.connect(_copy_reset)


func _copy_reset() -> void:
	if is_instance_valid(_copy):
		_copy.text = "Copy command"


# ---- lane IOS-12: building blocks (the tokens above, nothing else) ---------------------------------------------------------------------------

func _scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	parent.add_child(scroll)
	return scroll


func _column(scroll: ScrollContainer) -> VBoxContainer:
	var col := _vbox(SPACE_M)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	return col


func _vbox(gap: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	return box


# Every label wraps: nothing on this screen may push it wider than the display (the IOS-4 version-line bug).
func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _rich(font_size := TYPE_BODY, color := C_TEXT_2) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.selection_enabled = true
	rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rich.add_theme_font_size_override("normal_font_size", font_size)
	rich.add_theme_color_override("default_color", color)
	return rich


# Text for a RichTextLabel in a colour (and a size other than the body's); "[" is escaped, so a file name or error cannot add BBCode.
func _bb(text: String, color: Color, font_size := TYPE_BODY) -> String:
	var t := "[color=#%s]%s[/color]" % [color.to_html(), text.replace("[", "[lb]")]
	return t if font_size == TYPE_BODY else "[font_size=%d]%s[/font_size]" % [font_size, t]


# One way of step 2: its name in white, the way in the secondary colour.
func _option(name: String, how: String) -> RichTextLabel:
	var rich := _rich()
	rich.text = _bb(name, C_TEXT) + " " + _bb(how, C_TEXT_2)
	return rich


func _mono() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(MONO_FONTS)
	return font


func _box(fill: Color, edge: Color, radius: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(BORDER if edge.a > 0.0 else 0)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


func _panel(fill: Color, edge: Color, radius: int, pad: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(fill, edge, radius, pad, pad))
	return panel


# A step: its picture (res://assets/setup/step-N.png, at the card's width, when there is one), its number and heading, then its content.
func _step_card(n: int, heading: String, content: Array) -> PanelContainer:
	var card := _panel(C_CARD, C_BORDER, RADIUS, SPACE_S)
	var box := _vbox(SPACE_S)
	card.add_child(box)
	var art := ART_STEP % n
	if ResourceLoader.exists(art):
		var image := TextureRect.new()
		image.texture = load(art)
		image.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		box.add_child(image)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", SPACE_S)
	var badge := _panel(C_BADGE, Color.TRANSPARENT, BADGE / 2, 0) # a filled disc: a 1 px ring shows seams where StyleBoxFlat joins its corners
	(badge.get_theme_stylebox("panel") as StyleBoxFlat).corner_detail = BADGE # round, not faceted
	badge.custom_minimum_size = Vector2(BADGE, BADGE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var number := Label.new()
	number.text = str(n)
	number.add_theme_font_size_override("font_size", TYPE_BODY)
	number.add_theme_color_override("font_color", C_ACCENT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(number)
	title.add_child(badge)
	var label := _label(heading, TYPE_HEADING, C_HEADING)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.y = BADGE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_child(label)
	box.add_child(title)
	var body := _vbox(SPACE_XS)
	for c in content:
		body.add_child(c)
	box.add_child(body)
	return card


# primary: the gold button (the status card's action); secondary: outlined; flat: text only (the fold). Every state its own look: normal,
# hover, pressed, disabled, and a focus ring that Godot shows for the keyboard only (a tap hides it: Viewport gui.hide_focus).
func _button(text: String, kind: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = TOUCH_PRIMARY if kind == "primary" else TOUCH_MIN
	b.add_theme_font_size_override("font_size", TYPE_HEADING if kind == "primary" else TYPE_BODY)
	var none := Color.TRANSPARENT
	var fill: Array = [C_FILL, C_FILL_HOVER, C_FILL_PRESSED, none]        # normal, hover, pressed, disabled
	var ink: Array = [C_TEXT, C_TEXT, C_TEXT, C_TEXT_3]
	var edge: Array = [C_BUTTON_EDGE, C_BUTTON_EDGE, C_BUTTON_EDGE, C_BORDER]
	if kind == "primary":
		fill = [C_ACCENT, C_ACCENT_HOVER, C_ACCENT_PRESSED, C_ACCENT_DISABLED]
		ink = [C_ON_ACCENT, C_ON_ACCENT, C_ON_ACCENT, C_TEXT_3]
		edge = [none, none, none, none]
	elif kind == "flat":
		fill = [none, C_FILL, C_FILL_PRESSED, none]
		ink = [C_TEXT_2, C_TEXT, C_TEXT, C_TEXT_3]
		edge = [none, none, none, none]
	var states := ["normal", "hover", "pressed", "disabled"]
	for i in states.size():
		b.add_theme_stylebox_override(states[i], _box(fill[i], edge[i], RADIUS_S, SPACE_S, SPACE_XS))
	b.add_theme_stylebox_override("hover_pressed", _box(fill[2], edge[2], RADIUS_S, SPACE_S, SPACE_XS))
	var focus := _box(none, C_FOCUS, RADIUS_S + FOCUS_WIDTH, 0, 0)
	focus.draw_center = false
	focus.set_border_width_all(FOCUS_WIDTH)
	focus.set_expand_margin_all(FOCUS_WIDTH)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", ink[0])
	b.add_theme_color_override("font_hover_color", ink[1])
	b.add_theme_color_override("font_focus_color", ink[0])
	b.add_theme_color_override("font_pressed_color", ink[2])
	b.add_theme_color_override("font_hover_pressed_color", ink[2])
	b.add_theme_color_override("font_disabled_color", ink[3])
	return b


# ---- lane IOS-9: the one-file install -----------------------------------------------------------------------------------------------------

# Looks for a game file and says what installing it needs, on the status card (IOS-12). Nothing is installed until the player taps Install.
func _refresh_import() -> void:
	if _importing or _card == null:
		return
	_import = null
	_import_bar.visible = false
	var found := GameFileImport.find()
	var pending := GameFileImport.pending()
	if found.is_empty():
		if pending:
			# the folders hold part of an install: say so instead of letting their check read as a broken copy
			_show_card("The install from the game file did not finish",
				_bb("Copy OpenBFME-GameData.obfme into OpenBFME again (step 2) and tap Install: it carries on where it stopped.", C_WARN))
		else:
			_show_idle()
		return
	var imp := GameFileImport.new()
	var shown_name := found[0].get_file()
	var others := "" if found.size() == 1 else "\n" + _bb("%d other .obfme files in OpenBFME's folder are not used; delete them in the Files app." % (
		found.size() - 1), C_TEXT_3, TYPE_CAPTION)
	if not imp.open(found[0]):
		print("FIRST RUN game file: ", imp.error)
		_show_card("This game file cannot be used", _bb(imp.error, C_ERROR) + others)
		return
	print("FIRST RUN game file: %s, %d files, %d bytes (%d still to install)" % [found[0].get_file(), imp.files.size(), imp.total, imp.remaining])
	if _checked_ok and not pending:
		_show_card("Your game files are in place", _bb("%s is not needed. Delete it in the Files app to get its %s back." % [
			shown_name, GameFileImport.gb(imp.archive_size)], C_TEXT_3, TYPE_CAPTION) + others, "Start")
		return
	_import = imp
	# no-break spaces and a word joiner after each hyphen: a wrap never splits the file name or leaves "GB" (or "· 6.5 GB") alone on a line
	var title := "Found %s\u00a0·\u00a0%s" % [shown_name.replace("-", "-\u2060"), GameFileImport.gb(imp.archive_size).replace(" ", "\u00a0")]
	var button := "Continue installing" if imp.resuming else "Install"
	var free: int = imp.space_left()
	var need: int = imp.space_needed()
	if free > 0 and free < need:
		_show_card(title, _bb("Not enough space: installing needs %s free and this %s has %s. Free some space (Settings › General › %s Storage), then come back here." % [
			GameFileImport.gb(need), _ios_device(), GameFileImport.gb(free), _ios_device()], C_ERROR) + others, button, false)
		return
	var space := ("%s free, %s needed" % [GameFileImport.gb(free), GameFileImport.gb(need)]) if free > 0 else (
		"needs %s free (OpenBFME could not read how much is free)" % GameFileImport.gb(need))
	_show_card(title, _bb("%s. Takes a few minutes: keep OpenBFME open. The game file is deleted when the game files are in place." % space,
		C_TEXT_3, TYPE_CAPTION) + others, button)


func _on_install() -> void:
	if _import == null or _importing or _mounting:
		return
	_importing = true
	_again.disabled = true
	_start.disabled = true
	_import_bar.visible = true
	_import_bar.value = 0.0
	_show_card("Installing… 0 %", _bb("Keep OpenBFME open.", C_TEXT_3, TYPE_CAPTION)) # the button goes while it runs
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
		_show_card("Installing stopped", _bb(_import.error, C_ERROR), "Try again")
		_recheck()
		return
	print("FIRST RUN game file installed: %d files" % _import.files.size())
	_import = null
	_look_again()
	if _checked_ok:
		_on_start() # straight on to the full check and the game, as Use these folders would


func _on_import_progress(done_bytes: int, total_bytes: int, file_index: int, file_count: int, _file_path: String) -> void:
	var done := float(done_bytes) / maxf(1.0, float(total_bytes))
	_import_bar.value = done
	_import_title.text = "Installing… %d %% · file %d of %d" % [int(done * 100.0), file_index, file_count]
	_import_note.text = _bb("Keep OpenBFME open · %s of %s" % [GameFileImport.gb(done_bytes), GameFileImport.gb(total_bytes)], C_TEXT_3,
		TYPE_CAPTION)


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
	var margin := {}
	for side in insets:
		margin[side] = int(SPACE_M + maxf(0.0, insets[side]) / s)
		_margin.add_theme_constant_override("margin_" + side, margin[side])
	# lane IOS-12: the columns scroll to the screen's bottom edge, as iOS lists do; the bottom margin is inside them (the column's last gap,
	# SPACE_M, plus the home indicator's inset), so nothing is cut off by a hard line above the edge
	_margin.add_theme_constant_override("margin_bottom", 0)
	for pad in _end_pads:
		pad.custom_minimum_size.y = margin.bottom - SPACE_M
	_lay_out(_frame.size.x, _frame.size.x - margin.left - margin.right)


# lane IOS-12: one column up to WIDE_FROM points, else two (header and status card | the steps); each column at most CONTENT_MAX, centred.
func _lay_out(frame_width: float, room: float) -> void:
	var wide := frame_width > WIDE_FROM
	var width := minf((room - SPACE_L) / 2.0 if wide else room, CONTENT_MAX)
	_scroll_main.custom_minimum_size.x = width
	_scroll_steps.custom_minimum_size.x = width
	_scroll_steps.visible = wide
	if wide == _wide:
		return
	_wide = wide
	for i in _steps.size():
		var step := _steps[i]
		var column := _col_steps if wide else _col_main
		if step.get_parent() != column: # reparent() to the same parent does nothing
			step.reparent(column, false)
		if not wide:
			_col_main.move_child(step, _card.get_index() + 1 + i) # in order, right under the status card
	_col_steps.move_child(_end_pads[1], -1) # the steps went in after it
