extends CanvasLayer
## Lane IOS-37 (the owner's decision, 2026-11-05: "a top-edge strip"): the touch command toolbar. The idea is daisyhasacat/openbfme-godot's classic-HUD
## touch toolbar (her godot/scripts/touch_toolbar.gd, GPL-3.0: Deselect, Stop, Menu, Attack Move, Select Army, Home Base, Last Event, "the same input path
## as the keyboard"); no code copied: hers is a panel of text buttons, this a strip of round icon buttons with control groups and hold-for-help.
##
## The touch layer (touch_controls.gd) owns the fingers: it asks hit() as a finger comes down and calls press / hold / release; this layer draws the strip,
## lays it out, shows the help line and sends each command the way the keyboard does (activate()). It takes no input of its own (mouse_filter IGNORE).
##
##   Select army ... CommandMap SELECT_ALL (Q)            Attack move ... the selection's Attack Move button's hotkey (A: a command bar hotkey in RotWK)
##   Deselect ...... InGameUI::deselectAll (no key)       Stop .......... CommandMap STOP (S)
##   Home base ..... CommandMap VIEW_HOME_BASE (H)         Last event .... CommandMap VIEW_LAST_RADAR_EVENT (Space)
##   Groups ........ opens / closes the control groups' row under the strip: 1 .. 9, 0
##   Menu .......... Esc (game.gd's quit menu toggle)
##   a group, tap .. CommandMap SELECT_TEAMn (n): its units selected (the game's own second press of the key centres the view)
##   a group, hold . CommandMap CREATE_TEAMn (Ctrl+n): the group made from the selection; a gold ring fills while held (HOLD_MS) and flashes when made
## Every key is read from the game's CommandMap (InGameHudNode.get_command_map) and pressed as InputEventKeys (with their modifier keys around them), the
## path a hardware keyboard's keys take, so a remapped key follows. A hold on any other button shows what it does and presses nothing (IOS-21).
##
## Look (IOS-12's tokens, as ✓ / ✕): DISC_PT round dark discs with a hairline gold ring and a light glyph drawn here (no game art), CELL_PT touch cells
## (the 44 pt minimum), grouped by meaning with GROUP_GAP_PT between the groups. States: normal; pressed (the disc lightens, the ring and the glyph turn
## gold, 0.94 scale at once, back in PRESS_S); disabled (glyph and ring at 30 %: Deselect and Stop with nothing selected, Attack move when the selection
## has no Attack Move button); on (Groups while its row is open: the ring and the glyph gold).
## Place: the top edge inside the safe area, from its left; right of the frame-rate readout when that shows (its room, fps_overlay.gd), and within the left
## WIDTH_SHARE of the safe area's width, clear of the game's messages (right-aligned at the top right) and the side bar (right edge): a group that would
## reach past it starts a second row (a portrait screen: two rows; landscape: one), and the groups' row wraps the same way. The help line goes under the
## whole strip. No layout shift: the strip is an overlay and keeps its place.
## Motion: the strip fades in over APPEAR_S when a game shows it; the help line fades in over TIP_S (cubic ease-out); Reduce Motion: no scale, fades only.

const CELL_PT := 44.0           # a button's touch cell
const DISC_PT := 40.0           # its disc
const GAP_PT := 2.0             # between cells of a group (6 pt between discs)
const GROUP_GAP_PT := 10.0      # between groups
const MARGIN_PT := 6.0          # from the safe area's left edge
const TOP_PT := 4.0             # from the safe area's top edge
const ROW_GAP_PT := 4.0         # between the strip's rows and the groups' rows
const WIDTH_SHARE := 0.6        # the strip keeps to this much of the safe area's width, from its left (the messages' corner is the rest)
const RING_PT := 1.5
const GLYPH_PT := 2.5
const TIP_PT := 13.0            # the help line's text
const TIP_MAX_PT := 320.0       # its widest line before it wraps
const HOLD_MS := 450            # a group's hold to make it (touch_controls.gd LONG_PRESS_MS)
const PRESS_S := 0.15
const TIP_S := 0.15
const APPEAR_S := 0.2
const PRESSED_SCALE := 0.94

const C_DISC := Color(0.06, 0.06, 0.07, 0.82)
const C_DISC_PRESSED := Color(0.17, 0.15, 0.11, 0.94)
const C_SHADOW := Color(0, 0, 0, 0.3)
const C_ACCENT := Color("c8a25a")
const C_RING := Color(0.784, 0.635, 0.353, 0.45)
const C_GLYPH := Color(1, 1, 1, 0.86)
const C_DIM := 0.3              # a disabled button's alpha for the ring and the glyph
const C_TIP_TEXT := Color(0.94, 0.91, 0.84)

## the strip: [id, label, help]; "|" a group break
const STRIP := [
	["army", "Select army", "Selects all your units."],
	["deselect", "Deselect", "Clears the selection."],
	"|",
	["attack", "Attack move", "Then tap the ground: the selection moves there and fights what it meets on the way."],
	["stop", "Stop", "The selection stops what it is doing."],
	"|",
	["base", "Home base", "Shows your fortress."],
	["event", "Last event", "Shows where the last alert happened."],
	"|",
	["groups", "Control groups", "Shows the groups 1 to 0. Tap a number to select its units; hold it to make the group from your selection."],
	["menu", "Menu", "Opens the game menu."],
]
const GROUPS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
## the CommandMap meta each button presses (the groups': SELECT_TEAMn / CREATE_TEAMn)
const METAS := {"army": "SELECT_ALL", "stop": "STOP", "base": "VIEW_HOME_BASE", "event": "VIEW_LAST_RADAR_EVENT"}
## CommandMap key names (MetaMap::keyName) -> Godot keys, for the names that are not a letter, a digit or F1 .. F12
const KEY_NAMES := {"KEY_ESC": KEY_ESCAPE, "KEY_SPACE": KEY_SPACE, "KEY_ENTER": KEY_ENTER, "KEY_TAB": KEY_TAB, "KEY_BACKSPACE": KEY_BACKSPACE,
	"KEY_DEL": KEY_DELETE, "KEY_INS": KEY_INSERT, "KEY_HOME": KEY_HOME, "KEY_END": KEY_END, "KEY_PGUP": KEY_PAGEUP, "KEY_PGDN": KEY_PAGEDOWN,
	"KEY_UP": KEY_UP, "KEY_DOWN": KEY_DOWN, "KEY_LEFT": KEY_LEFT, "KEY_RIGHT": KEY_RIGHT, "KEY_MINUS": KEY_MINUS, "KEY_EQUAL": KEY_EQUAL,
	"KEY_COMMA": KEY_COMMA, "KEY_PERIOD": KEY_PERIOD, "KEY_SLASH": KEY_SLASH, "KEY_SEMICOLON": KEY_SEMICOLON, "KEY_APOSTROPHE": KEY_APOSTROPHE,
	"KEY_TICK": KEY_QUOTELEFT, "KEY_LBRACKET": KEY_BRACKETLEFT, "KEY_RBRACKET": KEY_BRACKETRIGHT, "KEY_BACKSLASH": KEY_BACKSLASH,
	"KEY_KPSTAR": KEY_KP_MULTIPLY, "KEY_KPMINUS": KEY_KP_SUBTRACT, "KEY_KPPLUS": KEY_KP_ADD, "KEY_KPDOT": KEY_KP_PERIOD, "KEY_KPENTER": KEY_KP_ENTER,
	"KEY_KPSLASH": KEY_KP_DIVIDE}


## one round button
class Cell:
	extends Control
	var id := ""
	var px := 1.0
	var pressed := false
	var enabled := true
	var on := false
	var progress := -1.0        # a group's hold, 0 .. 1 (-1 none)
	var flash := 0.0            # a group just made: the ring's flash, 1 -> 0
	var text := ""              # a group's number

	func _draw() -> void:
		var c := size * 0.5
		var r := DISC_PT * 0.5 * px
		var a := 1.0 if enabled else C_DIM
		draw_circle(c, r + 1.5 * px, C_SHADOW, true, -1.0, true)
		draw_circle(c, r, C_DISC_PRESSED if pressed else C_DISC, true, -1.0, true)
		var gold := pressed or on
		var ring: Color = C_ACCENT if gold else C_RING
		ring.a *= a
		draw_arc(c, r - RING_PT * px * 0.5, 0.0, TAU, 48, ring, RING_PT * px, true)
		if flash > 0.0:
			draw_arc(c, r + 2.0 * px, 0.0, TAU, 48, Color(C_ACCENT, flash), 3.0 * px, true)
		if progress >= 0.0:
			draw_arc(c, r - 1.5 * px, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 48, C_ACCENT, 3.0 * px, true)
		var ink: Color = C_ACCENT if gold else C_GLYPH
		ink.a *= a
		if text != "":
			var font := ThemeDB.fallback_font
			var fs := int(round(17.0 * px))
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, c + Vector2(-w * 0.5, font.get_ascent(fs) * 0.5 - 1.0 * px), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
			return
		_glyph(c, r * 0.46, ink, GLYPH_PT * px)

	## the vector glyphs (`g`: the glyph's half size)
	func _glyph(c: Vector2, g: float, ink: Color, w: float) -> void:
		match id:
			"army":
				# three figures: a head and shoulders each, the middle one in front
				for f in [[Vector2(-0.62, 0.12), 0.8], [Vector2(0.62, 0.12), 0.8], [Vector2(0.0, -0.05), 1.0]]:
					var o: Vector2 = c + f[0] * g
					var k: float = f[1]
					draw_circle(o + Vector2(0, -0.42 * g * k), 0.24 * g * k, ink, true, -1.0, true)
					draw_arc(o + Vector2(0, 0.55 * g * k), 0.48 * g * k, PI, TAU, 16, ink, w * 0.85, true)
			"deselect":
				# a selection box's corners, struck through
				var k := 0.82 * g
				var t := 0.38 * g
				for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var p: Vector2 = c + s * k
					draw_polyline(PackedVector2Array([p - Vector2(0, s.y * t), p, p - Vector2(s.x * t, 0)]), ink, w * 0.8, true)
				draw_line(c + Vector2(-0.5, 0.5) * g, c + Vector2(0.5, -0.5) * g, ink, w, true)
			"attack":
				# a sword pointing up and right (its blade, its guard, its grip)
				var tip := c + Vector2(0.78, -0.78) * g
				var guard := c + Vector2(-0.38, 0.38) * g
				draw_line(guard, tip, ink, w, true)
				draw_line(guard + Vector2(-0.34, -0.34) * g, guard + Vector2(0.34, 0.34) * g, ink, w, true)
				draw_line(guard, c + Vector2(-0.78, 0.78) * g, ink, w * 1.2, true)
			"stop":
				var k := 0.62 * g
				draw_rect(Rect2(c - Vector2(k, k), Vector2(k, k) * 2.0), ink, true)
			"base":
				# a keep: the tower with three merlons and a gate
				var l := -0.7 * g
				var rr := 0.7 * g
				var top := -0.45 * g
				var bot := 0.8 * g
				var m := 0.28 * g
				var pts := PackedVector2Array([Vector2(l, bot), Vector2(l, top - m), Vector2(l + 0.47 * g, top - m), Vector2(l + 0.47 * g, top),
					Vector2(-0.23 * g, top), Vector2(-0.23 * g, top - m), Vector2(0.23 * g, top - m), Vector2(0.23 * g, top), Vector2(rr - 0.47 * g, top),
					Vector2(rr - 0.47 * g, top - m), Vector2(rr, top - m), Vector2(rr, bot), Vector2(0.22 * g, bot), Vector2(0.22 * g, 0.38 * g),
					Vector2(-0.22 * g, 0.38 * g), Vector2(-0.22 * g, bot), Vector2(l, bot)])
				for i in pts.size():
					pts[i] += c
				draw_polyline(pts, ink, w * 0.85, true)
			"event":
				# a ping: a dot and two waves
				var o := c + Vector2(-0.45, 0.45) * g
				draw_circle(o, 0.2 * g, ink, true, -1.0, true)
				draw_arc(o, 0.62 * g, -PI * 0.5, 0.0, 16, ink, w * 0.85, true)
				draw_arc(o, 1.08 * g, -PI * 0.5, 0.0, 20, ink, w * 0.85, true)
			"groups":
				# four squares
				var s := 0.66 * g
				var h := 0.12 * g
				for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
					var o: Vector2 = c + q * (s * 0.5 + h)
					draw_rect(Rect2(o - Vector2(s, s) * 0.5, Vector2(s, s)), ink, false, w * 0.75)
			"menu":
				for y in [-0.5, 0.0, 0.5]:
					draw_line(c + Vector2(-0.68 * g, y * g), c + Vector2(0.68 * g, y * g), ink, w, true)


var _px := 1.0
var _cells := {}              # id -> Cell (the strip's and the groups')
var _order: Array = []        # the strip's ids, in order
var _row: Control             # the groups' row (shown while Groups is on)
var _strip: Control
var _tip: PanelContainer
var _tip_label: Label
var _tip_tween: Tween = null
var _tip_for := ""
var _appear: Tween = null
var _shown := false
var _drawer := false
var _keys := {}               # meta name -> {"key": Godot Key, "ctrl", "shift", "alt", "name": the CommandMap key name}
var hud: Node = null          # the game's InGameHudNode (touch_controls.gd sets it)
var sent: Array = []          # the commands sent, for the self-test: [id, what]


func _init() -> void:
	layer = 108  # over the game and its HUD; under the armed ring (109), ✓ / ✕ (110) and the frame-rate readout (120)


func setup(px_per_pt: float) -> void:
	_px = px_per_pt
	_strip = Control.new()
	_strip.name = "CommandToolbar"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.visible = false
	add_child(_strip)
	_row = Control.new()
	_row.name = "ControlGroups"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.visible = false
	_strip.add_child(_row)
	for item in STRIP:
		if item is String:
			continue
		_order.append(item[0])
		_cells[item[0]] = _cell(item[0], item[1], _strip)
	for n in GROUPS:
		var c := _cell("group" + n, "Control group " + n, _row)
		c.text = n
		_cells["group" + n] = c
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.07, 0.92)
	style.border_color = Color(0.784, 0.635, 0.353, 0.6)
	style.set_border_width_all(maxi(1, roundi(1.0 * _px)))
	style.set_corner_radius_all(roundi(8.0 * _px))
	style.content_margin_left = 10.0 * _px
	style.content_margin_right = 10.0 * _px
	style.content_margin_top = 6.0 * _px
	style.content_margin_bottom = 7.0 * _px
	_tip.add_theme_stylebox_override("panel", style)
	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", roundi(TIP_PT * _px))
	_tip_label.add_theme_color_override("font_color", C_TIP_TEXT)
	_tip.add_child(_tip_label)
	_tip.visible = false
	add_child(_tip)


func _cell(id: String, label: String, parent: Control) -> Cell:
	var c := Cell.new()
	c.id = id
	c.px = _px
	c.name = "Cell_" + id
	c.size = Vector2.ONE * CELL_PT * _px
	c.pivot_offset = c.size * 0.5
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.focus_mode = Control.FOCUS_NONE
	c.accessibility_name = label
	parent.add_child(c)
	return c


## the strip at the top of `safe` (window pixels), from `left` (a pixel past the frame-rate readout's room, or the safe area's left), wrapped at its groups
## to keep within WIDTH_SHARE of the safe width; the groups' row under it, wrapped the same way
func layout(safe: Rect2, left: float) -> void:
	var x0 := maxf(safe.position.x + MARGIN_PT * _px, left)
	var right := maxf(safe.position.x + safe.size.x * WIDTH_SHARE, x0 + 4.0 * (CELL_PT + GAP_PT) * _px)  # at least one group of two and a half
	var cell := CELL_PT * _px
	var step := cell + GAP_PT * _px
	var y := safe.position.y + TOP_PT * _px
	var x := x0
	var groups: Array = [[]]
	for item in STRIP:
		if item is String:
			groups.append([])
		else:
			groups[-1].append(item[0])
	for g in groups:
		var w: float = g.size() * cell + (g.size() - 1) * GAP_PT * _px
		if x > x0 and x + w > right:
			x = x0  # this group starts the next row
			y += cell + ROW_GAP_PT * _px
		for id in g:
			(_cells[id] as Cell).position = Vector2(x, y)
			x += step
		x += (GROUP_GAP_PT - GAP_PT) * _px
	# the groups' row(s) under the strip, as many numbers a row as fit in the same width
	var per_row := maxi(1, int(floor((right - x0 + GAP_PT * _px) / step)))
	var ry := y + cell + ROW_GAP_PT * _px
	for i in GROUPS.size():
		var c: Cell = _cells["group" + GROUPS[i]]
		c.position = Vector2(x0 + (i % per_row) * step, ry + (i / per_row) * (cell + ROW_GAP_PT * _px))


## the strip's rectangle (the groups' row too while it shows), window pixels; Rect2() while hidden
func rect() -> Rect2:
	if not _shown:
		return Rect2()
	var r := Rect2()
	for id in _cells:
		var c: Cell = _cells[id]
		if not c.is_visible_in_tree():
			continue
		var cr := Rect2(c.position, c.size)
		r = cr if not r.has_area() else r.merge(cr)
	return r


func set_shown(on: bool) -> void:
	if on == _shown:
		return
	_shown = on
	if _appear != null:
		_appear.kill()
		_appear = null
	if not on:
		_strip.visible = false
		hide_tip()
		return
	_strip.visible = true
	_strip.modulate.a = 0.0
	_appear = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_appear.tween_property(_strip, "modulate:a", 1.0, APPEAR_S)


func is_shown() -> bool:
	return _shown


## the button a finger at `at` is on ("" none): the touch cells (CELL_PT squares) of the shown buttons
func hit(at: Vector2) -> String:
	if not _shown:
		return ""
	for id in _cells:
		var c: Cell = _cells[id]
		if c.is_visible_in_tree() and Rect2(c.position, c.size).has_point(at):
			return id
	return ""


func set_pressed(id: String) -> void:
	for k in _cells:
		var c: Cell = _cells[k]
		var p: bool = k == id
		if c.pressed == p:
			continue
		c.pressed = p
		c.queue_redraw()
		var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
		if p:
			c.scale = Vector2.ONE * (1.0 if reduce else PRESSED_SCALE)
		elif not reduce:
			create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(c, "scale", Vector2.ONE, PRESS_S)
		else:
			c.scale = Vector2.ONE


## a group's hold, 0 .. 1 (-1: none)
func set_progress(id: String, t: float) -> void:
	if _cells.has(id):
		var c: Cell = _cells[id]
		c.progress = t
		c.queue_redraw()


func set_progress_all(t: float) -> void:
	for id in _cells:
		if (_cells[id] as Cell).progress != t:
			set_progress(id, t)


func is_group(id: String) -> bool:
	return id.begins_with("group")


## the disabled states from the game, about four times a second (touch_controls.gd): Deselect and Stop need a selection, Attack move the selection's
## Attack Move button
func refresh() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	var selected: bool = hud.has_method("get_selection") and not (hud.get_selection() as Array).is_empty()
	var attack: Dictionary = hud.command_hotkey("ATTACK_MOVE") if hud.has_method("command_hotkey") else {}
	_set_enabled("deselect", selected)
	_set_enabled("stop", selected)
	_set_enabled("attack", bool(attack.get("found", false)) and bool(attack.get("enabled", false)) and str(attack.get("key", "")) != "")


func _set_enabled(id: String, on: bool) -> void:
	var c: Cell = _cells[id]
	if c.enabled != on:
		c.enabled = on
		c.queue_redraw()


func is_enabled(id: String) -> bool:
	return _cells.has(id) and (_cells[id] as Cell).enabled


## a tap on `id`: its command, the keyboard's way. False when it did nothing (a disabled button, a key the CommandMap does not have)
func activate(id: String) -> bool:
	if not is_enabled(id):
		return false
	match id:
		"groups":
			_drawer = not _drawer
			_row.visible = _drawer
			var c: Cell = _cells["groups"]
			c.on = _drawer
			c.queue_redraw()
			sent.append([id, "open" if _drawer else "closed"])
			return true
		"menu":
			_press_key(KEY_ESCAPE, false, false, false)
			sent.append([id, "KEY_ESC"])
			return true
		"deselect":
			var ok: bool = hud != null and hud.has_method("deselect_all") and hud.deselect_all()
			sent.append([id, "deselect_all %s" % ok])
			return ok
		"attack":
			var hk: Dictionary = hud.command_hotkey("ATTACK_MOVE") if hud != null and hud.has_method("command_hotkey") else {}
			var letter := str(hk.get("key", "")).to_upper()
			var key := OS.find_keycode_from_string(letter) if letter.length() == 1 else KEY_NONE
			if key == KEY_NONE:
				return false
			_press_key(key, false, false, false)
			sent.append([id, letter])
			return true
	if is_group(id):
		return _meta(id, "SELECT_TEAM" + id.trim_prefix("group"))
	return _meta(id, str(METAS.get(id, "")))


## a hold on group `id` came to HOLD_MS: CREATE_TEAMn (the group made from the selection). False with nothing selected (nothing is sent)
func assign(id: String) -> bool:
	var n := id.trim_prefix("group")
	var selected: bool = hud != null and hud.has_method("get_selection") and not (hud.get_selection() as Array).is_empty()
	if not selected:
		show_tip(id, "Select units first, then hold %s to make them group %s." % [n, n])
		return false
	var ok := _meta(id, "CREATE_TEAM" + n)
	show_tip(id, "Group %s: made from your selection. Tap %s to select it." % [n, n] if ok else "Group %s: no key for it in the game's hot keys." % n)
	var c: Cell = _cells[id]
	c.flash = 1.0
	c.queue_redraw()
	var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_method(func(v: float) -> void:
		c.flash = v
		c.queue_redraw(), 1.0, 0.0, 0.1 if reduce else 0.4)
	return ok


## the help line of `id` under it (its label, its key, what it does), or `text`
func show_tip(id: String, text := "") -> void:
	if not _cells.has(id):
		return
	if text == "":
		text = _help_of(id)
	_tip_label.text = text
	_tip_for = id
	var view := get_viewport().get_visible_rect()
	# one line when it fits in TIP_MAX_PT (or the view), else wrapped at that width: the label's size is set, never left to the wrap (a wrapping label
	# with no width asks for a line per word)
	var font := _tip_label.get_theme_font("font")
	var fs := _tip_label.get_theme_font_size("font_size")
	var room := minf(TIP_MAX_PT * _px, view.size.x - 2.0 * MARGIN_PT * _px - 20.0 * _px)
	var one := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if one <= room:
		_tip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_tip_label.custom_minimum_size = Vector2(ceilf(one) + 1.0, 0)
	else:
		_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, room, fs).y
		_tip_label.custom_minimum_size = Vector2(room, ceilf(h))
	_tip.size = _tip.get_combined_minimum_size()
	var c: Cell = _cells[id]
	var below := rect().end.y + 6.0 * _px  # under the whole strip (its rows and the groups' rows): it covers no button
	var x := c.position.x + c.size.x * 0.5 - _tip.size.x * 0.5
	x = clampf(x, view.position.x + MARGIN_PT * _px, view.end.x - _tip.size.x - MARGIN_PT * _px)
	_tip.position = Vector2(x, below)
	_tip.visible = true
	if _tip_tween != null:
		_tip_tween.kill()
	_tip.modulate.a = 0.0
	_tip_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tip_tween.tween_property(_tip, "modulate:a", 1.0, TIP_S)


func hide_tip(after := 0.0) -> void:
	if _tip_tween != null:
		_tip_tween.kill()
		_tip_tween = null
	if not _tip.visible:
		return
	_tip_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if after > 0.0:
		_tip_tween.tween_interval(after)
	_tip_tween.tween_property(_tip, "modulate:a", 0.0, TIP_S)
	_tip_tween.tween_callback(func() -> void:
		_tip.visible = false
		_tip_for = "")


func _help_of(id: String) -> String:
	if is_group(id):
		var n := id.trim_prefix("group")
		return "Group %s: tap to select its units, hold to make it from your selection%s." % [n, _key_text("SELECT_TEAM" + n)]
	for item in STRIP:
		if item is Array and item[0] == id:
			var key := ""
			match id:
				"menu":
					key = " (Esc)"
				"attack":
					var hk: Dictionary = hud.command_hotkey("ATTACK_MOVE") if hud != null and hud.has_method("command_hotkey") else {}
					var letter := str(hk.get("key", "")).to_upper()
					key = " (%s)" % letter if letter != "" else ""
				_:
					key = _key_text(str(METAS.get(id, "")))
			var help: String = item[2]
			if id == "attack" and not is_enabled("attack"):
				help = "Select units that can attack-move first. " + help
			return "%s%s. %s" % [item[1], key, help]
	return ""


## " (Q)": the CommandMap key of `meta`, "" without one
func _key_text(meta: String) -> String:
	var k: Dictionary = _key_of(meta)
	if k.is_empty():
		return ""
	var name := str(k.name).trim_prefix("KEY_")
	name = {"ESC": "Esc", "SPACE": "Space"}.get(name, name)
	return " (%s%s%s%s)" % ["Ctrl+" if k.ctrl else "", "Shift+" if k.shift else "", "Alt+" if k.alt else "", name]


## the CommandMap record of `meta` usable in a game with the DOWN transition: {key (Godot), ctrl, shift, alt, name}, {} none
func _key_of(meta: String) -> Dictionary:
	if _keys.is_empty() and hud != null and hud.has_method("get_command_map"):
		for r in hud.get_command_map():
			var rec: Dictionary = r
			var m := str(rec.get("name", ""))
			if _keys.has(m) or not bool(rec.get("game", false)) or int(rec.get("transition", -1)) != 0:
				continue
			var key := _godot_key(str(rec.get("key", "")))
			if key == KEY_NONE:
				continue
			_keys[m] = {"key": key, "ctrl": bool(rec.ctrl), "shift": bool(rec.shift), "alt": bool(rec.alt), "name": str(rec.key)}
	return _keys.get(meta, {})


static func _godot_key(name: String) -> Key:
	if KEY_NAMES.has(name):
		return KEY_NAMES[name]
	var rest := name.trim_prefix("KEY_")
	if name.begins_with("KEY_KP") and rest.length() == 3 and rest[2].is_valid_int():
		return (KEY_KP_0 + rest[2].to_int()) as Key
	if rest.length() == 1 or (rest.begins_with("F") and rest.substr(1).is_valid_int()):
		return OS.find_keycode_from_string(rest)
	return KEY_NONE


func _meta(id: String, meta: String) -> bool:
	var k: Dictionary = _key_of(meta)
	if k.is_empty():
		sent.append([id, meta + " (no key)"])
		return false
	_press_key(k.key, k.ctrl, k.shift, k.alt)
	sent.append([id, meta])
	return true


## a key pressed and released as a keyboard does it: its modifier keys down first and up last; the HUD reads the physical key (InGameHudNode::_input)
func _press_key(key: Key, ctrl: bool, shift: bool, alt: bool) -> void:
	var mods: Array = []
	if ctrl:
		mods.append(KEY_CTRL)
	if shift:
		mods.append(KEY_SHIFT)
	if alt:
		mods.append(KEY_ALT)
	var held := {"ctrl": false, "shift": false, "alt": false}
	for m in mods:
		held[{KEY_CTRL: "ctrl", KEY_SHIFT: "shift", KEY_ALT: "alt"}[m]] = true
		_key_event(m, true, held)
	_key_event(key, true, held)
	_key_event(key, false, held)
	mods.reverse()
	for m in mods:
		held[{KEY_CTRL: "ctrl", KEY_SHIFT: "shift", KEY_ALT: "alt"}[m]] = false
		_key_event(m, false, held)


func _key_event(key: Key, down: bool, held: Dictionary) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.key_label = key
	e.pressed = down
	e.ctrl_pressed = held.ctrl
	e.shift_pressed = held.shift
	e.alt_pressed = held.alt
	Input.parse_input_event(e)


## the self-test's view: { shown, drawer, rect, buttons: {id: {rect, enabled, pressed, on}}, tip, sent }
func state() -> Dictionary:
	var buttons := {}
	for id in _cells:
		var c: Cell = _cells[id]
		buttons[id] = {"rect": Rect2(c.position, c.size), "visible": c.is_visible_in_tree(), "enabled": c.enabled, "pressed": c.pressed, "on": c.on}
	return {"shown": _shown, "drawer": _drawer, "rect": rect(), "buttons": buttons, "tip": _tip_label.text if _tip.visible else "", "sent": sent.duplicate()}
