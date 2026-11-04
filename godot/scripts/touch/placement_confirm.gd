extends CanvasLayer
## Lane IOS-26 (the owner's decision, 2026-11-04: "✓ / ✕ by the ghost"): the two buttons a touch placement waits on. The touch layer
## (touch_controls.gd) owns the gesture and the game calls; this layer only draws the buttons, lays them out beside the ghost and answers which one a
## finger is on. The buttons take no input of their own (mouse_filter IGNORE): the touch layer hit-tests the finger before it makes any mouse event,
## so the pointer (and with it the ghost) never moves to a button.
##
##   ✓ (build) .... primary: a dark disc, a gold ring and a gold check; dimmed (the ring and the check at 25 %) while the ghost is red
##   ✕ (cancel) ... secondary: the same disc, the ring at 40 % and a light cross
## Both are DIAMETER points across with a HIT_RADIUS touch area (larger than the disc, never under 44 pt). Their centres sit `side` pixels from the
## ghost's point (the touch layer's: at least SIDE_PT, more when the camera is zoomed in, to clear a building's footprint). Layout, the first that fits
## inside the safe area and off the HUD (the Palantir, the side bar, the radial bubbles, the radar: the touch layer's `free` call), along `axis`
## (a building: the screen's x; a wall span: across the span, so the buttons never lie on its line):
##   ✕ before, ✓ after (level with the ghost) | both before (✓ nearer) | both after (✓ nearer) | then each of `away` (a building: above, then below,
##   where the finger just was; a wall span: beyond its end, never back along it)
## None fits: the first, each button pulled into the safe area.
## Motion: the pair appears with a 180 ms fade and a 0.85 -> 1 scale (cubic ease-out); with Reduce Motion, the fade only. It goes at once (a finger
## on the world hides it: the finger is on its way to move the ghost). A pressed button shrinks to 0.94 and its disc lightens, at once.

const DIAMETER_PT := 48.0       # the disc (iOS's 44 pt minimum target, plus a little for a thumb on a moving map)
const HIT_RADIUS_PT := 30.0     # the touch area's radius: 60 pt across
const SIDE_PT := 64.0           # from the ghost's point to a button's centre (the disc's inner edge 40 pt from it)
const GAP_PT := 12.0            # between the two discs when they sit side by side
const MARGIN_PT := 8.0          # from the safe area's edge
const RING_PT := 2.5            # the ✓'s ring (the ✕'s is 1.5 pt)
const GLYPH_PT := 3.5           # the check's and the cross's stroke
const APPEAR_S := 0.18
const PRESSED_SCALE := 0.94

# lane IOS-12's tokens (scripts/release/first_run.gd): the near-black surface and BFME's menu gold
const C_DISC := Color(0.06, 0.06, 0.07, 0.88)
const C_DISC_PRESSED := Color(0.17, 0.15, 0.11, 0.94)
const C_SHADOW := Color(0, 0, 0, 0.35)          # a soft edge under the disc, for light ground (snow, sand)
const C_ACCENT := Color("c8a25a")
const C_ACCENT_PRESSED := Color("a8853f")
const C_ACCENT_DISABLED := Color(0.784, 0.635, 0.353, 0.25)
const C_RING_2 := Color(0.784, 0.635, 0.353, 0.4) # the secondary ring: the accent at 40 % (C_BORDER_LIVE)
const C_GLYPH_2 := Color(1, 1, 1, 0.82)


## one round button; `kind` "build" or "cancel"
class Disc:
	extends Control
	var kind := "build"
	var px := 1.0               # pixels per point
	var enabled := true
	var pressed := false

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		draw_circle(c, r + 1.5 * px, C_SHADOW, true, -1.0, true)
		draw_circle(c, r, C_DISC_PRESSED if pressed else C_DISC, true, -1.0, true)
		var build := kind == "build"
		var ring: Color = (C_ACCENT_PRESSED if pressed else C_ACCENT) if build else C_RING_2
		if build and not enabled:
			ring = C_ACCENT_DISABLED
		var ring_w := (RING_PT if build else 1.5) * px
		draw_arc(c, r - ring_w * 0.5, 0.0, TAU, 48, ring, ring_w, true)
		var g := r * 0.42  # the glyph's half size
		var w := GLYPH_PT * px
		if build:
			var ink: Color = C_ACCENT if enabled else C_ACCENT_DISABLED
			draw_polyline(PackedVector2Array([c + Vector2(-g, 0.05 * g), c + Vector2(-0.3 * g, 0.72 * g), c + Vector2(g, -0.62 * g)]), ink, w, true)
		else:
			var k := g * 0.78
			draw_line(c + Vector2(-k, -k), c + Vector2(k, k), C_GLYPH_2, w, true)
			draw_line(c + Vector2(-k, k), c + Vector2(k, -k), C_GLYPH_2, w, true)


var _px := 1.0
var _build: Disc
var _cancel: Disc
var _shown := false
var _ghost := Vector2.INF
var _offsets := [Vector2.ZERO, Vector2.ZERO]  # the chosen layout: the build's and the cancel's centre from the ghost's point
var _safe := Rect2()
var _tween: Tween = null


func _init() -> void:
	layer = 110  # over the game and its HUD; under the frame-rate readout (fps_overlay.gd, 120)


func setup(px_per_pt: float) -> void:
	_px = px_per_pt
	_build = _disc("build", "Build here")
	_cancel = _disc("cancel", "Cancel placement")


func _disc(kind: String, label: String) -> Disc:
	var d := Disc.new()
	d.kind = kind
	d.px = _px
	d.name = "Confirm" + kind.capitalize()
	d.size = Vector2.ONE * DIAMETER_PT * _px
	d.pivot_offset = d.size * 0.5
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.focus_mode = Control.FOCUS_NONE
	d.accessibility_name = label
	d.visible = false
	add_child(d)
	return d


## the buttons beside the ghost's point `ghost` (window pixels), inside `safe`; `free` (Callable(Vector2) -> bool) says a pixel is off the HUD.
## `side`: pixels from the ghost's point to a button's centre (0: SIDE_PT); `axis`, `away`: the layout's directions (above). `animate`: the
## appearing motion (else they are simply there)
func show_at(ghost: Vector2, safe: Rect2, free: Callable, animate := true, side := 0.0, axis := Vector2.RIGHT, away: Array = [Vector2.UP, Vector2.DOWN]) -> void:
	_ghost = ghost
	_safe = safe
	_offsets = _layout(ghost, free, maxf(side, SIDE_PT * _px), axis, away)
	_place()
	if _tween != null:
		_tween.kill()
		_tween = null
	_shown = true
	for d in [_build, _cancel]:
		d.visible = true
		d.pressed = false
		d.queue_redraw()
	if not animate:
		for d in [_build, _cancel]:
			d.modulate.a = 1.0
			d.scale = Vector2.ONE
		return
	var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for d in [_build, _cancel]:
		d.modulate.a = 0.0
		d.scale = Vector2.ONE if reduce else Vector2.ONE * 0.85
		_tween.tween_property(d, "modulate:a", 1.0, APPEAR_S)
		if not reduce:
			_tween.tween_property(d, "scale", Vector2.ONE, APPEAR_S)


## the ghost moved (the camera panned or zoomed under it): the buttons keep their layout beside it, pulled into the safe area
func move_to(ghost: Vector2) -> void:
	_ghost = ghost
	if _shown:
		_place()


func hide_now() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_shown = false
	for d in [_build, _cancel]:
		d.visible = false
		d.pressed = false


func is_shown() -> bool:
	return _shown


## "build", "cancel" or "" for a finger at `at`: within HIT_RADIUS_PT of a shown button's centre (the nearer one)
func hit(at: Vector2) -> String:
	if not _shown:
		return ""
	var b := at.distance_to(centre("build"))
	var c := at.distance_to(centre("cancel"))
	var reach := HIT_RADIUS_PT * _px
	if b <= reach and b <= c:
		return "build"
	if c <= reach:
		return "cancel"
	return ""


func centre(kind: String) -> Vector2:
	var d := _build if kind == "build" else _cancel
	return d.position + d.size * 0.5


func set_pressed(kind: String) -> void:
	for d in [_build, _cancel]:
		var on: bool = d.kind == kind
		if d.pressed != on:
			d.pressed = on
			d.scale = Vector2.ONE * (PRESSED_SCALE if on else 1.0)
			d.queue_redraw()


func set_build_enabled(on: bool) -> void:
	if _build.enabled != on:
		_build.enabled = on
		_build.queue_redraw()


func build_enabled() -> bool:
	return _build.enabled


## for the tests: { shown, ghost, build, cancel (centres), build_enabled, diameter, hit_radius (pixels) }
func state() -> Dictionary:
	return {"shown": _shown, "ghost": _ghost, "build": centre("build"), "cancel": centre("cancel"), "build_enabled": _build.enabled,
		"diameter": DIAMETER_PT * _px, "hit_radius": HIT_RADIUS_PT * _px}


func _place() -> void:
	var half := Vector2.ONE * DIAMETER_PT * _px * 0.5
	var inner := _safe.grow(-MARGIN_PT * _px)
	for i in 2:
		var d: Disc = _build if i == 0 else _cancel
		var at: Vector2 = _ghost + _offsets[i]
		if inner.size.x > half.x * 2.0 and inner.size.y > half.y * 2.0:
			at = at.clamp(inner.position + half, inner.end - half)
		d.position = (at - half).round()


## the first layout whose two discs sit inside the safe area and off the HUD: [build offset, cancel offset]
func _layout(ghost: Vector2, free: Callable, side: float, axis: Vector2, away: Array) -> Array:
	var pair := (DIAMETER_PT + GAP_PT) * _px
	var candidates := [
		[axis * side, -axis * side],                               # ✕ before, ✓ after (a building: ✕ left, ✓ right)
		[-axis * side, -axis * (side + pair)],                     # both before (the side bar is on the right), ✓ nearer
		[axis * side, axis * (side + pair)],                       # both after, ✓ nearer
	]
	for d in away:
		var dir: Vector2 = d
		var across := dir.orthogonal() if dir.orthogonal().dot(axis) >= 0.0 else -dir.orthogonal()
		candidates.append([dir * side + across * pair * 0.5, dir * side - across * pair * 0.5])
	for c in candidates:
		if _fits(ghost + c[0], free) and _fits(ghost + c[1], free):
			return c
	return candidates[0]


## a disc centred at `at` lies inside the safe area (less the margin) and its centre and four edge points are off the HUD
func _fits(at: Vector2, free: Callable) -> bool:
	var r := DIAMETER_PT * _px * 0.5
	var inner := _safe.grow(-MARGIN_PT * _px)
	if not inner.encloses(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0)):
		return false
	for p in [at, at + Vector2(r, 0), at - Vector2(r, 0), at + Vector2(0, r), at - Vector2(0, r)]:
		if not free.call(p):
			return false
	return true
