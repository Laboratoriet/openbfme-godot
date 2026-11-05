extends CanvasLayer
## Lane IOS-40 (the owner's decision, 2026-11-05: "click once to see name/info and twice to build is better"): the gold ring around a HUD button a first
## tap armed. The touch layer (touch_controls.gd) owns the gesture, the game calls and the help box; this layer only draws the ring around the button's
## window rectangle (InGameHudNode.touch_button_at's "rect") and takes no input (mouse_filter IGNORE).
##
##   armed ...... a gold ring (IOS-12's accent, as ✓'s) just outside the button's circle, over a soft dark halo so it reads on the Palantir's gold and on
##                bright ground; it stays for the arm window and fades out over its last FADE_TAIL_S (the window running out, without a sweep that could
##                be taken for the game's own recharge clock)
##   used ....... the second tap: the ring brightens and widens a little as it fades (USE_S): the press went through
##   disarmed ... a tap elsewhere, a gesture, the time out: the ring fades (DISARM_S)
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


var _px := 1.0
var _ring: Ring
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


## the ring around window rectangle `rect` for `seconds` (the arm window)
func arm(rect: Rect2, seconds: float) -> void:
	_rect = rect
	_armed = true
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


## the second tap used the button: a short bright flash as the ring goes
func used() -> void:
	if not _armed:
		return
	_armed = false
	_kill()
	var reduce := DisplayServer.accessibility_should_reduce_animation() == 1
	_ring.colour = C_ACCENT_BRIGHT
	_ring.queue_redraw()
	_ring.modulate.a = 1.0
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_ring, "modulate:a", 0.0, USE_S)
	if not reduce:
		_tween.tween_property(_ring, "scale", Vector2.ONE * 1.18, USE_S)
	_tween.chain().tween_callback(func() -> void: _ring.visible = false)


## a tap elsewhere, another gesture or the time out: the ring fades
func disarm() -> void:
	if not _armed:
		return
	_armed = false
	_kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_ring, "modulate:a", 0.0, DISARM_S)
	_tween.tween_callback(func() -> void: _ring.visible = false)


func is_armed() -> bool:
	return _armed


## the ring's state for the self-test: { armed, visible, centre, radius, rect }
func state() -> Dictionary:
	return {"armed": _armed, "visible": _ring.visible, "centre": _ring.position + _ring.size * 0.5, "radius": _ring.radius, "rect": _rect,
		"alpha": _ring.modulate.a}


func _kill() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
