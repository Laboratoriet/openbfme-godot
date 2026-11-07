extends CanvasLayer
## Lane IOS-46 (c) (a PROTOTYPE for the owner's choice): the "Touch controls" card, every gesture on one page with a small picture of it
## (touch_glyphs.gd, drawn here: nothing from the game's files). Reached from Options > Touch > Help > "Touch controls" and from the pause menu (its
## "Touch controls" button at the bottom right of the safe area while the quit menu is over a game), with every help style.
##
## The lines follow the Touch tab's switches in effect (touch_controls.gd switches()): with "One finger drag" on Move the view, the drag's line says so.
## Modal while open: the touch layer gives it every finger; its ✕ or a tap outside the card closes it (a mouse click there too). It never opens by
## itself, so it never blocks play.
##
## Layout: centred in the safe area, at most CARD_MAX_PT wide; two columns where a column has COLUMN_MIN_PT, else one; a card taller than the safe
## area scrolls (a finger drag on it). Motion: the dim fades in and the card rises RISE_PT into place over APPEAR_S (cubic ease-out); out over HIDE_S.
## Reduce Motion: fades only.

const TouchGlyphs := preload("res://scripts/touch/touch_glyphs.gd")

const CARD_MAX_PT := 760.0
const COLUMN_MIN_PT := 300.0
const MARGIN_PT := 16.0        # from the safe area's edges
const PAD_PT := 20.0           # inside the card
const CELL_PT := 44.0          # the ✕ cell and the entry button's height (iOS's minimum target)
const GLYPH_PT := 44.0
const TITLE_PT := 21.0
const SUB_PT := 13.0
const NAME_PT := 15.0
const LINE_PT := 13.0
const ROW_GAP_PT := 12.0
const COL_GAP_PT := 22.0
const APPEAR_S := 0.24
const HIDE_S := 0.16
const RISE_PT := 12.0

# IOS-12's tokens (touch_targeting.gd, placement_confirm.gd)
const C_DIM := Color(0, 0, 0, 0.62)
const C_SURFACE := Color(0.06, 0.06, 0.07, 0.97)
const C_BORDER := Color(0.784, 0.635, 0.353, 0.6)
const C_ACCENT := Color("c8a25a")
const C_TEXT := Color(0.94, 0.91, 0.84)
const C_HINT := Color(0.94, 0.91, 0.84, 0.72)
const C_RULE := Color(0.784, 0.635, 0.353, 0.22)
const C_DISC := Color(0.06, 0.06, 0.07, 0.88)
const C_DISC_PRESSED := Color(0.17, 0.15, 0.11, 0.94)
const C_RING_2 := Color(0.784, 0.635, 0.353, 0.4)
const C_GLYPH_2 := Color(1, 1, 1, 0.82)


class Glyph:
	extends Control
	var name_ := ""

	func _draw() -> void:
		# a quiet tile under the picture, so the pictures read as a set
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, Color(0.784, 0.635, 0.353, 0.08), true, -1.0, true)
		TouchGlyphs.draw(self, name_, size * 0.5, minf(size.x, size.y) * 0.8, C_ACCENT)


class Close:
	extends Control
	var px := 1.0
	var pressed := false

	func _draw() -> void:
		var c := size * 0.5
		var r := 16.0 * px
		draw_circle(c, r, C_DISC_PRESSED if pressed else C_DISC, true, -1.0, true)
		draw_arc(c, r - 0.75 * px, 0.0, TAU, 36, C_RING_2, 1.5 * px, true)
		var k := r * 0.36
		draw_line(c + Vector2(-k, -k), c + Vector2(k, k), C_GLYPH_2, 2.5 * px, true)
		draw_line(c + Vector2(-k, k), c + Vector2(k, -k), C_GLYPH_2, 2.5 * px, true)


## the pause menu's "Touch controls" button: a pill with the help picture
class Entry:
	extends Control
	var px := 1.0
	var pressed := false
	var font: Font
	const TEXT := "Touch controls"

	func _draw() -> void:
		var s := StyleBoxFlat.new()
		s.bg_color = C_DISC_PRESSED if pressed else C_DISC
		s.border_color = C_BORDER
		s.set_border_width_all(maxi(1, roundi(1.0 * px)))
		s.set_corner_radius_all(roundi(size.y * 0.5))
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = roundi(4.0 * px)
		s.anti_aliasing = true
		draw_style_box(s, Rect2(Vector2.ZERO, size))
		TouchGlyphs.draw(self, "help", Vector2(size.y * 0.5 + 4.0 * px, size.y * 0.5), size.y * 0.78, C_ACCENT)
		var fs := roundi(NAME_PT * px)
		draw_string(font, Vector2(size.y + 6.0 * px, size.y * 0.5 + fs * 0.36), TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)

	func want_width() -> float:
		return size.y + 6.0 * px + font.get_string_size(TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(NAME_PT * px)).x + 18.0 * px


var _px := 1.0
var _open := false
var _dim: ColorRect
var _card: PanelContainer
var _scroll: ScrollContainer
var _grid: GridContainer
var _close: Close
var _entry: Entry
var _entry_shown := false
var _tween: Tween = null
var _switches := {}
var opened_from := ""   # "options" / "pause" / "test": the log


func _init() -> void:
	layer = 125  # over everything the game and the touch layer draw, the frame-rate readout (120) and the Options page included


func setup(px_per_pt: float) -> void:
	_px = px_per_pt
	_dim = ColorRect.new()
	_dim.name = "TouchHelpDim"
	_dim.color = C_DIM
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)
	_card = PanelContainer.new()
	_card.name = "TouchHelpCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE
	sb.border_color = C_BORDER
	sb.set_border_width_all(maxi(1, roundi(1.0 * _px)))
	sb.set_corner_radius_all(roundi(16.0 * _px))
	sb.content_margin_left = PAD_PT * _px
	sb.content_margin_right = PAD_PT * 0.5 * _px
	sb.content_margin_top = PAD_PT * 0.6 * _px
	sb.content_margin_bottom = PAD_PT * _px
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = roundi(10.0 * _px)
	sb.anti_aliasing = true
	_card.add_theme_stylebox_override("panel", sb)
	add_child(_card)
	_entry = Entry.new()
	_entry.name = "TouchHelpEntry"
	_entry.px = _px
	_entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry.visible = false
	_entry.accessibility_name = "Touch controls"
	add_child(_entry)
	_entry.font = _entry.get_theme_font("font")


func _ready() -> void:
	if not get_tree().root.window_input.is_connected(_on_window_input):
		get_tree().root.window_input.connect(_on_window_input)


## the gestures, as the Touch tab's switches are now (touch_controls.gd switches() plus "drag" and "taps")
func entries(sw: Dictionary) -> Array:
	var drag_pan := str(sw.get("drag", "select")) == "pan"
	var taps := str(sw.get("taps", "costs"))
	var hold_info := str(sw.get("hold", "info")) == "info"
	var twist_building := str(sw.get("twist", "building")) == "building"
	var placement := str(sw.get("placement", "confirm"))
	var targeting := str(sw.get("targeting", "confirm"))
	var out := [
		["tap", "Tap", "Select a unit or a building. With units selected, tap the ground to send them, or an enemy to attack."],
		["double", "Double-tap", "Select every unit of that kind on the screen."],
		["drag", "Drag", "Move the view. To draw a selection box, hold still for a moment, then drag." if drag_pan else "Draw a box around units to select them all."],
		["tap2", "Tap a button twice", {"costs": "Build, recruit, upgrades and powers: the first tap shows what it is and what it costs, the second uses it.",
			"all": "The first tap shows what a button does, the second uses it.", "act": "A tap uses a button at once."}.get(taps, "")],
		["hold", "Hold a button", "See what it does, without using it." if hold_info else "Right-click it: on a recruit button, takes one off the queue."],
		["hold_map", "Hold on the map", "Right-click: deselect, or cancel a building or a power that waits."],
		["pan", "Two-finger drag", "Move the view."],
		["pinch", "Pinch", "Zoom in and out."],
		["twist", "Twist two fingers", "Turn the view. While a building waits for ✓, turn the building." if twist_building else "Turn the view."],
		["two_tap", "Two-finger tap", "Right-click where the fingers are: cancel, or take one off a recruit queue."],
	]
	if placement == "confirm" or targeting == "confirm":
		out.append(["confirm", "✓ and ✕", "A building (or a power's aim) waits where you put it: tap ✓ to go ahead, ✕ to cancel. Touch the map to move it."])
	if bool(sw.get("ghost_above", true)):
		out.append(["aim", "Above your finger", "While you place or aim, the spot shows above your fingertip, so your finger does not hide it."])
	return out


## opens the card (`switches`: as entries() reads them; `from` for the log)
func open(switches: Dictionary, from := "") -> void:
	_switches = switches
	opened_from = from
	_build()
	_open = true
	_layout()
	_dim.visible = true
	_card.visible = true
	_entry.visible = false  # the pause menu's button is under the dim while the card is up
	_close.pressed = false
	if _tween != null:
		_tween.kill()
	var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
	_dim.modulate.a = 0.0
	_card.modulate.a = 0.0
	var y := _card.position.y
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_dim, "modulate:a", 1.0, APPEAR_S)
	_tween.tween_property(_card, "modulate:a", 1.0, APPEAR_S)
	if not reduce:
		_card.position.y += RISE_PT * _px
		_tween.tween_property(_card, "position:y", y, APPEAR_S)
	print("TOUCH IOS-46 help card opened (%s), %d gestures, %d column(s)" % [from, _grid.get_child_count(), _grid.columns])


func close() -> void:
	if not _open:
		return
	_open = false
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_dim, "modulate:a", 0.0, HIDE_S)
	_tween.tween_property(_card, "modulate:a", 0.0, HIDE_S)
	_tween.chain().tween_callback(func() -> void:
		_dim.visible = _open
		_card.visible = _open
		_entry.visible = _entry_shown and not _open)
	print("TOUCH IOS-46 help card closed")


func is_open() -> bool:
	return _open


func _build() -> void:
	for c in _card.get_children():
		c.queue_free()
		_card.remove_child(c)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", roundi(12.0 * _px))
	_card.add_child(column)
	# head: the title and its line, ✕ at the right
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", roundi(8.0 * _px))
	column.add_child(head)
	var titles := VBoxContainer.new()
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", roundi(2.0 * _px))
	head.add_child(titles)
	var title := _text("Touch controls", TITLE_PT, C_TEXT)
	titles.add_child(title)
	var sub := _text("What your fingers do in a game. Options › Touch changes any of it.", SUB_PT, C_HINT)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(sub)
	_close = Close.new()
	_close.px = _px
	_close.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close.custom_minimum_size = Vector2.ONE * CELL_PT * _px
	_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close.accessibility_name = "Close"
	head.add_child(_close)
	var rule := ColorRect.new()
	rule.color = C_RULE
	rule.custom_minimum_size = Vector2(0, maxf(1.0, roundf(1.0 * _px)))
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", roundi(COL_GAP_PT * _px))
	_grid.add_theme_constant_override("v_separation", roundi(ROW_GAP_PT * _px))
	_scroll.add_child(_grid)
	for e in entries(_switches):
		var cell := HBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", roundi(12.0 * _px))
		var g := Glyph.new()
		g.name_ = e[0]
		g.custom_minimum_size = Vector2.ONE * GLYPH_PT * _px
		g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(g)
		var texts := VBoxContainer.new()
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", roundi(1.0 * _px))
		cell.add_child(texts)
		texts.add_child(_text(e[1], NAME_PT, C_TEXT))
		var line := _text(e[2], LINE_PT, C_HINT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(line)
		_grid.add_child(cell)


func _text(t: String, pt: float, colour: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", roundi(pt * _px))
	l.add_theme_color_override("font_color", colour)
	return l


func _safe() -> Rect2:
	var view := get_viewport().get_visible_rect()
	if OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			view = view.intersection(safe)
	return view


func _layout() -> void:
	var safe := _safe().grow(-MARGIN_PT * _px)
	var width := minf(CARD_MAX_PT * _px, safe.size.x)
	var inner := width - PAD_PT * 1.5 * _px
	_grid.columns = 2 if (inner - COL_GAP_PT * _px) * 0.5 >= COLUMN_MIN_PT * _px else 1
	var col_w := (inner - (COL_GAP_PT * _px if _grid.columns == 2 else 0.0)) / _grid.columns
	# an autowrapped label is as tall as its lines at its width now: each gets its width before anything is measured
	for cell in _grid.get_children():
		cell.custom_minimum_size = Vector2(col_w, 0)
		var line: Label = cell.get_child(1).get_child(1)
		var w := col_w - (GLYPH_PT + 12.0) * _px - PAD_PT * 0.5 * _px
		line.custom_minimum_size = Vector2(w, 0)
		line.size = Vector2(w, 0)
		line.update_minimum_size()
	var head_line: Label = _card.get_child(0).get_child(0).get_child(0).get_child(1)
	head_line.custom_minimum_size = Vector2(inner - CELL_PT * _px - 8.0 * _px, 0)
	head_line.size = Vector2(head_line.custom_minimum_size.x, 0)
	head_line.update_minimum_size()
	_grid.reset_size()
	var grid_h := _grid.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(inner, grid_h)
	_card.size = Vector2(width, 0)
	_card.reset_size()
	var size := _card.get_combined_minimum_size()
	if size.y > safe.size.y:
		_scroll.custom_minimum_size.y -= size.y - safe.size.y
		_card.reset_size()
		size = _card.get_combined_minimum_size()
	_card.size = Vector2(width, size.y)
	_card.position = (safe.position + (safe.size - _card.size) * 0.5).round()


## the pause menu's button: shown at the bottom right of the safe area (`on`), or hidden
func show_entry(on: bool) -> void:
	if on == _entry_shown:
		return
	_entry_shown = on
	if on:
		var safe := _safe()
		var h := CELL_PT * _px
		_entry.size = Vector2(0, h)
		_entry.size = Vector2(_entry.want_width(), h)
		_entry.position = (safe.end - _entry.size - Vector2(MARGIN_PT, MARGIN_PT) * _px).round()
		_entry.pressed = false
		_entry.modulate.a = 0.0
		_entry.visible = not _open
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(_entry, "modulate:a", 1.0, APPEAR_S)
	else:
		_entry.visible = false


func entry_shown() -> bool:
	return _entry_shown


func entry_rect() -> Rect2:
	return Rect2(_entry.position, _entry.size) if _entry_shown else Rect2()


## a finger at `at`: while open "close" (the ✕ cell), "card" (on the card), "outside"; else "entry" on the pause menu's button, or ""
func hit(at: Vector2) -> String:
	if _open:
		if Rect2(_close.global_position, _close.size).grow(4.0 * _px).has_point(at):
			return "close"
		return "card" if Rect2(_card.position, _card.size).has_point(at) else "outside"
	if _entry_shown and entry_rect().grow(4.0 * _px).has_point(at):
		return "entry"
	return ""


func set_pressed(what: String) -> void:
	if _close != null:
		_close.pressed = what == "close"
		_close.queue_redraw()
	_entry.pressed = what == "entry"
	_entry.queue_redraw()


## a finger drag on the card scrolls it (a card taller than the safe area)
func scroll_by(dy: float) -> void:
	if _open and _scroll != null:
		_scroll.scroll_vertical = int(_scroll.scroll_vertical - dy)


## a mouse (an iPad's, the Mac running the iPhone build): a click on ✕ or outside closes the card; on the pause menu's button opens it. The click also
## reaches the menus under it (the shell reads the mouse in its own _input): a known gap of the prototype
func _on_window_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b == null or not b.pressed or b.button_index != MOUSE_BUTTON_LEFT:
		return
	match hit(b.position):
		"close", "outside":
			close()
		"entry":
			entry_pressed.emit()


signal entry_pressed


## for the tests and the screenshots
func state() -> Dictionary:
	return {"open": _open, "entry": _entry_shown, "entry_rect": entry_rect(), "card_rect": Rect2(_card.position, _card.size) if _open else Rect2(),
		"columns": _grid.columns if _grid != null else 0, "entries": _grid.get_child_count() if _grid != null else 0, "from": opened_from}
