extends RefCounted
## Lane IOS-46 (a PROTOTYPE for the owner's choice): the small gesture pictures of the touch help (touch_tips.gd's tips and guide, touch_help_card.gd's
## card). Plain vectors drawn by Godot in the touch layer's colours: a finger is a filled disc with a halo, motion is a line with an arrow head, a hold is
## a ring that fills, a button is a rounded square. Nothing comes from the game's files.
##
## draw(item, name, centre, size, colour) draws picture `name` centred on `centre` in a `size` pixel square on CanvasItem `item` (inside its _draw).
## NAMES lists them; an unknown name draws nothing and returns false.

const NAMES := ["tap", "double", "drag", "hold", "hold_map", "tap2", "pan", "pinch", "twist", "two_tap", "confirm", "aim", "unqueue", "help"]

const C_FINGER_FILL := Color(0.94, 0.91, 0.84, 0.95)   # IOS-12's ivory: the finger
const C_HALO := Color(0.06, 0.06, 0.07, 0.55)


static func draw(item: CanvasItem, name: String, c: Vector2, size: float, colour: Color) -> bool:
	var u := size / 40.0  # the pictures are laid out on a 48 x 48 grid, drawn a little larger than their box's inner 40 (they fill it)
	var w := maxf(1.5, 2.25 * u)  # stroke
	match name:
		"tap":
			_ripple(item, c + Vector2(0, 3) * u, 13.0 * u, colour, w, 1)
			_finger(item, c + Vector2(0, 3) * u, 7.0 * u, colour)
		"double":
			_ripple(item, c + Vector2(0, 5) * u, 11.0 * u, colour, w, 2)
			_finger(item, c + Vector2(0, 5) * u, 7.0 * u, colour)
		"drag":
			var box := Rect2(c + Vector2(-17, -17) * u, Vector2(26, 24) * u)
			_dashed_rect(item, box, colour, w)
			_finger(item, box.end, 6.5 * u, colour)
			_arrow(item, box.position + Vector2(5, 5) * u, box.end - Vector2(9, 9) * u, colour, w, 5.0 * u)
		"hold", "hold_map":
			var at := c + Vector2(0, -1) * u
			item.draw_arc(at, 14.0 * u, 0.0, TAU, 48, Color(colour, 0.25), w, true)
			item.draw_arc(at, 14.0 * u, -PI * 0.5, -PI * 0.5 + TAU * 0.72, 40, colour, w * 1.2, true)
			_finger(item, at, 7.0 * u, colour)
			if name == "hold_map":
				# a ground line under the finger: the map, not a button
				item.draw_line(c + Vector2(-20, 19) * u, c + Vector2(20, 19) * u, Color(colour, 0.6), w, true)
		"tap2":
			var btn := Rect2(c + Vector2(-12, -6) * u, Vector2(24, 22) * u)
			_round_rect(item, btn, 5.0 * u, colour, w)
			item.draw_circle(c + Vector2(-5, -15) * u, 2.6 * u, colour, true, -1.0, true)
			item.draw_circle(c + Vector2(5, -15) * u, 2.6 * u, colour, true, -1.0, true)
			_finger(item, btn.get_center() + Vector2(0, 2) * u, 6.0 * u, colour)
		"pan":
			_finger(item, c + Vector2(-8, 4) * u, 6.0 * u, colour)
			_finger(item, c + Vector2(6, 4) * u, 6.0 * u, colour)
			_arrow(item, c + Vector2(-2, -8) * u, c + Vector2(-2, -21) * u, colour, w, 5.0 * u)
			_arrow(item, c + Vector2(13, -6) * u, c + Vector2(22, -6) * u, colour, w, 5.0 * u)
			_arrow(item, c + Vector2(-15, -6) * u, c + Vector2(-23, -6) * u, colour, w, 5.0 * u)
		"pinch":
			var a := c + Vector2(-8, 8) * u
			var b := c + Vector2(8, -8) * u
			_finger(item, a, 6.0 * u, colour)
			_finger(item, b, 6.0 * u, colour)
			_arrow(item, a + Vector2(-5, 5) * u, a + Vector2(-13, 13) * u, colour, w, 5.0 * u)
			_arrow(item, b + Vector2(5, -5) * u, b + Vector2(13, -13) * u, colour, w, 5.0 * u)
		"twist":
			var r := 14.0 * u
			item.draw_arc(c, r, -PI * 0.15, PI * 0.55, 24, colour, w, true)
			item.draw_arc(c, r, PI * 0.85, PI * 1.55, 24, colour, w, true)
			_head(item, c + Vector2.from_angle(PI * 0.55) * r, Vector2.from_angle(PI * 0.55 + PI * 0.5), colour, w, 5.0 * u)
			_head(item, c + Vector2.from_angle(PI * 1.55) * r, Vector2.from_angle(PI * 1.55 + PI * 0.5), colour, w, 5.0 * u)
			_finger(item, c + Vector2.from_angle(-PI * 0.15) * r, 5.5 * u, colour)
			_finger(item, c + Vector2.from_angle(PI * 0.85) * r, 5.5 * u, colour)
		"two_tap":
			_ripple(item, c + Vector2(-7, 0) * u, 11.0 * u, colour, w, 1)
			_ripple(item, c + Vector2(7, 0) * u, 11.0 * u, colour, w, 1)
			_finger(item, c + Vector2(-7, 0) * u, 6.0 * u, colour)
			_finger(item, c + Vector2(7, 0) * u, 6.0 * u, colour)
		"confirm":
			# ✕ left, ✓ right: IOS-26's pair
			var l := c + Vector2(-11, 0) * u
			var rr := c + Vector2(11, 0) * u
			item.draw_arc(l, 9.0 * u, 0.0, TAU, 32, Color(colour, 0.7), w, true)
			var k := 3.6 * u
			item.draw_line(l + Vector2(-k, -k), l + Vector2(k, k), Color(colour, 0.7), w, true)
			item.draw_line(l + Vector2(-k, k), l + Vector2(k, -k), Color(colour, 0.7), w, true)
			item.draw_arc(rr, 9.0 * u, 0.0, TAU, 32, colour, w * 1.15, true)
			item.draw_polyline(PackedVector2Array([rr + Vector2(-4.2, 0.2) * u, rr + Vector2(-1.2, 3.4) * u, rr + Vector2(4.6, -3.4) * u]), colour, w * 1.15, true)
		"aim":
			var spot := c + Vector2(0, -9) * u
			item.draw_arc(spot, 9.0 * u, 0.0, TAU, 32, colour, w, true)
			item.draw_circle(spot, 2.0 * u, colour, true, -1.0, true)
			item.draw_dashed_line(spot + Vector2(0, 10) * u, c + Vector2(0, 12) * u, Color(colour, 0.7), maxf(1.0, w * 0.8), 2.5 * u, true, true)
			_finger(item, c + Vector2(0, 16) * u, 6.0 * u, colour)
		"unqueue":
			var btn := Rect2(c + Vector2(-16, -10) * u, Vector2(22, 22) * u)
			_round_rect(item, btn, 5.0 * u, colour, w)
			var x := c + Vector2(13, -11) * u
			item.draw_arc(x, 7.0 * u, 0.0, TAU, 28, colour, w, true)
			var kk := 2.8 * u
			item.draw_line(x + Vector2(-kk, -kk), x + Vector2(kk, kk), colour, w, true)
			item.draw_line(x + Vector2(-kk, kk), x + Vector2(kk, -kk), colour, w, true)
		"help":
			item.draw_arc(c, 15.0 * u, 0.0, TAU, 40, colour, w, true)
			var q := PackedVector2Array()
			for i in 13:
				q.append(c + Vector2(0, -3.5) * u + Vector2.from_angle(lerpf(-PI * 1.05, PI * 0.35, i / 12.0)) * 5.5 * u)
			q.append(c + Vector2(0, 4.5) * u)
			item.draw_polyline(q, colour, w, true)
			item.draw_circle(c + Vector2(0, 9.5) * u, 1.7 * u, colour, true, -1.0, true)
		_:
			return false
	return true


## a fingertip: an ivory disc with a dark halo and a gold rim (reads on the map and on the dark surface alike)
static func _finger(item: CanvasItem, at: Vector2, r: float, colour: Color) -> void:
	item.draw_circle(at, r + maxf(1.0, r * 0.25), C_HALO, true, -1.0, true)
	item.draw_circle(at, r, C_FINGER_FILL, true, -1.0, true)
	item.draw_arc(at, r, 0.0, TAU, 28, colour, maxf(1.0, r * 0.22), true)


## `rings` short arcs above a point: a touch's ripple
static func _ripple(item: CanvasItem, at: Vector2, r: float, colour: Color, w: float, rings: int) -> void:
	for i in rings:
		var rr := r + i * 5.0 * (r / 12.0)
		item.draw_arc(at, rr, -PI * 0.85, -PI * 0.15, 20, Color(colour, 0.85 - 0.3 * i), w, true)


static func _arrow(item: CanvasItem, from: Vector2, to: Vector2, colour: Color, w: float, head: float) -> void:
	item.draw_line(from, to, colour, w, true)
	_head(item, to, (to - from).normalized(), colour, w, head)


static func _head(item: CanvasItem, tip: Vector2, dir: Vector2, colour: Color, w: float, head: float) -> void:
	if dir == Vector2.ZERO:
		return
	var back := tip - dir * head
	var side := dir.orthogonal() * head * 0.7
	item.draw_polyline(PackedVector2Array([back + side, tip, back - side]), colour, w, true)


static func _dashed_rect(item: CanvasItem, r: Rect2, colour: Color, w: float) -> void:
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		item.draw_dashed_line(p[i], p[(i + 1) % 4], colour, w, 3.0 * w, true, true)


static func _round_rect(item: CanvasItem, r: Rect2, radius: float, colour: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(radius, radius), PI], [Vector2(r.end.x - radius, r.position.y + radius), PI * 1.5],
		[r.end - Vector2(radius, radius), 0.0], [Vector2(r.position.x + radius, r.end.y - radius), PI * 0.5]]
	for k in corners:
		for i in 7:
			pts.append(k[0] + Vector2.from_angle(k[1] + i / 6.0 * PI * 0.5) * radius)
	pts.append(pts[0])
	item.draw_polyline(pts, colour, w, true)
