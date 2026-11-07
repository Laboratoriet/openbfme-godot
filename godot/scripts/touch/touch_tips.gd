extends CanvasLayer
## Lane IOS-46 (PROTOTYPES for the owner's choice; the owner, 2026-11-07: much of the touch scheme is hard to discover: hold for info, ✓ / ✕, twist
## to rotate, tap-preview, aiming powers). Three ways to teach it, switched by Options > Touch > Help > "Help style" (game_options.gd
## OpenBFMETouchHelp); "Show tips" (OpenBFMETouchTips) turns the in-game prompts of (a) and (b) off:
##
##   (b) "tips" (the default) ... contextual one-time tips: a small toast the first time a feature is reachable, each shown once:
##                                  hold ...... the first selection: "Hold any button to see what it does."
##                                  preview ... the first tap that only previews a button (IOS-40): "Tap once to see what it is, tap again to use it."
##                                  autocast .. the first previewed autocast ability: "Double-tap an ability like this to turn autocast on or off."
##                                  unqueue ... the first ✕ beside an armed recruit button (IOS-37): "Tap ✕ to take one off the queue."
##                                  place ..... the first ghost waiting for ✓ / ✕ (IOS-26): "Drag to move it, then tap ✓ to build."
##                                  twist ..... after it, while the ghost waits (IOS-37, not a wall): "Twist two fingers to turn the building."
##                                  aim ....... the first power aimed with ✓ / ✕ (IOS-43): "The spot shows above your finger: lift, then tap ✓."
##                                  camera .... the first one-finger box drag (it may have been meant to move the view), or a minute of play
##                                              without a two-finger gesture: "Two fingers move the view: drag, pinch to zoom, twist to turn."
##                                A tip the player shows they already know (they held a button, turned a ghost, panned) is never shown. One at a
##                                time, top of the safe area, under the command toolbar and the power banner, clear of ✓ / ✕ and the armed ring; ✕
##                                (or a tap on it) dismisses it, it goes by itself after TIP_S, and at once when its moment ends (the ghost placed)
##   (a) "guide" ................ a short, skippable first-game guide in the same panel, five steps that complete as the player does them: select, move,
##                                tap twice, hold, two fingers. While a ghost or a power waits, the panel says how to place / aim instead. "Skip" ends it
##   (c) "card" ................. no prompts in the game: the "Touch controls" card only (touch_help_card.gd), which every style has in Options > Touch >
##                                Help and on the pause menu
##
## Shown once: the tips seen, the tips learned and the guide's steps live in user://touch_tips.cfg (the player's data, not Options.ini: a tip seen in a
## game is not a setting the Options page's ACCEPT / CANCEL should hold back). Options > Touch > Help > "Reset tips" empties it.
##
## Never blocking: nothing here takes input of its own (mouse_filter IGNORE). The touch layer (touch_controls.gd) asks hit() before its own gestures: a
## finger on the panel is the panel's (its ✕ / Skip on lift); everywhere else the game's. The touch layer feeds it events (event()) as its gestures
## happen, never by polling the game for them, and its context (set_context()) on the toolbar's poll. Hidden while a menu is over the game, outside a
## game, and while a mouse is in use.
##
## Motion: in over APPEAR_S with a DROP_PT drop (cubic ease-out), out over HIDE_S (ease-in); a guide step's completion flashes the step dot. Reduce
## Motion: fades only.

const TouchGlyphs := preload("res://scripts/touch/touch_glyphs.gd")

const STYLE_TIPS := "tips"
const STYLE_GUIDE := "guide"
const STYLE_CARD := "card"
const STYLES := [STYLE_TIPS, STYLE_GUIDE, STYLE_CARD]
const STORE_PATH := "user://touch_tips.cfg"

## the tips, in the order they are listed (the tests, the log)
const TIPS := {
	"hold": {"text": "Hold any button to see what it does.", "glyph": "hold"},
	"preview": {"text": "Tap once to see what it is, again to use it.", "glyph": "tap2"},
	"autocast": {"text": "Double-tap an ability like this to turn its autocast on or off.", "glyph": "double"},
	"unqueue": {"text": "Tap ✕ beside the button to cancel: one off the queue, or the upgrade.", "glyph": "unqueue"},  # IOS-49: upgrades too
	"place": {"text": "Drag to move it, then tap ✓ to build it here.", "glyph": "confirm"},
	"twist": {"text": "Twist two fingers to turn the building.", "glyph": "twist"},
	"aim": {"text": "The spot shows above your finger: lift, then tap ✓.", "glyph": "aim"},
	"camera": {"text": "Two fingers move the view: drag, pinch to zoom, twist to turn.", "glyph": "pinch"},
}
## the first-game guide's steps (done by the event in "done")
const GUIDE := [
	{"id": "select", "text": "Tap one of your units to select it.", "glyph": "tap"},
	{"id": "move", "text": "Now tap the ground to send them there.", "glyph": "tap"},
	{"id": "buttons", "text": "Tap a button once to see what it is, tap it again to use it.", "glyph": "tap2"},
	{"id": "hold", "text": "Hold any button to see what it does, without using it.", "glyph": "hold"},
	{"id": "camera", "text": "Two fingers move the view: drag, pinch to zoom, twist to turn.", "glyph": "pinch"},
]
const GUIDE_PLACING := {"text": "Drag to move it, twist two fingers to turn it, then tap ✓ to build.", "glyph": "confirm"}
const GUIDE_AIMING := {"text": "Touch the map: the spot shows above your finger. Lift, then tap ✓.", "glyph": "aim"}
const GUIDE_FINISHED := "That's the basics. Every gesture: Options › Touch › Help."

const MAX_W_PT := 480.0        # the panel's widest (a longer line wraps to two)
const MARGIN_PT := 12.0        # from the safe area's sides
const TOP_PT := 8.0            # from the top (the toolbar's / banner's bottom, or the safe area's)
const AVOID_PT := 8.0          # kept clear around ✓ / ✕, the armed ring, the banner
const CELL_PT := 44.0          # the ✕ cell (iOS's minimum target)
const SKIP_W_PT := 66.0        # the Skip cell's width (44 pt high)
const GLYPH_PT := 34.0
const TEXT_PT := 15.0
const HEAD_PT := 11.5
const PAD_X_PT := 12.0
const PAD_Y_PT := 6.0
const TIP_S := 6.5             # a tip's time on screen (≤ 14 words: read twice over)
const MIN_READ_S := 1.5        # a tip hidden by its moment ending sooner than this counts as not seen
const FINISHED_S := 4.0
const CAMERA_AFTER_S := 60.0   # the camera tip's fallback: this long in a game without a two-finger gesture
const SELECTION_CHECK_MS := 180  # a world tap's selection is read this long after it (the HUD takes the click on its next frame)
const APPEAR_S := 0.22
const HIDE_S := 0.16
const DROP_PT := 8.0
const MOVE_S := 0.2

# IOS-12's tokens (touch_targeting.gd, placement_confirm.gd)
const C_SURFACE := Color(0.06, 0.06, 0.07, 0.94)
const C_BORDER := Color(0.784, 0.635, 0.353, 0.6)
const C_ACCENT := Color("c8a25a")
const C_TEXT := Color(0.94, 0.91, 0.84)
const C_HINT := Color(0.94, 0.91, 0.84, 0.72)
const C_DIM := Color(0.94, 0.91, 0.84, 0.28)
const C_DISC := Color(0.06, 0.06, 0.07, 0.88)
const C_DISC_PRESSED := Color(0.17, 0.15, 0.11, 0.94)
const C_RING_2 := Color(0.784, 0.635, 0.353, 0.4)
const C_GLYPH_2 := Color(1, 1, 1, 0.82)


## the picture at the panel's left
class Glyph:
	extends Control
	var name_ := ""
	var colour := C_ACCENT

	func _draw() -> void:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, Color(0.784, 0.635, 0.353, 0.1), true, -1.0, true)  # the card's tile (touch_help_card.gd)
		TouchGlyphs.draw(self, name_, size * 0.5, minf(size.x, size.y) * 0.9, colour)


## the panel's action cell: ✕ (a tip) or "Skip" (the guide)
class Action:
	extends Control
	var px := 1.0
	var skip := false
	var pressed := false
	var font: Font

	func _draw() -> void:
		var c := size * 0.5
		if skip:
			var text := "Skip"
			var fs := roundi(TEXT_PT * 0.93 * px)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pill := Rect2(Vector2(c.x - w * 0.5 - 10.0 * px, c.y - 15.0 * px), Vector2(w + 20.0 * px, 30.0 * px))
			draw_style_box(_pill(pill.size.y * 0.5), pill)
			draw_string(font, Vector2(pill.position.x + 10.0 * px, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)
			return
		var r := 15.0 * px
		draw_circle(c, r, C_DISC_PRESSED if pressed else C_DISC, true, -1.0, true)
		draw_arc(c, r - 0.75 * px, 0.0, TAU, 36, C_RING_2, 1.5 * px, true)
		var k := r * 0.36
		draw_line(c + Vector2(-k, -k), c + Vector2(k, k), C_GLYPH_2, 2.25 * px, true)
		draw_line(c + Vector2(-k, k), c + Vector2(k, -k), C_GLYPH_2, 2.25 * px, true)

	func _pill(radius: float) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = C_DISC_PRESSED if pressed else Color(0, 0, 0, 0)
		s.border_color = C_RING_2
		s.set_border_width_all(maxi(1, roundi(1.25 * px)))
		s.set_corner_radius_all(roundi(radius))
		s.anti_aliasing = true
		return s


## the guide's step dots ("● ● ○ ○ ○")
class Dots:
	extends Control
	var px := 1.0
	var count := 0
	var done := 0
	var flash := 0.0  # 1 -> 0: the dot just done grows and settles

	func _draw() -> void:
		var r := 3.5 * px
		var gap := 11.0 * px
		var y := size.y * 0.5
		for i in count:
			var at := Vector2(r + 1.0 * px + i * gap, y)
			if i < done:
				var grow := (1.0 + 0.6 * flash) if i == done - 1 else 1.0
				draw_circle(at, r * grow, C_ACCENT, true, -1.0, true)
			elif i == done:
				draw_arc(at, r, 0.0, TAU, 20, C_ACCENT, 1.5 * px, true)
			else:
				draw_arc(at, r, 0.0, TAU, 20, C_DIM, 1.25 * px, true)


var enabled := true           # OpenBFMETouchTips ("Show tips")
var suppressed := false       # a scripted run's: no prompts whatever the options say (--no-touch-tips, the touch self-test)
var style := STYLE_TIPS       # OpenBFMETouchHelp
var store_path := STORE_PATH  # tests use their own file
var hud_getter: Callable      # () -> the game's InGameHudNode or null (the world tap's selection check)
var shown_log: Array = []     # the tips and guide panels shown, in order ("tip:hold", "guide:select", ...): the tests, the log

var _px := 1.0
var _seen := {}               # tip id -> true
var _learned := {}            # tip id -> true (the player did it: never shown)
var _guide_done := {}         # guide step id -> true
var _guide_finished := false  # done or skipped
var _queue: Array = []        # tip ids waiting
var _current := ""            # what the panel shows: a tip id, "guide:<step>", "guide:placing", "guide:aiming", "guide:finished" or ""
var _current_ms := 0          # when it showed
var _until_ms := 0            # when it goes by itself (0: while its moment lasts)
var _ctx := {"game": false, "menu": false, "mouse": false, "placing": false, "line": false, "twist_ghost": true, "aiming": false, "armed": false}
var _avoid: Array = []        # Rect2: what the panel keeps off (window pixels)
var _top := 0.0               # the toolbar's or the banner's bottom (window pixels; 0: none)
var _safe := Rect2()
var _game_s := 0.0            # seconds in a game with no menu over it (the camera tip's fallback)
var _check_ms := 0            # a world tap's selection check is due then (0: none)
var _sel_before: Array = []
var _camera_used := {}        # "pan" / "zoom" / "twist" seen (the guide's last step wants a pan and a zoom)

var _panel: PanelContainer
var _head: HBoxContainer
var _head_label: Label
var _dots: Dots
var _glyph: Glyph
var _label: Label
var _action: Action
var _tween: Tween = null
var _dot_tween: Tween = null
var _visible := false


func _init() -> void:
	layer = 111  # over the game, its HUD, the toolbar (108), the banner and the armed ring (109) and ✓ / ✕ (110); under the frame-rate readout (120)


func setup(px_per_pt: float) -> void:
	_px = px_per_pt
	_panel = PanelContainer.new()
	_panel.name = "TouchTip"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = C_SURFACE
	style_box.border_color = C_BORDER
	style_box.set_border_width_all(maxi(1, roundi(1.0 * _px)))
	style_box.set_corner_radius_all(roundi(12.0 * _px))
	style_box.content_margin_left = PAD_X_PT * 0.75 * _px
	style_box.content_margin_right = 2.0 * _px  # the 44 pt cell brings its own room
	style_box.content_margin_top = PAD_Y_PT * _px
	style_box.content_margin_bottom = PAD_Y_PT * _px
	style_box.shadow_color = Color(0, 0, 0, 0.35)
	style_box.shadow_size = roundi(5.0 * _px)
	style_box.anti_aliasing = true
	_panel.add_theme_stylebox_override("panel", style_box)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", roundi(0.0 * _px))
	_panel.add_child(column)
	# the guide's head: "GETTING STARTED  2 of 5" and the dots
	_head = HBoxContainer.new()
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.add_theme_constant_override("separation", roundi(10.0 * _px))
	column.add_child(_head)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2((GLYPH_PT + 10.0) * _px - 10.0 * _px, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.add_child(spacer)
	_head_label = Label.new()
	_head_label.add_theme_font_size_override("font_size", roundi(HEAD_PT * _px))
	_head_label.add_theme_color_override("font_color", C_ACCENT)
	_head.add_child(_head_label)
	_dots = Dots.new()
	_dots.px = _px
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.custom_minimum_size = Vector2(GUIDE.size() * 11.0 * _px, 14.0 * _px)
	_head.add_child(_dots)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", roundi(10.0 * _px))
	column.add_child(row)
	_glyph = Glyph.new()
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.custom_minimum_size = Vector2.ONE * GLYPH_PT * _px
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_glyph)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", roundi(TEXT_PT * _px))
	_label.add_theme_color_override("font_color", C_TEXT)
	_label.add_theme_constant_override("line_spacing", roundi(1.0 * _px))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_label)
	_action = Action.new()
	_action.px = _px
	_action.font = _label.get_theme_font("font")
	_action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action.focus_mode = Control.FOCUS_NONE
	_action.custom_minimum_size = Vector2.ONE * CELL_PT * _px
	_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action.accessibility_name = "Dismiss tip"
	row.add_child(_action)
	add_child(_panel)
	load_store()


# ---------------------------------------------------------------------------------------------------------------------------------
# the options and the store
# ---------------------------------------------------------------------------------------------------------------------------------
## Options > Touch > Help as game_options.gd applies it (via touch_controls.gd apply_options): `help` OpenBFMETouchHelp, `tips_on` OpenBFMETouchTips
func apply(help: String, tips_on: bool) -> void:
	var s := help if help in STYLES else STYLE_TIPS
	if s != style or tips_on != enabled:
		print("TOUCH IOS-46 help: %s, tips %s" % [s, "on" if tips_on else "off"])
	style = s
	enabled = tips_on
	if not _prompts_on():
		_queue.clear()
		_hide()


func load_store() -> void:
	_seen = {}
	_learned = {}
	_guide_done = {}
	_guide_finished = false
	var cfg := ConfigFile.new()
	if cfg.load(store_path) != OK:
		return  # no file yet: nothing seen
	for k in cfg.get_section_keys("seen") if cfg.has_section("seen") else []:
		_seen[k] = true
	for k in cfg.get_section_keys("learned") if cfg.has_section("learned") else []:
		_learned[k] = true
	for k in cfg.get_section_keys("guide") if cfg.has_section("guide") else []:
		if k == "finished":
			_guide_finished = bool(cfg.get_value("guide", k, false))
		else:
			_guide_done[k] = true


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in _seen:
		cfg.set_value("seen", k, true)
	for k in _learned:
		cfg.set_value("learned", k, true)
	for k in _guide_done:
		cfg.set_value("guide", k, true)
	if _guide_finished:
		cfg.set_value("guide", "finished", true)
	var err := cfg.save(store_path)
	if err != OK:
		printerr("TOUCH IOS-46 the tips file %s could not be written: %s" % [store_path, error_string(err)])


## Options > Touch > Help > "Reset tips": every tip and the guide show again
func reset() -> void:
	_seen.clear()
	_learned.clear()
	_guide_done.clear()
	_guide_finished = false
	_camera_used.clear()
	_game_s = 0.0
	_queue.clear()
	_hide()
	_save()
	print("TOUCH IOS-46 tips reset")


## how many tips the player has seen or learned, and the guide's progress (the Options row's text)
func progress() -> Dictionary:
	var known := {}
	for k in _seen:
		known[k] = true
	for k in _learned:
		known[k] = true
	return {"tips_known": known.size(), "tips": TIPS.size(), "guide_done": _guide_done.size(), "guide": GUIDE.size(), "guide_finished": _guide_finished}


func seen(id: String) -> bool:
	return _seen.has(id)


func learned(id: String) -> bool:
	return _learned.has(id)


# ---------------------------------------------------------------------------------------------------------------------------------
# what happens (touch_controls.gd calls these as its gestures happen)
# ---------------------------------------------------------------------------------------------------------------------------------
## `name`: selected, world_tap {before: the selection's ids}, drag_box, armed {autocast}, armed_use, unqueue_shown, unqueued, info, placement_wait
## {line, twist}, placement_built, ghost_turned, aim_wait, aim_fired, camera {kind: pan / zoom / twist}
func event(name: String, info := {}) -> void:
	match name:
		"world_tap":
			_sel_before = info.get("before", [])
			_check_ms = Time.get_ticks_msec() + SELECTION_CHECK_MS
		"selected":
			_offer("hold")
			_step_done("select")
		"ordered":
			_step_done("move")
		"drag_box":
			if not _camera_used.has("pan"):
				_offer("camera")
			_sel_before = []
			_check_ms = Time.get_ticks_msec() + SELECTION_CHECK_MS
		"armed":
			_offer("preview")
			if bool(info.get("autocast", false)):
				_offer("autocast")
		"armed_use":
			_learn("preview")
			_step_done("buttons")
		"unqueue_shown":
			_offer("unqueue")
		"unqueued":
			_learn("unqueue")
		"info":
			_learn("hold")
			_step_done("hold")
		"placement_wait":
			_ctx.placing = true
			_ctx.line = bool(info.get("line", false))
			_ctx.twist_ghost = bool(info.get("twist", true))
			_offer("place")
			if not _ctx.line and _ctx.twist_ghost:
				_offer("twist")
		"placement_built":
			_learn("place")
			_step_done("buttons")
		"ghost_turned":
			_learn("twist")
		"aim_wait":
			_ctx.aiming = true
			_offer("aim")
		"aim_fired":
			_learn("aim")
		"camera":
			var kind := str(info.get("kind", "pan"))
			_camera_used[kind] = true
			_learn("camera")
			if _camera_used.has("pan") and (_camera_used.has("zoom") or _camera_used.has("twist")):
				_step_done("camera")
		_:
			printerr("TOUCH IOS-46 unknown tips event '%s'" % name)
			return
	_pump()


## the touch layer's context (every TOOLBAR_POLL_MS, and when ✓ / ✕ or the banner change): `ctx` game (a game is on screen), menu (a menu is over
## it), mouse (a mouse in use), placing (a ghost waits for ✓ / ✕), aiming (a power waits for its aim), armed (a previewed button); `avoid` the
## rectangles the panel keeps off; `top` the toolbar's or banner's bottom; `safe` the safe area
func set_context(ctx: Dictionary, avoid: Array, top: float, safe: Rect2) -> void:
	for k in ctx:
		_ctx[k] = ctx[k]
	_avoid = avoid
	_top = top
	_safe = safe
	_pump()
	if is_shown() and (_collides(rect()) or rect().position.y < maxf(_top, _safe.position.y)):
		_move_clear()


## something came onto the panel's spot after it showed (the power's banner, ✓ / ✕): it slides clear (MOVE_S, cubic ease-out; at once with Reduce Motion)
func _move_clear() -> void:
	var was := _panel.position
	_layout()
	var to := _panel.position
	if to == was:
		return
	if DisplayServer.accessibility_should_reduce_animation() == 1:
		return
	_panel.position = was
	if _tween != null:
		_tween.kill()
	_panel.modulate.a = 1.0
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "position", to, MOVE_S)


func _process(delta: float) -> void:
	if not _showable():
		return
	var now := Time.get_ticks_msec()
	if not _ctx.placing and not _ctx.aiming:
		_game_s += delta
	if _game_s >= CAMERA_AFTER_S and not _camera_used.has("pan") and not _learned.has("camera") and not _seen.has("camera") and not _queue.has("camera"):
		_offer("camera")
	if _check_ms > 0 and now >= _check_ms:
		_check_ms = 0
		_check_selection()
	if _current != "" and _until_ms > 0 and now >= _until_ms:
		_end_current("time")
	_pump()


## a world tap's (or box's) selection, read once the HUD took the click: something selected from nothing is "selected"; the same selection kept is an
## order ("ordered": the tap sent them); another selection is "selected" again
func _check_selection() -> void:
	var hud: Node = hud_getter.call() if hud_getter.is_valid() else null
	if hud == null or not hud.has_method("get_selection"):
		return
	var after: Array = hud.get_selection()
	if after.is_empty():
		return
	if not _sel_before.is_empty() and after == _sel_before:
		event("ordered")
	else:
		event("selected")


func _offer(id: String) -> void:
	if not _prompts_on() or style != STYLE_TIPS:
		return
	if _seen.has(id) or _learned.has(id) or _queue.has(id) or _current == id:
		return
	_queue.append(id)


func _learn(id: String) -> void:
	if _learned.has(id):
		return
	_learned[id] = true
	_queue.erase(id)
	_save()
	if _current == id:
		_end_current("learned")


func _step_done(id: String) -> void:
	if _guide_finished or _guide_done.has(id):
		return
	_guide_done[id] = true
	_save()
	if style == STYLE_GUIDE and _prompts_on() and _current == "guide:" + id:
		_flash_dot()
		_end_current("step done")
	if _guide_done.size() >= GUIDE.size():
		_guide_finished = true
		_save()
		if style == STYLE_GUIDE and _prompts_on():
			_show("guide:finished")


## Skip: the guide ends for good (its last line says where the help is)
func skip_guide() -> void:
	if _guide_finished:
		return
	_guide_finished = true
	_save()
	print("TOUCH IOS-46 guide skipped at %d of %d" % [_guide_done.size(), GUIDE.size()])
	_end_current("skipped")
	if _prompts_on() and style == STYLE_GUIDE:
		_show("guide:finished")


# ---------------------------------------------------------------------------------------------------------------------------------
# what the panel shows
# ---------------------------------------------------------------------------------------------------------------------------------
func _prompts_on() -> bool:
	return enabled and not suppressed and style != STYLE_CARD


func _showable() -> bool:
	return _prompts_on() and bool(_ctx.game) and not bool(_ctx.menu) and not bool(_ctx.mouse)


## a tip still fits the moment (the preview while a button is armed, the placement's while its ghost waits ...)
func _relevant(id: String) -> bool:
	match id:
		"preview", "autocast", "unqueue":
			return bool(_ctx.armed)
		"place":
			return bool(_ctx.placing)
		"twist":
			return bool(_ctx.placing) and not bool(_ctx.line) and bool(_ctx.twist_ghost)
		"aim":
			return bool(_ctx.aiming)
		"hold", "camera":
			return not bool(_ctx.placing) and not bool(_ctx.aiming)
		"guide:placing":
			return bool(_ctx.placing)
		"guide:aiming":
			return bool(_ctx.aiming)
	return true


## the next thing to show, or the current one to end
func _pump() -> void:
	if not _showable():
		if _current != "":
			_end_current("hidden")
		return
	if _current != "" and not _relevant(_current):
		_end_current("moment over")
	if style == STYLE_GUIDE:
		_pump_guide()
		return
	if _current != "":
		return
	while not _queue.is_empty():
		var id: String = _queue.pop_front()
		if _seen.has(id) or _learned.has(id):
			continue
		if not _relevant(id):
			continue  # its moment passed: offered again next time
		_show(id)
		return


func _pump_guide() -> void:
	if _guide_finished:
		return
	var want := ""
	if bool(_ctx.placing):
		want = "guide:placing"
	elif bool(_ctx.aiming):
		want = "guide:aiming"
	else:
		for s in GUIDE:
			if not _guide_done.has(s.id):
				want = "guide:" + str(s.id)
				break
	if want != "" and want != _current and _current != "guide:finished":
		_show(want)


func _show(what: String) -> void:
	var text := ""
	var glyph := ""
	var guide := what.begins_with("guide:")
	_head.visible = guide and what != "guide:finished" and what != "guide:placing" and what != "guide:aiming"
	_action.skip = guide and what != "guide:finished"
	_action.accessibility_name = "Skip the guide" if _action.skip else "Dismiss"
	_action.custom_minimum_size = Vector2((SKIP_W_PT if _action.skip else CELL_PT) * _px, CELL_PT * _px)
	_until_ms = 0
	if not guide:
		text = TIPS[what].text
		glyph = TIPS[what].glyph
		_seen[what] = true
		_save()
		_until_ms = Time.get_ticks_msec() + roundi(TIP_S * 1000.0)
	elif what == "guide:finished":
		text = GUIDE_FINISHED
		glyph = "help"
		_until_ms = Time.get_ticks_msec() + roundi(FINISHED_S * 1000.0)
	elif what == "guide:placing":
		text = GUIDE_PLACING.text
		glyph = GUIDE_PLACING.glyph
	elif what == "guide:aiming":
		text = GUIDE_AIMING.text
		glyph = GUIDE_AIMING.glyph
	else:
		var i := _guide_index(what.trim_prefix("guide:"))
		text = GUIDE[i].text
		glyph = GUIDE[i].glyph
		_head_label.text = "GETTING STARTED   %d of %d" % [i + 1, GUIDE.size()]
		_dots.count = GUIDE.size()
		_dots.done = _guide_done.size()
		_dots.queue_redraw()
	var fresh := _current == "" or not _visible
	_current = what
	_current_ms = Time.get_ticks_msec()
	_label.text = text
	_glyph.name_ = glyph
	_glyph.queue_redraw()
	_action.pressed = false
	_action.queue_redraw()
	shown_log.append(("tip:" + what) if not guide else what)
	print("TOUCH IOS-46 %s: %s" % [what if guide else "tip " + what, text])
	_layout()
	_appear(fresh)


func _guide_index(id: String) -> int:
	for i in GUIDE.size():
		if GUIDE[i].id == id:
			return i
	return 0


## the panel goes: `why` for the log; a tip hidden by its moment ending before MIN_READ_S is not counted as seen (it comes back next time)
func _end_current(why: String) -> void:
	if _current == "":
		return
	var was := _current
	if not was.begins_with("guide:") and why in ["moment over", "hidden"] and Time.get_ticks_msec() - _current_ms < roundi(MIN_READ_S * 1000.0):
		_seen.erase(was)
		_save()
	_current = ""
	_until_ms = 0
	_hide()


## the panel's ✕ (a tip: dismissed, seen) or Skip (the guide)
func dismiss() -> void:
	if _current == "":
		return
	if _action.skip:
		skip_guide()
		return
	print("TOUCH IOS-46 %s dismissed" % _current)
	_end_current("dismissed")


# ---------------------------------------------------------------------------------------------------------------------------------
# layout, motion, hit tests
# ---------------------------------------------------------------------------------------------------------------------------------
func _layout() -> void:
	var safe := _safe if _safe.has_area() else get_viewport().get_visible_rect()
	var chrome := (PAD_X_PT * 0.75 + 2.0 + GLYPH_PT + 10.0 + 10.0) * _px + _action.custom_minimum_size.x + 2.0
	var width := minf(MAX_W_PT * _px, safe.size.x - 2.0 * MARGIN_PT * _px)
	# the panel hugs a one-line text (a short tip is a short pill); the guide keeps its width from step to step (no jumping edge)
	var font := _label.get_theme_font("font")
	var one_line := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(TEXT_PT * _px)).x + chrome + 4.0 * _px
	if not _current.begins_with("guide:") and one_line < width:
		width = ceilf(one_line)
	var text_w := width - chrome
	_label.custom_minimum_size = Vector2(maxf(40.0, text_w), 0)
	_label.size = Vector2(_label.custom_minimum_size.x, 0)  # an autowrapped label measures its lines at its width now
	_label.update_minimum_size()
	_panel.size = Vector2(width, 0)
	_panel.reset_size()
	_panel.size = Vector2(width, _panel.get_combined_minimum_size().y)
	var y := maxf(_top, safe.position.y) + TOP_PT * _px
	var xs := [safe.position.x + (safe.size.x - width) * 0.5, safe.position.x + MARGIN_PT * _px, safe.end.x - MARGIN_PT * _px - width]
	var at := Vector2(xs[0], y)
	var placed := false
	for x in xs:
		var r := Rect2(Vector2(x, y), _panel.size)
		if not _collides(r):
			at = r.position
			placed = true
			break
	if not placed:
		# every top spot touches ✓ / ✕ (a ghost waits right under the banner): under the lowest thing it touches, if that still fits in the upper half
		var below := y
		for a in _avoid:
			if Rect2(Vector2(xs[0], y), _panel.size).grow(AVOID_PT * _px).intersects(a):
				below = maxf(below, a.end.y + AVOID_PT * _px)
		if below + _panel.size.y <= safe.position.y + safe.size.y * 0.5:
			at = Vector2(xs[0], below)
	_panel.position = at.round()


func _collides(r: Rect2) -> bool:
	for a in _avoid:
		if a is Rect2 and a.has_area() and r.grow(AVOID_PT * _px).intersects(a):
			return true
	return false


func _appear(fresh: bool) -> void:
	_visible = true
	_panel.visible = true
	if _tween != null:
		_tween.kill()
	var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
	var target := _panel.position
	if not fresh:
		# a new step in the shown panel: its text cross-fades in place (no drop)
		_panel.modulate.a = 0.55
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_panel, "modulate:a", 1.0, APPEAR_S)
		return
	_panel.modulate.a = 0.0
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "modulate:a", 1.0, APPEAR_S)
	if not reduce:
		_panel.position.y -= DROP_PT * _px
		_tween.tween_property(_panel, "position:y", target.y, APPEAR_S)


func _hide() -> void:
	if not _visible:
		return
	_visible = false
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_panel, "modulate:a", 0.0, HIDE_S)
	_tween.tween_callback(func() -> void: _panel.visible = _visible)


func _flash_dot() -> void:
	_dots.done = _guide_done.size()
	if DisplayServer.accessibility_should_reduce_animation() == 1:
		_dots.queue_redraw()
		return
	if _dot_tween != null:
		_dot_tween.kill()
	_dot_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_dot_tween.tween_method(func(v: float) -> void:
		_dots.flash = v
		_dots.queue_redraw(), 1.0, 0.0, 0.3)


func is_shown() -> bool:
	return _visible and _current != ""


func current() -> String:
	return _current


## the panel's rectangle (window pixels; Rect2() while hidden)
func rect() -> Rect2:
	return Rect2(_panel.position, _panel.size) if is_shown() else Rect2()


## a finger at `at`: "action" on the ✕ / Skip cell, "panel" elsewhere on the panel, "" off it
func hit(at: Vector2) -> String:
	if not is_shown():
		return ""
	var cell := Rect2(_action.global_position, _action.size).grow(4.0 * _px)
	if cell.has_point(at):
		return "action"
	return "panel" if rect().has_point(at) else ""


func set_pressed(on: bool) -> void:
	if _action.pressed != on:
		_action.pressed = on
		_action.queue_redraw()


## for the tests and the screenshots: { shown, current, text, rect, queue, seen, learned, guide_done, guide_finished, style, enabled }
func state() -> Dictionary:
	return {"shown": is_shown(), "current": _current, "text": _label.text if _label != null else "", "rect": rect(), "queue": _queue.duplicate(),
		"seen": _seen.keys(), "learned": _learned.keys(), "guide_done": _guide_done.keys(), "guide_finished": _guide_finished, "style": style,
		"enabled": enabled}
