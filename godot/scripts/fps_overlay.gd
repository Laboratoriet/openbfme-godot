## Lane OPTS-1: the frame-rate counter and the OpenBFME display hotkeys (NOT RETAIL: owner, 2026-10-10).
##   F11        shows / hides the frame-rate counter (saved as show_fps in openbfme-display.cfg)
##   Alt+Enter  toggles between a window and full screen (the last full-screen kind chosen, borderless by default; saved as window_mode)
## Both keys are free in RotWK 2.01's CommandMap.ini (no CommandMap record uses KEY_F11 with any modifier, or KEY_ENTER with ALT; checked against the
## retail file by tools/opts/test_opts1_hotkeys.py), so no retail command loses its key. The node sits under the scene root after the game, so it sees
## a key before the shell, the HUD and the game do, and a key it acts on goes no further.
## The counter: frames per second and the mean frame time of the last half second, drawn over everything in the top-left corner.
## Lane IOS-25 (GOAL 2026-11-03 item 4: "an on-screen fps / frame-time readout, off by default; --perf turns it on"): the same counter and the same
## setting (show_fps, not a second option for one readout), and on touch (a phone, a tablet or --touch, TouchControls' rule) a phone's readout:
##   "60 fps · 16.6 ms · p99 21 ms": the frame rate, the mean frame time of the last half second and the 99th percentile frame time of the last
##     RING frames (GAME PERF's p99, game.gd _perf_frame: v[int(0.99 * (n - 1))]; 5 s at 60 fps, GAME PERF's window), again twice a second;
##   at least MenuText.MOBILE_MIN_PT points tall (16 px times the interface scale when that is larger);
##   in the top-left corner inside the safe area (on a phone; the window is the screen with --touch): clear of the Palantir (bottom left), the side
##     command bar (right), the clock (top centre), the game's messages and the version corner (top right; where the menus' version line reaches
##     it, in a portrait window, the readout goes under the corner: Release.corner_rect). The menus' top-left lines start under it (game.gd
##     _style_menu_texts: reserved_bottom, again on layout_changed);
##   no layout shift: the numbers followed by more text sit in fixed-width fields padded with figure spaces (U+2007, a digit's width) in Godot's
##     face, whose digits are tabular (the p99, last, needs none); no allocation per frame (a fixed ring of frame times, the p99 found by keeping
##     the few largest).
## A desktop without --touch keeps the counter as it was ("60 fps  16.6 ms", 16 px times the interface scale, at 8, 4).
extends CanvasLayer

signal layout_changed        # lane IOS-25: the counter appeared, disappeared or changed size (the menus' top-left lines follow it)

const DisplaySettings := preload("res://scripts/display_settings.gd")
const MenuText := preload("res://scripts/menu_text.gd")
const RING := 300            # lane IOS-25: frame times kept for the p99
const TOP := 4               # the largest frame times kept to find the p99: RING - 1 - int(0.99 * (RING - 1)) + 1
const FIGURE_SPACE := "\u2007"
const BASE_PX := 16          # the counter's size at interface scale 100 %
const WIDEST := "888 fps · 88.8 ms · p99 888 ms" # lane IOS-25: the room the touch readout keeps (Release's corner must not reach into it)

const HOTKEYS := [
	{"name": "OPENBFME_TOGGLE_FPS", "key": KEY_F11, "alt": false, "commandmap": "KEY_F11", "modifiers": "any"},
	{"name": "OPENBFME_TOGGLE_FULLSCREEN", "key": KEY_ENTER, "alt": true, "commandmap": "KEY_ENTER", "modifiers": "ALT"},
]

var settings: RefCounted     # scripts/display_settings.gd, the settings in effect (shared with game.gd and the options screen)
var settings_path := ""
var session_fps := false     # --fps: shown for this run whatever the file says
var preview = null           # the options screen's box while the screen is up (true / false), else null
var screen: CanvasLayer      # scripts/openbfme_options_screen.gd: while it is up the keys change its settings, not the file
var touch := false           # lane IOS-25: the phone's readout (OS feature "mobile" or --touch, as scripts/touch/touch_controls.gd)
var _label: Label
var _frames := 0
var _since_us := 0
var _text := ""
var _ui_scale := 1.0         # OpenBFMEUIScale / 100 (game_options.gd set_ui_scale)
var _px_per_pt := 1.0
var _font_px := BASE_PX
var _shown := false
var _ring := PackedFloat32Array()
var _ring_n := 0
var _ring_i := 0
var _top := PackedFloat32Array()
var _prev_us := 0


func _ready() -> void:
	layer = 120
	touch = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")
	_px_per_pt = maxf(1.0, DisplayServer.screen_get_scale())
	_label = Label.new()
	_label.name = "FpsCounter"
	_label.set_meta("game_text", true) # a player's option, not developer text (game.gd _dev_text_on_screen)
	_label.position = Vector2(8, 4)
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	if touch:
		_ring.resize(RING)
		_top.resize(TOP)
		_label.position = _home()
		if OS.has_feature("mobile"):
			# clear of the status bar, the camera and the rounded corners (the safe area's top-left inset, as game.gd's online count), on every turn
			get_viewport().size_changed.connect(_fit_safe_area)
			_fit_safe_area()
	_apply_size()
	_since_us = Time.get_ticks_usec()
	refresh()


## OpenBFMEUIScale (game_options.gd): the counter is 16 px times it (on touch at least MOBILE_MIN_PT points)
func set_ui_scale(k: float) -> void:
	_ui_scale = k
	if _label != null:
		_apply_size()


func _apply_size() -> void:
	var px := roundi(BASE_PX * _ui_scale)
	if touch:
		px = maxi(px, roundi(MenuText.MOBILE_MIN_PT * _px_per_pt))
		_label.add_theme_constant_override("outline_size", maxi(4, roundi(px / 6.0)))
	_label.add_theme_font_size_override("font_size", px)
	if px != _font_px:
		_font_px = px
		layout_changed.emit()
	_place()


func _fit_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0 and safe.size.y > 0 and offset != Vector2(safe.position):
		offset = Vector2(safe.position)
		layout_changed.emit()
		_place()


## the touch readout's place in the corner: a few points in from the layer's (safe area's) top left
func _home() -> Vector2:
	return Vector2(roundf(6.0 * _px_per_pt), roundf(4.0 * _px_per_pt))


## lane IOS-25: on touch, the readout at its home, or under the version corner where that corner (menus only) reaches into its room
func _place() -> void:
	if not touch or _label == null:
		return
	var at := _home()
	var font := _label.get_theme_font("font")
	var room := Rect2(offset + at, Vector2(font.get_string_size(WIDEST, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px).x, font.get_height(_font_px)))
	var release := get_node_or_null("/root/Release")
	var corner: Rect2 = release.corner_rect() if release != null and release.has_method("corner_rect") else Rect2()
	if corner.has_area() and room.intersects(corner):
		at.y = corner.end.y - offset.y + roundf(2.0 * _px_per_pt)
	if at != _label.position:
		_label.position = at
		layout_changed.emit()


## lane IOS-25: on touch, where the menus' top-left lines may start (in this layer's coordinates, which the online count's layer shares: the safe
## area's inset): under the readout while it shows. 0 on a desktop, whose lines keep their place (game.gd _style_menu_texts' 30 px).
func reserved_bottom() -> float:
	if not touch or _label == null or not _label.visible:
		return 0.0
	return _label.position.y + _label.get_theme_font("font").get_height(_font_px) + roundf(2.0 * _px_per_pt)


func shown() -> bool:
	if preview != null:
		return preview
	return session_fps or (settings != null and settings.show_fps)


func refresh() -> void:
	var on := shown()
	_label.visible = on
	if on != _shown:
		_shown = on
		_place()
		layout_changed.emit()


func counter_text() -> String:
	return _label.text


func _process(_delta: float) -> void:
	if not _label.visible:
		_frames = 0
		_since_us = Time.get_ticks_usec()
		_ring_n = 0
		_prev_us = 0
		return
	_frames += 1
	var now := Time.get_ticks_usec()
	if touch:
		if _prev_us != 0:
			_ring[_ring_i] = (now - _prev_us) / 1000.0
			_ring_i = (_ring_i + 1) % RING
			_ring_n = mini(_ring_n + 1, RING)
		_prev_us = now
	var span := now - _since_us
	if span >= 500000 or _label.text.is_empty():
		var ms := (span / 1000.0) / maxi(_frames, 1)
		var fps := roundi(Engine.get_frames_per_second())
		if touch:
			_place() # the version corner comes and goes with the menus, and grows with the update note
			_label.text = "%s fps · %s ms · p99 %d ms" % [_pad(str(fps), 3), _pad("%.1f" % ms, 4), roundi(p99())]
		else:
			_label.text = "%d fps  %.1f ms" % [fps, ms]
		_frames = 0
		_since_us = now


## lane IOS-25: the 99th percentile of the ring's frame times (ms) as GAME PERF takes it: the sorted times' element int(0.99 * (n - 1)), found by
## keeping the TOP largest (no sort, no allocation). 0 before two frames.
func p99() -> float:
	var n := _ring_n
	if n == 0:
		return 0.0
	var above := n - 1 - int(0.99 * (n - 1)) # the times larger than the p99's place
	_top.fill(-1.0)
	for i in n:
		var v := _ring[i]
		if v <= _top[TOP - 1]:
			continue
		var j := TOP - 1
		while j > 0 and v > _top[j - 1]:
			_top[j] = _top[j - 1]
			j -= 1
		_top[j] = v
	return _top[above]


static func _pad(text: String, width: int) -> String:
	return FIGURE_SPACE.repeat(maxi(0, width - text.length())) + text


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F11 and not key.alt_pressed and not key.ctrl_pressed and not key.shift_pressed:
		get_viewport().set_input_as_handled()
		toggle_fps()
	elif (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and key.alt_pressed and not key.ctrl_pressed and not key.shift_pressed:
		get_viewport().set_input_as_handled()
		toggle_fullscreen()


func toggle_fps() -> void:
	if settings == null:
		return
	var on := not shown()
	if screen != null and screen.is_open():
		screen.hotkey("show_fps", on) # the screen's settings, written by its ACCEPT, put back by its CANCEL
		print("GAME DISPLAY frame-rate counter %s (F11, options screen)" % ("on" if on else "off"))
		return
	session_fps = false
	settings.show_fps = on
	_save(["show_fps"])
	refresh()
	print("GAME DISPLAY frame-rate counter %s (F11)" % ("on" if shown() else "off"))


## Alt+Enter: windowed <-> full screen, from the mode the window is in. Going full screen uses the kind this run last left (borderless when it never
## had one). Only the window mode changes (and only window_mode is written): a --max-fps cap or the screen's other settings stay.
var _last_fullscreen := "borderless"
func toggle_fullscreen() -> void:
	if settings == null:
		return
	var root := get_tree().root
	var open: bool = screen != null and screen.is_open()
	var current: String = DisplaySettings.window_mode_now(root, screen.pending_value("window_mode") if open else settings.window_mode)
	var next := _last_fullscreen
	if current != "windowed":
		_last_fullscreen = current
		next = "windowed"
	if open:
		screen.hotkey("window_mode", next)
		print("GAME DISPLAY Alt+Enter: %s (options screen)" % next)
		return
	var before = settings.copy()
	before.window_mode = current
	settings.window_mode = next
	var r: Dictionary = settings.apply(root, before)
	_save(["window_mode"])
	print("GAME DISPLAY Alt+Enter: %s %s" % [", ".join(r.applied), "" if r.problems.is_empty() else str(r.problems)])


func _save(keys: Array) -> void:
	if settings_path.is_empty():
		return
	if not settings.save_keys(settings_path, keys):
		printerr("GAME DISPLAY ", settings.errors[-1])
