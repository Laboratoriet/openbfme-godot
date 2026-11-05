## Lane IOS-24: the "iPhone / iPad" tab of the OpenBFME options page (desktop only): one button that makes OpenBFME-GameData.obfme from the
## game folders this game runs on (game_file_pack.gd), with its progress, and then says how to send it to the phone or tablet. NOT RETAIL:
## the original game has nothing like it; the rows are the page's own gadgets (openbfme_options_screen.gd draws them, this says what they are).
##
## States, each its own rows and note: ready (PREPARE), not possible (the reason, the button greyed), writing (the share done and the time
## left, CANCEL), done (the size, SHOW FILE, the three ways to send it), stopped (the reason, TRY AGAIN), cancelled (PREPARE again).
## The file is written by a thread of its own: the menus stay usable, and leaving the page does not stop it (the tab shows it again).
extends RefCounted

const GameFilePack := preload("res://scripts/release/game_file_pack.gd")

const TAB := "iPhone / iPad"
const ACTION := "Prepare.action"
const TICK_MSEC := 500     # how often the progress row is redrawn while the file is written

var mount_getter: Callable  # () -> the mount report of this start (openbfme_options_screen.gd: Release.last_mount)
var output := ""            # where the file goes ("": GameFilePack.default_output(), the Desktop); a test points it elsewhere
var _pack: GameFilePack    # the file being made or made (null: not started this session)
var _refused := ""         # why the last PREPARE could not start (nothing was written)
var _shown_phase := ""
var _tick := 0


## The tab exists on a desktop only (a phone has nothing to prepare).
static func available() -> bool:
	return not OS.has_feature("mobile") and not OS.has_feature("web")


func rows() -> Array:
	var s := _status()
	var phase: String = s.phase
	var place := _place()
	var rows := [
		_text("Prepare.folders", "Your game folders", _folders_line(), "The folders OpenBFME runs on now. They are only read, never changed."),
		_text("Prepare.file", "The game file", "about 6.5 GB, %s" % place,
			"OpenBFME-GameData.obfme: one file with what the game reads from both folders (no Windows programs). It replaces an older one of the same name."),
	]
	var label := "Make the game file"
	var button := "PREPARE"
	var help := "Writes the game file %s. It takes a few minutes; you can keep using the menus meanwhile." % place
	var enabled := _plan_problem().is_empty()
	var state := ""
	match phase:
		"writing":
			label = "Making the game file"
			button = "CANCEL"
			help = "Stops and deletes the half-written file."
			enabled = true
			state = "%d %%" % int(100.0 * s.done / maxf(1.0, s.total)) + (" · %s left" % _duration(s.seconds_left) if s.seconds_left >= 0 else " · working out the time")
		"done":
			label = "The game file is ready"
			button = "SHOW FILE"
			help = "Shows OpenBFME-GameData.obfme in %s." % ("Finder" if OS.get_name() == "macOS" else "the file manager")
			enabled = true
			state = "Done · %s" % _gb(s.size)
		"failed":
			button = "TRY AGAIN"
			state = "Stopped: see below"
		"cancelled":
			state = "Cancelled; nothing was kept"
		_:
			# the values stay under about 30 characters: a Text row is not wrapped (OpenBFMEOptionsPage draws it from the gadget column on)
			state = "Ready" if not FileAccess.file_exists(_output()) else "Ready (replaces the old file)"
	if not enabled:
		state = "Not possible now: see below"
	rows.append({"kind": "button", "key": ACTION, "label": label, "value_text": button, "help": help, "enabled": enabled})
	rows.append(_text("Prepare.state", "Status", state, "What the game file is doing."))
	if phase == "done":
		var device := "iPhone or iPad"
		var app := "Finder" if OS.get_name() == "macOS" else "Apple Devices"
		rows.append(_text("Prepare.cable", "With a cable", "%s › your device › Files" % app,
			"Connect the %s, select it in %s, open Files and drag the file onto OpenBFME." % [device, app]))
		rows.append(_text("Prepare.airdrop", "Wirelessly", "AirDrop, then Save to Files",
			"AirDrop the file to the %s, choose Save to Files and pick On My iPhone (or iPad) › OpenBFME." % device))
		rows.append(_text("Prepare.icloud", "Through iCloud Drive", "then move it to OpenBFME",
			"Put the file in iCloud Drive. On the %s, in the Files app, move it to On My iPhone (or iPad) › OpenBFME." % device))
	return rows


## The help line while no row is pointed at: what the tab is for, or what happened.
func note() -> String:
	var s := _status()
	match s.phase:
		"done":
			return "Now send it to your iPhone or iPad: point at a way below. Then open OpenBFME there and tap Install; the app deletes the file once the game is in place."
		"failed":
			return s.error
		"writing":
			return "Keep OpenBFME open until the file is done. Your game folders are only read."
	var problem := _plan_problem()
	if not problem.is_empty():
		return problem
	return "OpenBFME on iPhone and iPad plays your own copy of the game too. Make one file of it here, send it to the phone or tablet, and the app installs it."


## A Button row was clicked.
func press(key: String) -> void:
	if key != ACTION:
		return
	var s := _status()
	match s.phase:
		"writing":
			_pack.cancel()
		"done":
			preload("res://scripts/external_open.gd").show_in_file_manager(s.out)
		_:
			_start()


## Called every frame while the tab is shown: "show" (the state changed: rebuild the page), "sync" (the progress row changed), "" (nothing).
func tick() -> String:
	if _pack == null:
		return ""
	var phase: String = _pack.status().phase
	if phase != _shown_phase:
		_shown_phase = phase
		if phase != "writing":
			_pack.wait()
			print("GAME FILE PREPARE ", phase, ": ", _pack.status().out if phase == "done" else _pack.status().error)
		return "show"
	if phase == "writing" and Time.get_ticks_msec() - _tick > TICK_MSEC:
		_tick = Time.get_ticks_msec()
		return "sync"
	return ""


## The game is closing: the thread is told to stop and waited for (its half-written file is deleted).
func stop() -> void:
	if _pack != null and _pack.is_running():
		_pack.cancel()
	if _pack != null:
		_pack.wait()


func _start() -> void:
	var pack := GameFilePack.new()
	_refused = ""
	if not pack.plan(_mount()) or not pack.start(_output()):
		_refused = pack.error # said on the tab like a stop while writing
		_pack = null
		_shown_phase = ""
		return
	_pack = pack
	print("GAME FILE PREPARE writing %s: %d files, %d bytes (%d left out)" % [pack.out_path.get_file(), pack.files.size(), pack.total, pack.skipped.size()])


func _status() -> Dictionary:
	if _pack != null:
		return _pack.status()
	return {"phase": "failed" if not _refused.is_empty() else "idle", "error": _refused, "done": 0, "total": 0, "seconds_left": -1, "size": 0, "out": ""}


func _mount() -> Dictionary:
	return mount_getter.call() if mount_getter.is_valid() else {}


func _output() -> String:
	return output if not output.is_empty() else GameFilePack.default_output()


# "" when a file can be made from the folders in use, else why not
func _plan_problem() -> String:
	var m := _mount()
	if not m.get("ok", false):
		return "OpenBFME has not opened the game folders in this session, so there is nothing to pack. Start OpenBFME normally, then come back here."
	if str(m.get("rotwk_install", "")).is_empty():
		return "OpenBFME runs in Battle for Middle-earth mode now. Start it for The Rise of the Witch-king to prepare the game file."
	return ""


func _folders_line() -> String:
	var m := _mount()
	if not m.get("ok", false) or str(m.get("rotwk_install", "")).is_empty():
		return "not in use"
	return "RotWK 2.01 and BFME2 1.06"


func _place() -> String:
	var out := _output()
	if out.get_base_dir() == OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP):
		return "on your Desktop"
	if out.get_base_dir() == OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS):
		return "in Documents"
	return "in " + out.get_base_dir().get_file()


static func _text(key: String, label: String, value: String, help: String) -> Dictionary:
	return {"kind": "text", "key": key, "label": label, "value_text": value, "help": help}


static func _gb(bytes: int) -> String:
	return "%.2f GB" % (bytes / 1e9)


static func _duration(seconds: int) -> String:
	if seconds < 60:
		return "less than a minute"
	return "about %d min" % ceili(seconds / 60.0)
