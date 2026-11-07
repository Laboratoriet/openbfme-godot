extends CanvasLayer
## Lane IOS-47: the benchmark's summary card, shown when a run ends (game.gd _run_benchmark): the variant and when, the results' lines
## (benchmark_stats.gd lines(): fps, p95 / p99, the worst stalls, video memory, the display settings, battery and thermal, the device, the battle) and
## where the file is. IOS-12's look: near-black, BFME's gold, ivory text; sizes in points (the touch layer's px per point); centred in the safe area.
## Close (a 44 pt button, a tap or a click on it, Esc or Enter) emits closed. Motion: a 220 ms fade and an 8 pt rise (cubic ease-out); Reduce
## Motion: the fade only.

signal closed

const Stats := preload("res://scripts/benchmark/benchmark_stats.gd")

const MAX_W_PT := 560.0
const PAD_PT := 20.0
const TITLE_PT := 20.0
const SUB_PT := 12.5
const LABEL_PT := 13.0
const VALUE_PT := 14.5
const BUTTON_H_PT := 44.0
const LABEL_W_PT := 170.0   # the labels' column (the values take the rest)

const C_DIM := Color(0, 0, 0, 0.55)
const C_SURFACE := Color(0.06, 0.06, 0.07, 0.97)
const C_BORDER := Color(0.784, 0.635, 0.353, 0.6)
const C_ACCENT := Color("c8a25a")
const C_TEXT := Color(0.94, 0.91, 0.84)
const C_HINT := Color(0.94, 0.91, 0.84, 0.66)
const C_RULE := Color(0.784, 0.635, 0.353, 0.22)

var _px := 1.0
var _panel: PanelContainer
var _button: Button


func _init() -> void:
	layer = 126  # over the menus, the game and the touch help card


func show_results(r: Dictionary, px_per_pt := 1.0) -> void:
	_px = px_per_pt
	var dim := ColorRect.new()
	dim.color = C_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE
	sb.border_color = C_BORDER
	sb.set_border_width_all(maxi(1, roundi(_px)))
	sb.set_corner_radius_all(roundi(16.0 * _px))
	sb.set_content_margin_all(PAD_PT * _px)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = roundi(10.0 * _px)
	sb.anti_aliasing = true
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", roundi(10.0 * _px))
	_panel.add_child(col)
	var error := str(r.get("error", ""))
	col.add_child(_label("Benchmark: %s" % str(r.get("variant", "")).capitalize() if error.is_empty() else "Benchmark failed", TITLE_PT, C_TEXT))
	var map := str(r.get("map", "")).get_file().get_basename().trim_prefix("map mp ").capitalize()
	var sub := "%s · %.0f s · %s, seed %d" % [str(r.get("started", "")).replace("T", " "), float(r.get("seconds", 0.0)), map, int(r.get("seed", 0))] \
		if error.is_empty() else error
	var sub_l := _label(sub, SUB_PT, C_HINT)
	sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub_l)
	_wrap(sub_l, _width() - 2.0 * PAD_PT * _px)
	var rule := ColorRect.new()
	rule.color = C_RULE
	rule.custom_minimum_size = Vector2(0, maxf(1.0, roundf(_px)))
	col.add_child(rule)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", roundi(16.0 * _px))
	grid.add_theme_constant_override("v_separation", roundi(7.0 * _px))
	col.add_child(grid)
	var width := _width()
	if error.is_empty():
		for l in Stats.lines(r):
			var k := _label(l[0], LABEL_PT, C_HINT)
			k.custom_minimum_size = Vector2(LABEL_W_PT * _px - 16.0 * _px, 0)
			grid.add_child(k)
			var v := _label(l[1], VALUE_PT, C_TEXT if l[0] != "Average" else C_ACCENT)
			v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			grid.add_child(v)
			_wrap(v, width - 2.0 * PAD_PT * _px - LABEL_W_PT * _px)
		var file := _label("Saved: %s" % ProjectSettings.globalize_path(str(r.get("file", ""))).get_file(), SUB_PT, C_HINT)
		col.add_child(file)
	_button = Button.new()
	_button.text = "Close"
	_button.custom_minimum_size = Vector2(120.0 * _px, BUTTON_H_PT * _px)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button.add_theme_font_size_override("font_size", roundi(15.0 * _px))
	_button.add_theme_color_override("font_color", C_TEXT)
	for state in ["normal", "hover", "pressed", "focus"]:
		var b := StyleBoxFlat.new()
		b.bg_color = Color(0.17, 0.15, 0.11, 0.94) if state in ["pressed", "hover"] else Color(0.06, 0.06, 0.07, 0.9)
		b.border_color = C_ACCENT if state != "normal" else C_BORDER
		b.set_border_width_all(maxi(1, roundi(1.25 * _px)))
		b.set_corner_radius_all(roundi(BUTTON_H_PT * 0.5 * _px))
		b.anti_aliasing = true
		_button.add_theme_stylebox_override(state, b)
	_button.pressed.connect(_close)
	col.add_child(_button)
	_panel.size = Vector2(width, 0)
	_panel.reset_size()
	_panel.size = Vector2(width, _panel.get_combined_minimum_size().y)
	var safe := _safe()
	var at := (safe.position + (safe.size - _panel.size) * 0.5).round()
	_panel.position = at
	var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
	_panel.modulate.a = 0.0
	dim.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.22)
	tw.tween_property(dim, "modulate:a", 1.0, 0.22)
	if not reduce:
		_panel.position.y += 8.0 * _px
		tw.tween_property(_panel, "position:y", at.y, 0.22)
	_button.grab_focus()


## an autowrapped label (in the tree: its font is known) as tall as its lines at `width`
func _wrap(l: Label, width: float) -> void:
	l.custom_minimum_size = Vector2(width, 0)
	l.size = Vector2(width, 0)
	l.update_minimum_size()


func _label(t: String, pt: float, colour: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", roundi(pt * _px))
	l.add_theme_color_override("font_color", colour)
	return l


func _width() -> float:
	return minf(MAX_W_PT * _px, _safe().size.x - 32.0 * _px)


func _safe() -> Rect2:
	var view := get_viewport().get_visible_rect()
	if OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			view = view.intersection(safe)
	return view


## modal while shown (the card is a later child of the root than the touch layer and the menus, so its _input comes first): every touch and click
## is its own; lifting a finger or releasing the button on Close, Esc or Enter closes it
func _input(event: InputEvent) -> void:
	if _button == null:
		return
	var close_rect := Rect2(_button.global_position, _button.size).grow(4.0 * _px)
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		var t := event as InputEventScreenTouch
		var m := event as InputEventMouseButton
		if (t != null and not t.pressed and close_rect.has_point(t.position)) or (m != null and not m.pressed and m.button_index == MOUSE_BUTTON_LEFT
				and close_rect.has_point(m.position)):
			_close()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _button == null:
		return
	_button = null
	closed.emit()
	queue_free()


## the card's rectangle (the screenshots, the test)
func panel_rect() -> Rect2:
	return Rect2(_panel.position, _panel.size) if _panel != null else Rect2()
