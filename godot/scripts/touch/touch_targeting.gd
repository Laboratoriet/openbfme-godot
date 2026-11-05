extends CanvasLayer
## Lane IOS-43 (the owner, 2026-11-05: "I don't remember how they work, and after clicking it seems like you have to place them on the map. Maybe
## incorporate something similar to building placement?"): what a touch screen shows while a spell book power or a hero ability waits for its target.
## The touch layer (touch_controls.gd) owns the gestures and the game calls (InGameHudNode.touch_targeting_at / cancel_targeting); this layer only draws
## and answers which of its parts a finger is on. Nothing here takes input of its own (mouse_filter IGNORE): the touch layer hit-tests first.
##
##   the banner ....... near the top of the safe area, under the command toolbar (IOS-37) when it shows: "Choose where: <power>" (a ground power) or
##                      "Choose a target: <power>" (one that needs a unit or a building), a second line saying what to do, and a ✕ that cancels
##                      (the game's own cancel, the right click's). Dark surface, BFME's gold, a 44 pt ✕ cell. It appears with a 200 ms fade and a
##                      6 pt drop (cubic ease-out); Reduce Motion: the fade only
##   the ring ......... a ground power's area where it would land, for a power whose retail radius decal is not drawn (no RadiusCursorType, or the device
##                      did not draw it): the power's radius on the ground (at least RING_MIN_PT), gold where the game would cast, retail's red where it
##                      would not. A power whose decal is drawn shows the game's own decal (white / red), not this ring
##   the highlight .... the unit or building an object power was aimed at: a gold ring around it while ✓ / ✕ wait; it appears with a 0.85 -> 1 scale
##   the refusal ...... a tap the game would not take (a target the power cannot have, a ground point it cannot land on): a red ring that widens and
##                      fades at that point (REFUSE_S) with a short vibration (the touch layer's): the mouse's red invalid cursor, for a finger
## ✓ / ✕ are IOS-26's buttons (placement_confirm.gd), made by the touch layer and laid out beside the aim point as a placement's are.

const BANNER_TOP_PT := 6.0        # from the toolbar's bottom (or the safe area's top)
const BANNER_MARGIN_PT := 8.0     # from the safe area's sides
const BANNER_MAX_PT := 440.0      # its widest
const CLOSE_PT := 44.0            # the ✕ cell (iOS's minimum target)
const CLOSE_DISC_PT := 32.0       # its disc
const TITLE_PT := 16.0
const HINT_PT := 12.5
const PAD_X_PT := 14.0
const PAD_Y_PT := 6.0
const RING_PT := 2.5              # the ring's and the highlight's stroke
const RING_MIN_PT := 22.0         # a ground power's ring is never smaller than this (a radius 0 power: a point)
const APPEAR_S := 0.2
const HIDE_S := 0.15
const REFUSE_S := 0.4
const DROP_PT := 6.0

# IOS-12's tokens (placement_confirm.gd, command_toolbar.gd): the near-black surface, BFME's menu gold, the help text's ivory
const C_SURFACE := Color(0.06, 0.06, 0.07, 0.92)
const C_BORDER := Color(0.784, 0.635, 0.353, 0.6)
const C_ACCENT := Color("c8a25a")
const C_TEXT := Color(0.94, 0.91, 0.84)
const C_HINT := Color(0.94, 0.91, 0.84, 0.72)
const C_DISC := Color(0.06, 0.06, 0.07, 0.88)
const C_DISC_PRESSED := Color(0.17, 0.15, 0.11, 0.94)
const C_RING_2 := Color(0.784, 0.635, 0.353, 0.4)
const C_GLYPH_2 := Color(1, 1, 1, 0.82)
const C_HALO := Color(0.06, 0.06, 0.07, 0.55)
# retail's invalid hint colour (RadiusCursor.h: Shadow::setColor 0xFFFF1414)
const C_INVALID := Color(1.0, 0.078, 0.078)


## the banner's ✕
class CloseDisc:
	extends Control
	var px := 1.0
	var pressed := false

	func _draw() -> void:
		var c := size * 0.5
		var r := CLOSE_DISC_PT * 0.5 * px
		draw_circle(c, r, C_DISC_PRESSED if pressed else C_DISC, true, -1.0, true)
		draw_arc(c, r - 0.75 * px, 0.0, TAU, 40, C_RING_2, 1.5 * px, true)
		var k := r * 0.36
		draw_line(c + Vector2(-k, -k), c + Vector2(k, k), C_GLYPH_2, 2.5 * px, true)
		draw_line(c + Vector2(-k, k), c + Vector2(k, -k), C_GLYPH_2, 2.5 * px, true)


## the ring, the highlight and the refusal, drawn over the whole view
class Marks:
	extends Control
	var px := 1.0
	var ring_at := Vector2.INF     # a ground power's ring
	var ring_radius := 0.0
	var ring_valid := true
	var target_at := Vector2.INF   # an object power's target
	var target_radius := 0.0
	var target_scale := 1.0
	var refuse_at := Vector2.INF   # the refusal
	var refuse_t := 1.0            # 0 -> 1 over REFUSE_S

	func _draw() -> void:
		if ring_at.is_finite():
			var colour := C_ACCENT if ring_valid else C_INVALID
			draw_circle(ring_at, ring_radius, Color(colour, 0.12), true, -1.0, true)
			draw_arc(ring_at, ring_radius, 0.0, TAU, 72, C_HALO, (RING_PT + 2.5) * px, true)
			draw_arc(ring_at, ring_radius, 0.0, TAU, 72, colour, RING_PT * px, true)
			draw_circle(ring_at, 3.0 * px, colour, true, -1.0, true)
		if target_at.is_finite():
			var r := target_radius * target_scale
			draw_arc(target_at, r, 0.0, TAU, 64, C_HALO, (RING_PT + 2.5) * px, true)
			draw_arc(target_at, r, 0.0, TAU, 64, C_ACCENT, RING_PT * px, true)
			# four short ticks outside the ring: a sight, so a picked target reads apart from the game's own selection circles
			for k in 4:
				var d := Vector2.RIGHT.rotated(k * PI * 0.5)
				draw_line(target_at + d * (r + 3.0 * px), target_at + d * (r + 10.0 * px), C_ACCENT, RING_PT * px, true)
		if refuse_at.is_finite() and refuse_t < 1.0:
			var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
			var e := 1.0 - pow(1.0 - refuse_t, 3.0)  # cubic ease-out
			var r := (RING_MIN_PT + (0.0 if reduce else 14.0 * e)) * px
			draw_arc(refuse_at, r, 0.0, TAU, 48, Color(C_INVALID, 1.0 - refuse_t), 3.0 * px, true)
			var k := 7.0 * px
			draw_line(refuse_at + Vector2(-k, -k), refuse_at + Vector2(k, k), Color(C_INVALID, 1.0 - refuse_t), 3.0 * px, true)
			draw_line(refuse_at + Vector2(-k, k), refuse_at + Vector2(k, -k), Color(C_INVALID, 1.0 - refuse_t), 3.0 * px, true)


var _px := 1.0
var _banner: PanelContainer
var _title: Label
var _hint: Label
var _close: CloseDisc
var _marks: Marks
var _shown := false
var _text := ["", ""]
var _banner_tween: Tween = null
var _target_tween: Tween = null
var _refuse_tween: Tween = null


func _init() -> void:
	layer = 109  # over the game, its HUD and the command toolbar (108); under ✓ / ✕ (110) and the frame-rate readout (120)


func setup(px_per_pt: float) -> void:
	_px = px_per_pt
	_marks = Marks.new()
	_marks.name = "TargetMarks"
	_marks.px = _px
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_marks)
	_banner = PanelContainer.new()
	_banner.name = "TargetBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = C_SURFACE
	style.border_color = C_BORDER
	style.set_border_width_all(maxi(1, roundi(1.0 * _px)))
	style.set_corner_radius_all(roundi(10.0 * _px))
	style.content_margin_left = PAD_X_PT * _px
	style.content_margin_right = 4.0 * _px  # the ✕ cell brings its own room
	style.content_margin_top = PAD_Y_PT * _px
	style.content_margin_bottom = PAD_Y_PT * _px
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = roundi(4.0 * _px)
	_banner.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", roundi(8.0 * _px))
	_banner.add_child(row)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", roundi(1.0 * _px))
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", roundi(TITLE_PT * _px))
	_title.add_theme_color_override("font_color", C_TEXT)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(_title)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", roundi(HINT_PT * _px))
	_hint.add_theme_color_override("font_color", C_HINT)
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(_hint)
	_close = CloseDisc.new()
	_close.name = "TargetCancel"
	_close.px = _px
	_close.custom_minimum_size = Vector2.ONE * CLOSE_PT * _px
	_close.pivot_offset = _close.custom_minimum_size * 0.5
	_close.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close.focus_mode = Control.FOCUS_NONE
	_close.accessibility_name = "Cancel"
	row.add_child(_close)
	add_child(_banner)


## the banner for a waiting power: `title` its first line ("Choose where: Heal"), `hint` the second; laid out under `top` (window pixels: the toolbar's
## bottom, or the safe area's top) and centred in `safe`. Shown with its motion when it was hidden or says something new
func show_banner(title: String, hint: String, safe: Rect2, top: float) -> void:
	var fresh := not _shown or _text != [title, hint]
	_text = [title, hint]
	_title.text = title
	_hint.text = hint
	_hint.visible = hint != ""
	var room := minf(BANNER_MAX_PT * _px, safe.size.x - 2.0 * BANNER_MARGIN_PT * _px)
	var font := _title.get_theme_font("font")
	var want := maxf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(TITLE_PT * _px)).x,
		font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(HINT_PT * _px)).x)
	var width := minf(room, ceilf(want) + (PAD_X_PT + 4.0 + 8.0 + CLOSE_PT) * _px + 2.0)
	_banner.custom_minimum_size = Vector2(width, CLOSE_PT * _px)
	_banner.size = Vector2(width, 0)
	_banner.size = _banner.get_combined_minimum_size()
	var at := Vector2(safe.position.x + (safe.size.x - _banner.size.x) * 0.5, maxf(top, safe.position.y) + BANNER_TOP_PT * _px)
	_banner.position = at.round()
	if not fresh:
		return
	_shown = true
	_banner.visible = true
	_close.pressed = false
	_close.scale = Vector2.ONE
	if _banner_tween != null:
		_banner_tween.kill()
	var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
	_banner.modulate.a = 0.0
	_banner_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, APPEAR_S)
	if not reduce:
		_banner.position.y -= DROP_PT * _px
		_banner_tween.tween_property(_banner, "position:y", at.round().y, APPEAR_S)


func hide_banner() -> void:
	if not _shown:
		return
	_shown = false
	_text = ["", ""]
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, HIDE_S)
	_banner_tween.tween_callback(func() -> void: _banner.visible = _shown)


func banner_shown() -> bool:
	return _shown


## the banner's rectangle (window pixels; Rect2() while hidden): ✓ / ✕ keep off it
func banner_rect() -> Rect2:
	return Rect2(_banner.position, _banner.size) if _shown else Rect2()


## a finger at `at` is on the banner's ✕ (its 44 pt cell, and a little more toward the banner's edge)
func cancel_hit(at: Vector2) -> bool:
	if not _shown:
		return false
	var cell := Rect2(_banner.position + _close.position, _close.size).grow(4.0 * _px)
	return cell.has_point(at)


func cancel_centre() -> Vector2:
	return _banner.position + _close.position + _close.size * 0.5


func set_cancel_pressed(on: bool) -> void:
	if _close.pressed != on:
		_close.pressed = on
		_close.scale = Vector2.ONE * (0.94 if on else 1.0)
		_close.queue_redraw()


## a ground power's ring at `at` with `radius` pixels (Vector2.INF: none), gold or red
func set_ring(at: Vector2, radius: float, valid: bool) -> void:
	radius = maxf(radius, RING_MIN_PT * _px)
	if at == _marks.ring_at and is_equal_approx(radius, _marks.ring_radius) and valid == _marks.ring_valid:
		return
	_marks.ring_at = at
	_marks.ring_radius = radius
	_marks.ring_valid = valid
	_marks.queue_redraw()


## an object power's target at `at`, `radius` pixels around it (Vector2.INF: none); `appear` plays the pick's motion
func set_target(at: Vector2, radius: float, appear := false) -> void:
	_marks.target_at = at
	_marks.target_radius = radius
	if appear and at.is_finite():
		if _target_tween != null:
			_target_tween.kill()
		if DisplayServer.accessibility_should_reduce_animation() == 1:
			_marks.target_scale = 1.0
		else:
			_marks.target_scale = 0.85
			_target_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_target_tween.tween_method(func(v: float) -> void:
				_marks.target_scale = v
				_marks.queue_redraw(), 0.85, 1.0, 0.18)
	_marks.queue_redraw()


## the refusal at `at`: a red ring with a cross, widening and fading out
func refuse(at: Vector2) -> void:
	_marks.refuse_at = at
	if _refuse_tween != null:
		_refuse_tween.kill()
	_refuse_tween = create_tween()
	_refuse_tween.tween_method(func(v: float) -> void:
		_marks.refuse_t = v
		_marks.queue_redraw(), 0.0, 1.0, REFUSE_S)


## everything off (the power went: cast, cancelled, or the game ended it)
func clear() -> void:
	hide_banner()
	set_ring(Vector2.INF, 0.0, true)
	set_target(Vector2.INF, 0.0)


## for the tests: { banner, title, hint, banner_rect, cancel (centre), ring, ring_radius, ring_valid, target, target_radius, refusing }
func state() -> Dictionary:
	return {"banner": _shown, "title": _text[0], "hint": _text[1], "banner_rect": banner_rect(), "cancel": cancel_centre(),
		"ring": _marks.ring_at, "ring_radius": _marks.ring_radius, "ring_valid": _marks.ring_valid, "target": _marks.target_at,
		"target_radius": _marks.target_radius, "refusing": _marks.refuse_at.is_finite() and _marks.refuse_t < 1.0}
