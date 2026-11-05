extends CanvasLayer
## Lane IOS-40 (the owner's decision, 2026-11-05: "click once to see name/info and twice to build is better"): the gold ring around a HUD button a first
## tap armed. The touch layer (touch_controls.gd) owns the gesture, the game calls and the help box; this layer only draws the ring around the button's
## window rectangle (InGameHudNode.touch_button_at's "rect") and takes no input (mouse_filter IGNORE).
##
##   armed ...... a gold ring (IOS-12's accent, as ✓'s) just outside the button's circle, over a soft dark halo so it reads on the Palantir's gold and on
##                bright ground; it stays for the arm window and fades out over its last FADE_TAIL_S (the window running out, without a sweep that could
##                be taken for the game's own recharge clock)
##   used ....... a tap that used the button: the ring flashes bright and settles back to gold (USE_S): the press went through, and the button stays
##                armed for another tap (the arm window starts again)
##   disarmed ... a tap elsewhere, a gesture, the time out: the ring fades (DISARM_S)
## Lane IOS-37, the production cancel: while the armed button has something queued that its right press would cancel, a small ✕ disc (BADGE_PT, the
## IOS-26 ✕'s look, a 44 pt touch area) sits beside the ring, outward (a radial bubble: away from the ring of bubbles; another button: toward the
## screen's middle), kept inside the safe area. It appears with the ring's fade; pressed, it shrinks to 0.94 and lightens.
## The ring is round: the Palantir's buttons and the radial bubbles are round, and the side bar's frames are round glass. It hugs the button: the larger
## half side of the hit box plus OUTSET_PT (a ring any larger reaches over the neighbouring buttons of the side bar and the arc).
## Motion: in ARM_S with a 1.12 -> 1 scale (cubic ease-out: it settles onto the button); with Reduce Motion, fades only.

const RING_PT := 2.5             # the gold stroke
const HALO_PT := 5.0             # the dark halo under it
const OUTSET_PT := 2.0           # from the button's edge to the ring's middle
const ARM_S := 0.18
const USE_S := 0.22
const DISARM_S := 0.14
const FADE_TAIL_S := 0.6
const BADGE_PT := 30.0           # lane IOS-37: the ✕ disc
const BADGE_HIT_PT := 22.0       # its touch area's radius (44 pt across)
const BADGE_GAP_PT := 6.0        # from the ring to the disc
const C_DISC := Color(0.06, 0.06, 0.07, 0.88)          # IOS-26's ✕ (placement_confirm.gd)
const C_DISC_PRESSED := Color(0.17, 0.15, 0.11, 0.94)
const C_RING_2 := Color(0.784, 0.635, 0.353, 0.4)
const C_GLYPH_2 := Color(1, 1, 1, 0.82)

const C_ACCENT := Color("c8a25a")              # IOS-12's gold (placement_confirm.gd C_ACCENT)
const C_ACCENT_BRIGHT := Color("e9cd8f")       # the press's flash
const C_HALO := Color(0.06, 0.06, 0.07, 0.55)  # IOS-12's near-black, see-through


class Ring:
	extends Control
	var px := 1.0
	var radius := 0.0
	var colour := C_ACCENT

	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, radius, 0.0, TAU, 64, C_HALO, HALO_PT * px, true)
		draw_arc(c, radius, 0.0, TAU, 64, colour, RING_PT * px, true)


## lane IOS-37: the ✕ beside the ring
class Badge:
	extends Control
	var px := 1.0
	var pressed := false

	func _draw() -> void:
		var c := size * 0.5
		var r := BADGE_PT * 0.5 * px
		draw_circle(c, r + 1.5 * px, Color(0, 0, 0, 0.35), true, -1.0, true)
		draw_circle(c, r, C_DISC_PRESSED if pressed else C_DISC, true, -1.0, true)
		draw_arc(c, r - 0.75 * px, 0.0, TAU, 40, C_RING_2, 1.5 * px, true)
		var k := r * 0.34
		draw_line(c + Vector2(-k, -k), c + Vector2(k, k), C_GLYPH_2, 2.5 * px, true)
		draw_line(c + Vector2(-k, k), c + Vector2(k, -k), C_GLYPH_2, 2.5 * px, true)


var _px := 1.0
var _ring: Ring
var _badge: Badge
var _badge_at := Vector2.INF
var _tween: Tween = null
var _armed := false
var _rect := Rect2()


func _init() -> void:
	layer = 109  # over the game and its HUD (the help box); under ✓ / ✕ (placement_confirm.gd, 110) and the frame-rate readout (120)


func setup(px_per_pt: float) -> void:
	_px = px_per_pt
	_ring = Ring.new()
	_ring.name = "ArmedRing"
	_ring.px = _px
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.focus_mode = Control.FOCUS_NONE
	_ring.visible = false
	add_child(_ring)
	_badge = Badge.new()
	_badge.name = "UnqueueBadge"
	_badge.px = _px
	_badge.size = Vector2.ONE * (BADGE_PT + 4.0) * _px
	_badge.pivot_offset = _badge.size * 0.5
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.focus_mode = Control.FOCUS_NONE
	_badge.accessibility_name = "Cancel one"
	_badge.visible = false
	add_child(_badge)


## the ring around window rectangle `rect` for `seconds` (the arm window)
func arm(rect: Rect2, seconds: float) -> void:
	_rect = rect
	_armed = true
	hide_cancel()  # the touch layer shows it again for a button with a queue
	var r := maxf(rect.size.x, rect.size.y) * 0.5 + OUTSET_PT * _px
	var side := (r + HALO_PT * _px) * 2.0 + 4.0
	_ring.radius = r
	_ring.size = Vector2(side, side)
	_ring.pivot_offset = _ring.size * 0.5
	_ring.position = rect.get_center() - _ring.size * 0.5
	_ring.colour = C_ACCENT
	_ring.visible = true
	_ring.queue_redraw()
	_kill()
	var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
	_ring.modulate.a = 0.0
	_ring.scale = Vector2.ONE if reduce else Vector2.ONE * 1.12
	_tween = create_tween()
	_tween.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_ring, "modulate:a", 1.0, ARM_S)
	if not reduce:
		_tween.tween_property(_ring, "scale", Vector2.ONE, ARM_S)
	# the window running out: the ring fades over its last FADE_TAIL_S (eased in: it lets go slowly, then goes)
	_tween.chain().tween_interval(maxf(0.0, seconds - ARM_S - FADE_TAIL_S))
	_tween.chain().tween_property(_ring, "modulate:a", 0.0, FADE_TAIL_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_badge, "modulate:a", 0.0, FADE_TAIL_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## a tap used the button: a short bright flash, back to gold, and the arm window (`seconds`) again
func used(seconds: float) -> void:
	if not _armed:
		return
	_kill()
	var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
	_ring.modulate.a = 1.0
	_badge.modulate.a = 1.0
	_ring.scale = Vector2.ONE if reduce else Vector2.ONE * 1.08
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(t: float) -> void:
		_ring.colour = C_ACCENT_BRIGHT.lerp(C_ACCENT, t)
		_ring.queue_redraw(), 0.0, 1.0, USE_S)
	if not reduce:
		_tween.tween_property(_ring, "scale", Vector2.ONE, USE_S)
	_tween.chain().tween_interval(maxf(0.0, seconds - USE_S - FADE_TAIL_S))
	_tween.chain().tween_property(_ring, "modulate:a", 0.0, FADE_TAIL_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_badge, "modulate:a", 0.0, FADE_TAIL_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## lane IOS-37: the ✕ beside the ring, in direction `away` from the button's centre, inside `safe` and with its touch area off `avoid` (the command
## toolbar): the first of away, a quarter turn either way and the opposite side that fits; none fits: `away`'s, pulled into the safe area
func show_cancel(away: Vector2, safe: Rect2, avoid := Rect2()) -> void:
	if not _armed:
		return
	var d := away.normalized() if away.length() > 0.01 else Vector2.UP
	var reach := _ring.radius + (BADGE_GAP_PT + BADGE_PT * 0.5) * _px
	var m := (BADGE_PT * 0.5 + 4.0) * _px
	var hit := BADGE_HIT_PT * _px
	var at := (_rect.get_center() + d * reach).clamp(safe.position + Vector2(m, m), safe.end - Vector2(m, m))
	for dir in [d, d.orthogonal(), -d.orthogonal(), -d]:
		var c: Vector2 = _rect.get_center() + dir * reach
		var inside := safe.grow(-m).has_point(c)
		var clear := not avoid.has_area() or not avoid.intersects(Rect2(c - Vector2(hit, hit), Vector2(hit, hit) * 2.0))
		if inside and clear:
			at = c
			break
	var was := _badge.visible
	_badge_at = at
	_badge.position = at - _badge.size * 0.5
	_badge.visible = true
	if not was:
		_badge.modulate.a = 0.0
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(_badge, "modulate:a", 1.0, ARM_S)


func hide_cancel() -> void:
	_badge.visible = false
	_badge.pressed = false
	_badge_at = Vector2.INF


## a finger at `at` is on the ✕ (its BADGE_HIT_PT touch area)
func cancel_hit(at: Vector2) -> bool:
	return _armed and _badge.visible and _badge_at.is_finite() and at.distance_to(_badge_at) <= BADGE_HIT_PT * _px


func set_cancel_pressed(on: bool) -> void:
	if _badge.pressed == on:
		return
	_badge.pressed = on
	_badge.scale = Vector2.ONE * (0.94 if on and DisplayServer.accessibility_should_reduce_animation() != 1 else 1.0)
	_badge.queue_redraw()


## a tap elsewhere, another gesture or the time out: the ring fades
func disarm() -> void:
	if not _armed:
		return
	_armed = false
	_kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.set_parallel(true)
	_tween.tween_property(_ring, "modulate:a", 0.0, DISARM_S)
	if _badge.visible:
		_tween.tween_property(_badge, "modulate:a", 0.0, DISARM_S)
	_tween.chain().tween_callback(func() -> void:
		_ring.visible = false
		hide_cancel())


func is_armed() -> bool:
	return _armed


## the ring's state for the self-test: { armed, visible, centre, radius, rect }
func state() -> Dictionary:
	return {"armed": _armed, "visible": _ring.visible, "centre": _ring.position + _ring.size * 0.5, "radius": _ring.radius, "rect": _rect,
		"alpha": _ring.modulate.a, "cancel": _badge.visible, "cancel_at": _badge_at, "cancel_hit_radius": BADGE_HIT_PT * _px}


func _kill() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
