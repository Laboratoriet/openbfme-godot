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
##
## Lane IOS-24 (a draft for the owner's review): the iOS screen as an overview. The status card on top says what OpenBFME sees and offers ONE
## action for it (Open in Files when there is no file yet, Install, Try again, Play); Look again sits under it as a link. The three steps are
## one card of short rows (1 prepare on the computer: the desktop game's Options > iPhone / iPad > Prepare, game_file_pack.gd; 2 send;
## 3 install), the steps behind the player ticked and the one at hand in gold. Each step's (i) opens a sheet with the detail: the ways to
## send the file, the command-line packer, the troubleshooting; "Other ways to add the game" (the two folders) is a sheet too. Dev switches
## for the screenshots: --first-run-state=<state> and --first-run-sheet=<n> (with --first-run-ios on a desktop, _preview).
## Godot 4.7.2's iOS display server has no native file dialog (drivers/apple_embedded/display_server_apple_embedded.mm has_feature:
## FEATURE_NATIVE_DIALOG_FILE commented out, file_dialog_show not implemented) and its own FileDialog sees only the app's folder.
##
## Lane IOS-36 ("Choose game file…", after daisyhasacat/openbfme-godot's folder picker, GodotIOSAssets.mm, GPL-3.0): the extension's
## IOSDocumentPicker (engine IOSDocumentPickerBridge.mm, iOS builds only) opens Files' document picker in place (UIDocumentPickerViewController,
## asCopy NO). The player picks OpenBFME-GameData.obfme wherever it is (iCloud Drive, Downloads, a drive); its security scope stays open while
## game_file_import.gd streams from its path (no 6.5 GB copy into the app first), and the file is kept there afterwards (keep_file). A file that
## is not on the device yet (iCloud) is brought down first by a coordinated read: the card says "Downloading from iCloud Drive…" meanwhile. A
## bookmark (PICK_BOOKMARK) gives the same file back on a later launch, so an install the system stopped carries on without picking again; it is
## dropped once the install is done or the game is ready.
## Layout (the owner's IOS-24 design kept; this choice documented in COMBINE / REPORT): "Choose game file…" is the status card's ONE action in
## the "no game file yet" state, as the card's rule asks, and Open in Files steps down to a text link beside Look again (both flat, one row). The
## steps card is unchanged. Without the class (the desktop, an extension built before IOS-36) the card is as before: Open in Files is its action.
## Dev preview on a desktop: --first-run-ios --first-run-picker shows the picker's states (--first-run-state=none | picking | downloading |
## picked | pickerror).
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
const C_FILL_STRONG := Color(1, 1, 1, 0.22)          # lane IOS-24: an (i) pressed (its resting fill is C_FILL_HOVER)
const C_BUTTON_EDGE := Color(1, 1, 1, 0.24)          # a secondary button's 1 px edge
const C_FOCUS := Color(1, 1, 1, 0.85)                # the keyboard focus ring (an iPad with a keyboard)
const C_OK := Color("88ff88")                        # the check's colours (_recheck's #8f8 / #fd8 / #f98)
const C_WARN := Color("ffdd88")
const C_ERROR := Color("ff9988")
const C_TRACK := Color(1, 1, 1, 0.10)                # the progress bar's empty part
const C_BADGE := Color(0.784, 0.635, 0.353, 0.16)    # a step number's disc: the accent at 16 %
const C_SHEET := Color(0.11, 0.11, 0.12)             # lane IOS-24: a sheet, one step lighter than a card (it sits above the screen)
const C_SCRIM := Color(0, 0, 0, 0.6)                 # what is under an open sheet
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
# motion (seconds): a sheet comes in eased out and goes eased in (Tween cubic); none with Reduce Motion
const MOTION_IN := 0.22
const MOTION_OUT := 0.16
const SHEET_RISE := 16           # points a sheet rises into place
# the art (res://assets/setup/README.md): each is shown only when it is there
const ART_LOGO := "res://assets/setup/logo.png"
const ART_STEP := "res://assets/setup/step-%d.png"
const MAKE_COMMAND := "python3 tools/ios/make_game_file.py --rotwk <RotWK folder> --bfme2 <BFME2 folder>"
# shown one flag a line (a wrap must never split "--bfme2"), still a valid shell command when selected and pasted; Copy copies MAKE_COMMAND
const MAKE_COMMAND_SHOWN := "python3 tools/ios/make_game_file.py \\\n  --rotwk <RotWK folder> \\\n  --bfme2 <BFME2 folder>"

# lane IOS-36: the picker (the extension's class, iOS builds only) and where the picked game file's bookmark is kept (a dotfile: Files hides it)
const PICKER_CLASS := "IOSDocumentPicker"
const PICK_BOOKMARK := "user://.openbfme-picked-game-file.bookmark"

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
var _import_button: Button     # the card's one action (_card_action says which)
var _again: Button             # Look again, under the card's action
var _card_action := ""         # lane IOS-24: files / install / play / other / look
var _install_started := 0      # Time.get_ticks_msec() when Install was tapped (the time left)
# lane IOS-12 / IOS-24: the welcome screen's layout
var _wide = null               # two columns (null: not laid out yet)
var _scroll_main: ScrollContainer
var _scroll_steps: ScrollContainer
var _col_main: VBoxContainer   # header, status card, (steps and footer when narrow)
var _col_steps: VBoxContainer  # the steps and the footer when wide
var _steps_card: PanelContainer  # the three steps
var _step_parts: Array = []      # per step: {badge, number, heading, row}
var _footer: Control             # Other ways + the version
var _files_hint: Label         # said when the Files app could not be opened
var _other_box: VBoxContainer  # the two-folder way (sheet 4)
var _copy: Button
var _end_pads: Array[Control] = [] # each column's last child: the bottom safe area, inside the scroll (it scrolls to the screen's edge)
# lane IOS-24: the sheets
var _sheet_layer: Control
var _sheet_center: CenterContainer
var _sheets: Array[PanelContainer] = []  # 1 prepare, 2 send, 3 install, 4 other ways
var _open_n := 0               # the sheet shown (0: none)
var _opener: Control           # the button that opened it (the focus goes back to it)
var _opener_keyboard := false  # it was opened from the keyboard (the focus ring stays visible)
var _tween: Tween
var _previewing := false       # a dev preview state is shown (--first-run-state): coming back to the window must not replace it
# lane IOS-36: Files' document picker
var _files_link: Button        # Open in Files as a link beside Look again (the picker is the card's action then)
var _watching_pick := false    # a pick (or a restored bookmark) is under way: _process reads its status
var _pick_state := ""          # the status state last shown
var _picked := {}              # the picked game file once it can be read: IOSDocumentPicker's status (path, name, place, size, ...)
var _again_picks := false      # the link under the action is "Choose another file" (a picked file is offered), not Look again

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
	# lane IOS-24, dev only (with --first-run-ios on a desktop): --first-run-state=<looking|none|none-again|found|nospace|installing|checking|
	# error|badfile|ready> shows that state of the card, --first-run-sheet=<1..4> opens that sheet (the screenshots of every state)
	if _ios and not OS.has_feature("ios") and _card != null:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--first-run-state="):
				_preview(arg.trim_prefix("--first-run-state="))
			elif arg.begins_with("--first-run-sheet="):
				await get_tree().process_frame
				_open_sheet(int(arg.trim_prefix("--first-run-sheet=")), _import_button)
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
		# lane IOS-12: said on the status card, where the player is looking (the folders' own status is in a sheet)
		_card_checking()
	await get_tree().process_frame
	await get_tree().process_frame
	var mount := _mount_and_remember(_rotwk_edit.text, _bfme2_edit.text)
	_mounting = false
	if mount.ok:
		if _ios:
			_card_ready("Starting OpenBFME…")
			_import_button.disabled = true
		finished.emit(mount)
		return
	var t := "[color=#f98]The folders could not be used:[/color]\n"
	for e in mount.errors:
		t += "[color=#f98]%s[/color]\n" % e
	_status.text = t
	_start.disabled = false
	if _ios:
		_card_error("The game files could not be used", "\n".join(mount.errors), "Try again", "play")


# ---- lane IOS-4: iPhone / iPad -------------------------------------------------------------------------------------------------------------

func _notification(what: int) -> void:
	# back from the Files app or Finder (iOS sends this when the app becomes active again): look again by itself
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _ios and _status != null and not _previewing:
		_look_again()


# `tapped`: the player asked (Look again): when nothing new turns up, the card says when it looked
func _look_again(tapped := false) -> void:
	if _mounting or _importing:
		return
	if _card != null:
		_card_looking() # drawn for a frame: the tap is seen to do something even when nothing new turns up
		await get_tree().process_frame
	_found = _setup.discover()
	print("FIRST RUN looking again: %d folders found" % _found.size())
	for c in _found:
		print(Release.info.redact("FIRST RUN found %s: %s (%s) %s" % [c.game, c.path, c.source, "ok" if c.ok else "rejected: " + "; ".join(c.errors)]))
	_rotwk_edit.text = _first_found("rotwk")
	_bfme2_edit.text = _first_found("bfme2")
	_recheck()
	var t := Time.get_time_dict_from_system()
	_refresh_import("%02d:%02d" % [t.hour, t.minute] if tapped else "")


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


# ---- lane IOS-12 / IOS-24: the welcome screen ------------------------------------------------------------------------------------------------

# Header, the status card (the one action), the three steps as one overview, "Other ways" and the version. The detail lives in sheets
# (_sheet_*), opened by each step's (i) button. _fit_frame lays it out in one column or two.
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
	# each column scrolls on its own (two columns: the status card stays in view while the steps scroll); the bars are hidden as iOS hides
	# them, so a column is exactly its width
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

	# 2. the status card: what OpenBFME sees now and the one thing to do about it (_card_* below)
	_card = _panel(C_CARD_LIVE, C_BORDER_LIVE, RADIUS, SPACE_S)
	var live := _vbox(SPACE_S)
	_card.add_child(live)
	if not problem.is_empty():
		live.add_child(_label(problem, TYPE_BODY, C_ERROR))
	var said := _vbox(SPACE_XS) # the line, the bar and the note read as one; the buttons stand apart
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
	var actions := _vbox(SPACE_XS)
	_import_button = _button("Install", "primary")
	_import_button.pressed.connect(_on_card_button)
	actions.add_child(_import_button)
	# the links under the action, one row: Open in Files (lane IOS-36: only while the picker is the action) and Look again, sharing the width
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", SPACE_XS)
	_files_link = _button("Open in Files", "flat")
	_files_link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_files_link.pressed.connect(_open_files)
	_files_link.visible = false
	links.add_child(_files_link)
	_again = _button("Look again", "flat")
	_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_again.pressed.connect(_on_again)
	links.add_child(_again)
	actions.add_child(links)
	live.add_child(actions)
	_files_hint = _label("Open the Files app and go to %s › OpenBFME." % _ios_place(), TYPE_CAPTION, C_TEXT_3)
	_files_hint.visible = false
	live.add_child(_files_hint)
	_col_main.add_child(_card)

	# 3. the steps: one overview card, a row each; the (i) opens the step's sheet
	var device := _ios_device()
	_steps_card = _panel(C_CARD, C_BORDER, RADIUS, SPACE_S)
	var rows := _vbox(SPACE_S)
	_steps_card.add_child(rows)
	rows.add_child(_label("Three steps", TYPE_CAPTION, C_TEXT_3))
	var titles := ["Prepare on your computer", "Send it to this %s" % device, "Install"]
	var lines := ["In OpenBFME on your Mac or PC: Options › iPhone / iPad › Prepare.", "With a cable, AirDrop or iCloud Drive.",
		"Tap Install here. It takes a few minutes."]
	for i in 3:
		rows.add_child(_step_row(i + 1, titles[i], lines[i]))
	_col_main.add_child(_steps_card)

	# 4. the other ways (a sheet too) and the version
	var footer := _vbox(SPACE_XS)
	var other := _button("Other ways to add the game", "flat")
	other.alignment = HORIZONTAL_ALIGNMENT_LEFT
	other.pressed.connect(_open_sheet.bind(4, other))
	footer.add_child(other)
	# lane VERSION-1: "OpenBFME Alpha 0.4.5 (<date>)"; lane IOS-4: wrapped, a nightly's long version line must not widen the screen. Indented
	# as the flat button's text above it, so the two read as one left edge
	var version := MarginContainer.new()
	version.add_theme_constant_override("margin_left", SPACE_S)
	version.add_child(_label(Release.display_line(), TYPE_CAPTION, C_TEXT_3))
	footer.add_child(version)
	_footer = footer
	_col_main.add_child(footer)
	for col in [_col_main, _col_steps]:
		var pad := Control.new()
		col.add_child(pad)
		_end_pads.append(pad)

	# 5. the sheets, over everything; built once (the two-folder way's controls live in sheet 4 and are used while it is closed)
	_build_sheets(device)
	_recheck()
	_restore_pick()
	_refresh_import()
	_fit_frame()
	get_viewport().size_changed.connect(_fit_frame)


# A step of the overview: its badge (the number, or a tick once it is done), title, one line, and the (i) for its sheet.
func _step_row(n: int, title: String, line: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_S)
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
	row.add_child(badge)
	var text := _vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := _label(title, TYPE_BODY, C_TEXT)
	text.add_child(heading)
	text.add_child(_label(line, TYPE_CAPTION, C_TEXT_2))
	row.add_child(text)
	var info := _info_button("More about: " + title)
	info.pressed.connect(_open_sheet.bind(n, info))
	row.add_child(info)
	_step_parts.append({"badge": badge, "number": number, "heading": heading, "row": row})
	return row


# The steps that are behind the player get a tick, the one at hand the accent; the rest stay as they are. `at`: 1..3, 4 = all done.
func _set_step(at: int) -> void:
	for i in _step_parts.size():
		var p: Dictionary = _step_parts[i]
		var n := i + 1
		var done := n < at
		(p.number as Label).text = "✓" if done else str(n)
		(p.heading as Label).add_theme_color_override("font_color", C_ACCENT if n == at else (C_TEXT_2 if done else C_TEXT))


# ---- the status card's states (each says what is going on and offers the one thing to do) ------------------------------------------------

# The card's line, its note (BBCode, from _bb) and its action: "" hides the button. `look`: the Look again link under it.
func _show_card(title: String, note: String, button := "", action := "", enabled := true, look := false) -> void:
	_import_title.text = title
	_import_note.text = note
	_import_note.visible = not note.is_empty()
	_import_button.visible = not button.is_empty()
	_import_button.text = button
	_import_button.disabled = not enabled
	_card_action = action
	_again.visible = look
	_again.text = "Look again"
	_again_picks = false
	_files_link.visible = false # lane IOS-36: _card_none shows it
	_files_hint.visible = false


func _card_looking() -> void:
	_import_bar.visible = false
	_show_card("Looking for your game file…", _bb("In %s › OpenBFME." % _ios_place(), C_TEXT_3, TYPE_CAPTION))
	_set_step(1)


# Nothing in the app's folder yet: the player is somewhere in steps 1 and 2. `looked`: when Look again found nothing ("" at the start).
func _card_none(looked := "") -> void:
	_import_bar.visible = false
	var note := "Send OpenBFME-GameData.obfme to %s › OpenBFME (the three steps). OpenBFME looks again whenever you come back to it." % _ios_place()
	if not looked.is_empty():
		note = "Still nothing in %s › OpenBFME (looked at %s). If the file is in iCloud Drive or Downloads, move it there in Files." % [_ios_place(), looked]
	if _can_pick():
		# lane IOS-36: the picker is the action; Open in Files becomes the link beside Look again
		note = "Choose OpenBFME-GameData.obfme where it is: iCloud Drive, Downloads or a drive. OpenBFME installs it from there, no copy needed."
		if not looked.is_empty():
			note = "Still nothing in %s › OpenBFME (looked at %s). Choose the file where it is instead." % [_ios_place(), looked]
		_show_card("No game file yet", _bb(note, C_TEXT_3, TYPE_CAPTION), "Choose game file…", "pick", true, true)
		_files_link.visible = true
	else:
		_show_card("No game file yet", _bb(note, C_TEXT_3, TYPE_CAPTION), "Open in Files", "files", true, true)
	_set_step(1)


# `kept_in`: lane IOS-36, the file was picked where it is (its place in Files' words): read from there and kept, not deleted afterwards
func _card_found(name: String, archive: int, free: int, need: int, resuming: bool, others: String, kept_in := "") -> void:
	_import_bar.visible = false
	# no-break spaces and a word joiner after each hyphen: a wrap never splits the file name or leaves "GB" (or "· 6.5 GB") alone on a line
	var title := "Found %s · %s" % [name.replace("-", "-⁠"), GameFileImport.gb(archive).replace(" ", " ")]
	var button := "Continue installing" if resuming else "Install"
	_set_step(3)
	if free > 0 and free < need:
		_show_card(title, _bb("Not enough space: installing needs %s free and this %s has %s. Free some space (Settings › General › %s Storage), then come back here." % [
			GameFileImport.gb(need), _ios_device(), GameFileImport.gb(free), _ios_device()], C_ERROR) + others, button, "install", false, true)
	else:
		var space := ("%s free, %s needed" % [GameFileImport.gb(free), GameFileImport.gb(need)]) if free > 0 else (
			"needs %s free (OpenBFME could not read how much is free)" % GameFileImport.gb(need))
		var after := "the file is deleted afterwards" if kept_in.is_empty() else "read from %s, where it stays" % kept_in
		_show_card(title, _bb("%s · takes a few minutes · %s" % [space, after], C_TEXT_3, TYPE_CAPTION) + others, button, "install")
	if not kept_in.is_empty():
		_again_picks = true # lane IOS-36: the link picks again (Look again would only find the same picked file)
		_again.text = "Choose another file"
		_again.visible = true


func _card_installing(done_bytes: int, total_bytes: int, file_index: int, file_count: int, seconds_left: int) -> void:
	var done := float(done_bytes) / maxf(1.0, float(total_bytes))
	_import_bar.visible = true
	_import_bar.indeterminate = false # lane IOS-36: the iCloud download's bar has no measure
	_import_bar.value = done
	var left := "working out the time" if seconds_left < 0 else ("less than a minute left" if seconds_left < 60 else "about %d min left" % ceili(seconds_left / 60.0))
	_show_card("Installing… %d %%" % int(done * 100.0), _bb("%s of %s · file %d of %d · %s. Keep OpenBFME open." % [
		GameFileImport.gb(done_bytes), GameFileImport.gb(total_bytes), file_index, file_count, left], C_TEXT_3, TYPE_CAPTION))
	_set_step(3)


func _card_checking() -> void:
	_import_bar.visible = false
	_show_card("Checking every game file…", _bb("The first time this takes about a minute. Keep OpenBFME open.", C_TEXT_3, TYPE_CAPTION))
	_set_step(3)


func _card_error(title: String, why: String, button: String, action: String) -> void:
	_import_bar.visible = false
	_show_card(title, _bb(why, C_ERROR), button, action, true, action != "look")
	_set_step(3)


func _card_ready(note := "") -> void:
	_import_bar.visible = false
	if note.is_empty():
		note = "RotWK and BFME2 are in %s › OpenBFME. OpenBFME checks every file before it starts; the first time this takes about a minute." % _ios_place()
	_show_card("Ready to play", _bb(note, C_TEXT_3, TYPE_CAPTION), "Play", "play")
	_set_step(4)


# No game file in the app's folder: the folders are ready, partly there, or not there at all (the player is on the steps).
func _show_idle(looked := "") -> void:
	if _checked_ok:
		_card_ready()
	elif not (_rotwk_edit.text.is_empty() and _bfme2_edit.text.is_empty()):
		_card_error("Your game folders are not complete", "Other ways to add the game, below, says what is missing.", "Show what is missing", "other")
	else:
		_card_none(looked)


# The card's one action
func _on_card_button() -> void:
	match _card_action:
		"install":
			_on_install()
		"play":
			_on_start()
		"files":
			_open_files()
		"pick":
			_pick_file()
		"other":
			_open_sheet(4, _import_button)
		"look":
			_look_again(true)


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


# The command-line packer's command to the clipboard (with Universal Clipboard it pastes on the Mac); the button says so for a moment.
func _copy_command() -> void:
	DisplayServer.clipboard_set(MAKE_COMMAND)
	_copy.custom_minimum_size.x = _copy.size.x
	_copy.text = "Copied"
	get_tree().create_timer(1.5).timeout.connect(_copy_reset)


func _copy_reset() -> void:
	if is_instance_valid(_copy):
		_copy.text = "Copy command"


# ---- lane IOS-36: Files' document picker ("Choose game file…") ------------------------------------------------------------------------------

# The extension's picker is there (iOS builds from IOS-36 on), or a desktop preview asks for its states (--first-run-picker)
func _can_pick() -> bool:
	return ClassDB.class_exists(PICKER_CLASS) or (_previewing and OS.get_cmdline_user_args().has("--first-run-picker"))


func _picker(method: String, args: Array = []) -> Variant:
	# the class exists on iOS only, so it is called by name (ClassDB.class_call_static takes its arguments as varargs)
	return Callable(ClassDB, "class_call_static").callv([PICKER_CLASS, method] + args) if ClassDB.class_exists(PICKER_CLASS) else null


func _on_again() -> void:
	if _again_picks:
		_pick_file()
	else:
		_look_again(true)


# Files' picker over the app, for one .obfme file anywhere; the result comes in through _process. The bookmark keeps the pick for a later launch
func _pick_file() -> void:
	if not ClassDB.class_exists(PICKER_CLASS) or _importing or _mounting:
		return
	if not bool(_picker("pick", ["file", GameFileImport.EXTENSION, ProjectSettings.globalize_path(PICK_BOOKMARK)])):
		return # a picker is open already
	print("FIRST RUN picker: opened")
	_pick_state = "waiting"
	_watching_pick = true


func _process(_delta: float) -> void:
	if not _watching_pick:
		return
	var s = _picker("status")
	if not (s is Dictionary) or str(s.state) == _pick_state:
		return
	_pick_state = str(s.state)
	_on_pick_status(s)


func _on_pick_status(s: Dictionary) -> void:
	print(Release.info.redact("FIRST RUN picker: %s %s %s %s" % [s.state, s.name, s.place, s.error]))
	match str(s.state):
		"waiting":
			pass # the picker is over the screen
		"opening":
			_card_picking(str(s.name), str(s.place))
		"downloading":
			_card_downloading(str(s.name), str(s.place))
		"cancelled":
			_watching_pick = false
			_refresh_import()
		"error":
			_watching_pick = false
			_forget_pick(str(s.path))
			_card_pick_error(str(s.name), str(s.error))
		"picked":
			_watching_pick = false
			if str(s.name).get_extension().to_lower() != GameFileImport.EXTENSION:
				_forget_pick(str(s.path))
				_card_pick_error(str(s.name), "%s is not an OpenBFME game file. Choose OpenBFME-GameData.obfme (Prepare makes it on your computer)." % s.name)
				return
			if not _picked.is_empty() and _picked.path != s.path:
				_picker("release", [str(_picked.path), ""]) # the file picked before is no longer read (its bookmark was replaced)
			_picked = s
			_refresh_import()


# A file picked on an earlier launch (an install the system stopped, or one not started): its access back from the bookmark
func _restore_pick() -> void:
	if not ClassDB.class_exists(PICKER_CLASS) or not FileAccess.file_exists(PICK_BOOKMARK):
		return
	var r: Dictionary = _picker("restore", [ProjectSettings.globalize_path(PICK_BOOKMARK)])
	print(Release.info.redact("FIRST RUN picker: restored %s %s %s" % [r.ok, r.path, r.error]))
	if not r.ok:
		_forget_pick("")
		return
	_pick_state = ""
	_watching_pick = true
	_on_pick_status(r)
	_pick_state = str(r.state)


# The picked file is no longer used: its access stops and its bookmark goes
func _forget_pick(path: String) -> void:
	_picker("release", [path, ProjectSettings.globalize_path(PICK_BOOKMARK)])
	if path.is_empty() or (not _picked.is_empty() and _picked.path == path):
		_picked = {}


func _card_picking(name: String, place: String) -> void:
	_import_bar.visible = false
	_show_card("Opening %s…" % name.replace("-", "-⁠"), _bb("In %s." % place, C_TEXT_3, TYPE_CAPTION))
	_set_step(3)


# iCloud Drive brings the file down before it can be read (the coordinated read in IOSDocumentPickerBridge.mm); no percentage: the provider
# does not give one to an app outside its container
func _card_downloading(name: String, place: String) -> void:
	_import_bar.visible = true
	_import_bar.indeterminate = true
	_show_card("Downloading from %s…" % place, _bb("%s is not on this %s yet. %s is bringing it down (about 6.5 GB); installing can start once it is here. Keep OpenBFME open." % [
		name.replace("-", "-⁠"), _ios_device(), place], C_TEXT_3, TYPE_CAPTION))
	_set_step(2)


func _card_pick_error(name: String, why: String) -> void:
	_import_bar.visible = false
	var title := "This file cannot be opened" if name.is_empty() else "%s cannot be opened" % name.replace("-", "-⁠")
	_show_card(title, _bb(why + " Choose it again, or send it to %s › OpenBFME." % _ios_place(), C_ERROR), "Choose game file…", "pick", true, true)
	_files_link.visible = true
	_set_step(2)


# ---- lane IOS-24: the sheets (each step's detail, and the other ways) -----------------------------------------------------------------------

# A dimmed screen and a card over it. Closed by its Close button, a tap on the dimmed part, Esc / the controller's back (ui_cancel). It
# takes the focus when it opens and gives it back to the button that opened it.
func _build_sheets(device: String) -> void:
	_sheet_layer = Control.new()
	_sheet_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_layer.visible = false
	_frame.add_child(_sheet_layer)
	var scrim := ColorRect.new()
	scrim.color = C_SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.is_pressed():
			_close_sheet())
	_sheet_layer.add_child(scrim)
	_sheet_center = CenterContainer.new()
	_sheet_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_layer.add_child(_sheet_center)
	var place := _ios_place()

	# 1. prepare
	var code := _panel(C_CODE, Color.TRANSPARENT, RADIUS_S, SPACE_S)
	var command := _rich(TYPE_CAPTION, C_TEXT)
	command.bbcode_enabled = false
	command.add_theme_font_override("normal_font", _mono())
	command.text = MAKE_COMMAND_SHOWN
	code.add_child(command)
	_copy = _button("Copy command", "secondary")
	_copy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_copy.pressed.connect(_copy_command)
	_sheets.append(_sheet("Prepare on your computer", [
		_label("OpenBFME on your Mac or PC makes the file from the game folders it already plays on:", TYPE_BODY, C_TEXT_2),
		_option("1.", "Open OpenBFME, then Options › iPhone / iPad."),
		_option("2.", "Choose Prepare. It writes OpenBFME-GameData.obfme (about 6.5 GB) to your Desktop in a few minutes."),
		_label("Your game folders are only read, never changed.", TYPE_CAPTION, C_TEXT_3),
		_label("Without OpenBFME on the computer", TYPE_HEADING, C_HEADING),
		_label("On a Mac with OpenBFME's source, its packer makes the same file:", TYPE_BODY, C_TEXT_2),
		code, _copy]))
	# 2. send
	var files := _button("Open in Files", "secondary")
	files.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	files.pressed.connect(_open_files)
	_sheets.append(_sheet("Send it to this %s" % device, [
		_label("OpenBFME reads only its own folder, %s › OpenBFME. The file has to end up there:" % place, TYPE_BODY, C_TEXT_2),
		_option("With a cable:", "connect this %s to the computer. In Finder (on Windows: the Apple Devices app) select it, open Files and drag the file onto OpenBFME." % device),
		_option("AirDrop:", "share the file from the Mac, then choose Save to Files › %s › OpenBFME." % place),
		_option("iCloud Drive:", "put the file in iCloud Drive. Here, in the Files app, move it from iCloud Drive to %s › OpenBFME." % place),
		_label("Coming back to OpenBFME looks for it again.", TYPE_CAPTION, C_TEXT_3),
		files]))
	# 3. install
	_sheets.append(_sheet("Install", [
		_label("Tap Install. OpenBFME unpacks the file into its folder and checks every file against the list inside it.", TYPE_BODY, C_TEXT_2),
		_option("Space:", "about 9 GB free while it installs. The game file is deleted afterwards; the game then takes 8.5 GB."),
		_option("Time:", "a few minutes. Keep OpenBFME open: the screen stays on while it works."),
		_option("Stopped?", "tap Install again: it carries on where it stopped."),
		_label("If something goes wrong", TYPE_HEADING, C_HEADING),
		_option("Not found:", "the file must be in %s › OpenBFME, not in iCloud Drive or Downloads." % place),
		_option("Damaged or cut short:", "the copy did not finish. Send it again, or prepare it again on the computer."),
		_option("Made by another version:", "prepare it again with this version of OpenBFME.")]))
	# 4. the other ways: the two folders copied by hand (lane IOS-4)
	_other_box = _vbox(SPACE_S)
	_other_box.add_child(_label(_ios_folder_steps(), TYPE_BODY, C_TEXT_2))
	for game in [["The Rise of the Witch-king 2.01", "rotwk", "RotWK"], ["The Battle for Middle-earth II 1.06", "bfme2", "BFME2"]]:
		var where := _vbox(0)
		where.add_child(_label(game[0], TYPE_BODY, C_TEXT))
		where.add_child(_label("%s › OpenBFME › %s" % [place, game[2]], TYPE_CAPTION, C_TEXT_3))
		# lane IOS-4: each game has one place; the edit (hidden: the container path means nothing to the player) holds the folder found
		var held := LineEdit.new()
		held.visible = false
		held.text = _first_found(game[1])
		where.add_child(held)
		_other_box.add_child(where)
		if game[1] == "rotwk":
			_rotwk_edit = held
		else:
			_bfme2_edit = held
	_status = _rich()
	_other_box.add_child(_status)
	_start = _button("Use these folders", "secondary")
	_start.pressed.connect(func(): _close_sheet(); _on_start())
	_other_box.add_child(_start)
	_sheets.append(_sheet("Other ways to add the game", [_other_box]))


# One sheet: its title and Close on top, its content scrolling under them.
func _sheet(title: String, content: Array) -> PanelContainer:
	var sheet := _panel(C_SHEET, C_BORDER, RADIUS, 0)
	sheet.visible = false
	var box := _vbox(0)
	sheet.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", SPACE_S)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right"]:
		pad.add_theme_constant_override("margin_" + side, SPACE_S)
	pad.add_theme_constant_override("margin_bottom", SPACE_XS)
	pad.add_child(top)
	var heading := _label(title, TYPE_HEADING, C_HEADING)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(heading)
	var close := _button("Close", "secondary")
	close.pressed.connect(_close_sheet)
	top.add_child(close)
	box.add_child(pad)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	box.add_child(scroll)
	var inner := MarginContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, SPACE_S)
	inner.add_theme_constant_override("margin_top", SPACE_XS)
	scroll.add_child(inner)
	var body := _vbox(SPACE_S)
	for c in content:
		body.add_child(c)
	inner.add_child(body)
	sheet.set_meta("close", close)
	sheet.set_meta("scroll", scroll)
	sheet.set_meta("body", inner)
	_sheet_center.add_child(sheet)
	return sheet


func _open_sheet(n: int, opener: Control) -> void:
	if _open_n > 0:
		_sheets[_open_n - 1].visible = false
	_open_n = n
	_opener = opener
	_opener_keyboard = is_instance_valid(opener) and opener.has_focus(true)
	var sheet: PanelContainer = _sheets[n - 1]
	sheet.visible = true
	_sheet_layer.visible = true
	_size_sheet()
	# the focus moves into the sheet; its ring shows only when the opener had a visible one (a keyboard), not after a tap
	var keyboard := is_instance_valid(opener) and opener.has_focus(true)
	(sheet.get_meta("close") as Control).grab_focus(not keyboard)
	print("FIRST RUN sheet %d open" % n)
	# motion: the dim fades in and the card rises SHEET_RISE into place (it comes from the screen under it); none with Reduce Motion.
	# The card's centring container moves, not the card (its container would put the card back).
	if _tween != null:
		_tween.kill()
	if DisplayServer.accessibility_should_reduce_animation() == 1:
		_sheet_layer.modulate.a = 1.0
		_sheet_center.position.y = 0
		return
	_sheet_layer.modulate.a = 0.0
	_sheet_center.position.y = SHEET_RISE
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_sheet_layer, "modulate:a", 1.0, MOTION_IN)
	_tween.tween_property(_sheet_center, "position:y", 0.0, MOTION_IN)


func _close_sheet() -> void:
	if _open_n == 0:
		return
	var sheet: PanelContainer = _sheets[_open_n - 1]
	_open_n = 0
	if _tween != null:
		_tween.kill()
	var done := func():
		sheet.visible = false
		_sheet_layer.visible = false
		if is_instance_valid(_opener) and _opener.is_visible_in_tree():
			_opener.grab_focus(not _opener_keyboard)
	if DisplayServer.accessibility_should_reduce_animation() == 1:
		done.call()
		return
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_sheet_layer, "modulate:a", 0.0, MOTION_OUT)
	_tween.tween_callback(done)


# The open sheet: as wide as a column can be, as tall as its content up to the frame less SPACE_L above and below (then it scrolls).
# Its labels wrap to its width only once laid out, so the height is measured a frame later.
func _size_sheet() -> void:
	if _open_n == 0:
		return
	var sheet: PanelContainer = _sheets[_open_n - 1]
	var width := minf(_frame.size.x - 2.0 * SPACE_M, CONTENT_MAX)
	sheet.custom_minimum_size.x = width
	var scroll: ScrollContainer = sheet.get_meta("scroll")
	var body: Control = sheet.get_meta("body")
	var room := _frame.size.y - 2.0 * SPACE_L - (sheet.get_meta("close") as Control).get_combined_minimum_size().y - SPACE_S - SPACE_XS
	scroll.custom_minimum_size.y = room
	await get_tree().process_frame
	if _open_n == 0 or not is_instance_valid(body):
		return
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, room)


func _unhandled_input(event: InputEvent) -> void:
	if _open_n > 0 and event.is_action_pressed("ui_cancel"):
		_close_sheet()
		get_viewport().set_input_as_handled()


# ---- dev previews (--first-run-ios on a desktop only): every state of the card, for the screenshots ------------------------------------------

func _preview(state: String) -> void:
	_previewing = true
	var others := ""
	match state:
		"looking":
			_card_looking()
		"none":
			_card_none()
		"none-again":
			_card_none("14:02")
		"found":
			_card_found("OpenBFME-GameData.obfme", 6463767289, 25600000000, 8800000000, false, others)
		"nospace":
			_card_found("OpenBFME-GameData.obfme", 6463767289, 4100000000, 8800000000, false, others)
		"installing":
			_card_installing(2780000000, 8497649467, 212, 551, 190)
		"checking":
			_card_checking()
		"error":
			_card_error("Installing stopped", "RotWK/W3D.big arrived damaged. Send the file again, or prepare it again on the computer, then tap Try again.",
				"Try again", "install")
		"badfile":
			_card_error("This game file cannot be used", "OpenBFME-GameData.obfme is cut short: the copy did not finish. Send it again.", "Look again", "look")
		"ready":
			_card_ready()
		# lane IOS-36 (with --first-run-picker): the picker's states
		"picking":
			_card_picking("OpenBFME-GameData.obfme", "iCloud Drive")
		"downloading":
			_card_downloading("OpenBFME-GameData.obfme", "iCloud Drive")
		"picked":
			_card_found("OpenBFME-GameData.obfme", 6463767289, 25600000000, 8800000000, false, others, "iCloud Drive")
		"pickerror":
			_card_pick_error("OpenBFME-GameData.obfme", "The file couldn't be opened because you don't have permission to view it.")


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


# The (i) of a step: a 44 pt target drawing a BADGE-sized disc with an "i" (the step's number disc, mirrored on the other side), named for
# a screen reader by what it opens. A filled disc, no ring: StyleBoxFlat shows seams where a 1 px ring joins its corners.
func _info_button(name: String) -> Button:
	var b := _button("i", "secondary")
	b.custom_minimum_size = Vector2(TOUCH_MIN, TOUCH_MIN)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var inset := -(TOUCH_MIN - BADGE) / 2.0 # the disc drawn inside the target
	var fills := {"normal": C_FILL_HOVER, "hover": C_FILL_PRESSED, "pressed": C_FILL_STRONG, "hover_pressed": C_FILL_STRONG, "disabled": C_FILL}
	for state in fills:
		var box := _box(fills[state], Color.TRANSPARENT, BADGE / 2, 0, 0)
		box.corner_detail = BADGE
		box.set_expand_margin_all(inset)
		b.add_theme_stylebox_override(state, box)
	var focus := _box(Color.TRANSPARENT, C_FOCUS, BADGE / 2 + FOCUS_WIDTH, 0, 0)
	focus.draw_center = false
	focus.corner_detail = BADGE
	focus.set_border_width_all(FOCUS_WIDTH)
	focus.set_expand_margin_all(inset + FOCUS_WIDTH)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", C_TEXT_2)
	b.tooltip_text = name
	b.accessibility_name = name
	return b


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
# `looked`: the time Look again was tapped ("" otherwise): said when it found nothing new.
func _refresh_import(looked := "") -> void:
	if _importing or _card == null:
		return
	if _watching_pick: # lane IOS-36: a pick is under way (back from the picker, or iCloud still downloading): its card stays
		return
	_import = null
	var found := GameFileImport.find()
	var pending := GameFileImport.pending()
	# lane IOS-36: a file picked where it is comes first (the player chose it); one picked in OpenBFME's own folder is found there anyway
	var kept_in := ""
	if not _picked.is_empty() and str(_picked.place) != "OpenBFME's folder":
		kept_in = str(_picked.place)
		found.insert(0, str(_picked.path))
	if found.is_empty():
		if pending:
			# the folders hold part of an install: say so instead of letting their check read as a broken copy
			if _can_pick():
				_card_error("The install from the game file did not finish",
					"Choose OpenBFME-GameData.obfme again, or send it to OpenBFME again, and tap Install: it carries on where it stopped.", "Choose game file…", "pick")
				_files_link.visible = true
			else:
				_card_error("The install from the game file did not finish",
					"Send OpenBFME-GameData.obfme to OpenBFME again and tap Install: it carries on where it stopped.", "Open in Files", "files")
		else:
			_show_idle(looked)
		return
	var imp := GameFileImport.new()
	imp.keep_file = not kept_in.is_empty()
	var shown_name := found[0].get_file()
	var others := "" if found.size() == 1 else "\n" + _bb("%d other .obfme files in OpenBFME's folder are not used; delete them in the Files app." % (
		found.size() - 1), C_TEXT_3, TYPE_CAPTION)
	if not imp.open(found[0]):
		print("FIRST RUN game file: ", imp.error)
		if imp.keep_file:
			_forget_pick(found[0])
			_card_pick_error(shown_name, imp.error)
		else:
			_card_error("This game file cannot be used", imp.error + others.replace("\n", " "), "Look again", "look")
		return
	print("FIRST RUN game file: %s, %d files, %d bytes (%d still to install)%s" % [found[0].get_file(), imp.files.size(), imp.total, imp.remaining,
		(", read in place from " + kept_in) if imp.keep_file else ""])
	if _checked_ok and not pending:
		if imp.keep_file:
			_forget_pick(found[0]) # the game is there: the picked file is not needed (and stays where it is)
			_show_idle(looked)
			return
		_card_ready("%s is not needed. Delete it in the Files app to get its %s back." % [shown_name, GameFileImport.gb(imp.archive_size)])
		return
	_import = imp
	_card_found(shown_name, imp.archive_size, imp.space_left(), imp.space_needed(), imp.resuming, others, kept_in)


func _on_install() -> void:
	if _import == null or _importing or _mounting:
		return
	_importing = true
	_start.disabled = true
	_install_started = Time.get_ticks_msec()
	_card_installing(0, _import.total, 1, _import.files.size(), -1) # the button goes while it runs
	var kept_on := DisplayServer.screen_is_kept_on()
	DisplayServer.screen_set_keep_on(true) # the screen must not lock (and the app stop) halfway through
	_import.progress.connect(_on_import_progress)
	print("FIRST RUN installing the game file %s" % _import.file_name)
	var ok: bool = await _import.run()
	_import.progress.disconnect(_on_import_progress)
	DisplayServer.screen_set_keep_on(kept_on)
	_importing = false
	if not ok:
		print("FIRST RUN game file install stopped: ", _import.error)
		_card_error("Installing stopped", _import.error, "Try again", "install")
		_recheck()
		return
	print("FIRST RUN game file installed: %d files" % _import.files.size())
	if _import.keep_file:
		_forget_pick(_import.path) # lane IOS-36: read in place; its access and bookmark are no longer needed (the file stays where it was)
	_import = null
	await _look_again()
	if _checked_ok:
		_on_start() # straight on to the full check and the game, as Use these folders would


# The time left from the pace so far (after a few seconds, when it means something); -1 until then
func _on_import_progress(done_bytes: int, total_bytes: int, file_index: int, file_count: int, _file_path: String) -> void:
	var elapsed := (Time.get_ticks_msec() - _install_started) / 1000.0
	var left := int((total_bytes - done_bytes) * elapsed / done_bytes) if done_bytes > 0 and elapsed > 5.0 else -1
	_card_installing(done_bytes, total_bytes, file_index, file_count, left)


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


# lane IOS-12: one column up to WIDE_FROM points, else two (header and status card | the steps and the footer); each column at most
# CONTENT_MAX, centred. An open sheet is sized again (rotation).
func _lay_out(frame_width: float, room: float) -> void:
	var wide := frame_width > WIDE_FROM
	var width := minf((room - SPACE_L) / 2.0 if wide else room, CONTENT_MAX)
	_scroll_main.custom_minimum_size.x = width
	_scroll_steps.custom_minimum_size.x = width
	_scroll_steps.visible = wide
	_size_sheet()
	if wide == _wide:
		return
	_wide = wide
	var column := _col_steps if wide else _col_main
	for part in [_steps_card, _footer]:
		if part.get_parent() != column: # reparent() to the same parent does nothing
			part.reparent(column, false)
	_col_main.move_child(_end_pads[0], -1)
	_col_steps.move_child(_end_pads[1], -1)
