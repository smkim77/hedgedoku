class_name Art
extends RefCounted
## Vector art from the web version's SVG symbols, drawn with CanvasItem calls:
## the hedgehog, the apple and the line icons (undo, hint, erase, restart, flag, help, podium).

const SPIKE := Color("6b4423")
const BODY := Color("a8743f")
const FACE := Color("f1d3a8")
const EAR := Color("e3b886")
const DARK := Color("2b1d12")
const CHEEK := Color(0.941, 0.561, 0.561, 0.75)

static var _spikes := PackedVector2Array()
static var _apple := PackedVector2Array()
static var _leaf := PackedVector2Array()
static var _stem := PackedVector2Array()


static func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, out: PackedVector2Array, steps := 10) -> void:
	for k in range(1, steps + 1):
		var t := float(k) / steps
		var u := 1.0 - t
		out.append(u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3)


static func _init_shapes() -> void:
	if not _spikes.is_empty():
		return
	# hedgehog spikes (same construction as the web version's buildSpikes)
	var cx := 57.0
	var cy := 62.0
	var k := 13
	_spikes.append(Vector2(cx, cy))
	for i in 2 * k + 1:
		var t := deg_to_rad(200.0 + (372.0 - 200.0) * i / (2 * k))
		var r := 41.0 if i % 2 == 1 else 31.0
		_spikes.append(Vector2(cx + r * cos(t), cy + r * sin(t) * 0.86))
	# apple body (absolute cubic segments of the web version's path)
	var segs := [
		[Vector2(10.8, 6), Vector2(8.2, 5.4), Vector2(6.4, 7.2)],
		[Vector2(4.5, 9.1), Vector2(4.8, 13), Vector2(6.6, 16.2)],
		[Vector2(8, 18.7), Vector2(9.6, 20.3), Vector2(11, 19.8)],
		[Vector2(11.6, 19.6), Vector2(11.8, 19.4), Vector2(12, 19.4)],
		[Vector2(12.2, 19.4), Vector2(12.4, 19.6), Vector2(13, 19.8)],
		[Vector2(14.4, 20.3), Vector2(16, 18.7), Vector2(17.4, 16.2)],
		[Vector2(19.2, 13), Vector2(19.5, 9.1), Vector2(17.6, 7.2)],
		[Vector2(15.8, 5.4), Vector2(13.2, 6), Vector2(12, 7)],
	]
	var p := Vector2(12, 7)
	_apple.append(p)
	for s in segs:
		_cubic(p, s[0], s[1], s[2], _apple, 6)
		p = s[2]
	_apple.remove_at(_apple.size() - 1)
	_leaf.append(Vector2(13, 4.6))
	_cubic(Vector2(13, 4.6), Vector2(14.6, 3.5), Vector2(16.4, 3.6), Vector2(17.4, 4.2), _leaf, 6)
	_cubic(Vector2(17.4, 4.2), Vector2(16.4, 5.7), Vector2(14.6, 6.2), Vector2(13, 4.6), _leaf, 6)
	_leaf.remove_at(_leaf.size() - 1)
	_stem.append(Vector2(12, 7))
	_cubic(Vector2(12, 7), Vector2(12, 5.4), Vector2(12.6, 4), Vector2(13.6, 3), _stem, 6)


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


static func _xf(pts: PackedVector2Array, origin: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = origin + pts[i] * s
	return out


## Hedgehog filling `rect` (the 100×100 viewBox scaled to it).
static func hog(ci: CanvasItem, rect: Rect2, alpha := 1.0) -> void:
	_init_shapes()
	var s := minf(rect.size.x, rect.size.y) / 100.0
	var o := rect.position + (rect.size - Vector2(100, 100) * s) / 2
	var a := func(c: Color) -> Color: return Color(c, c.a * alpha)
	ci.draw_colored_polygon(_xf(_spikes, o, s), a.call(SPIKE))
	ellipse(ci, o + Vector2(56, 63) * s, 33 * s, 24 * s, a.call(BODY))
	ellipse(ci, o + Vector2(40, 87) * s, 6 * s, 3.5 * s, a.call(SPIKE))
	ellipse(ci, o + Vector2(70, 87) * s, 6 * s, 3.5 * s, a.call(SPIKE))
	ellipse(ci, o + Vector2(29, 67) * s, 20 * s, 15.5 * s, a.call(FACE))
	ci.draw_circle(o + Vector2(41, 53) * s, 5 * s, a.call(EAR))
	ci.draw_circle(o + Vector2(11, 69) * s, 4.2 * s, a.call(DARK))
	ci.draw_circle(o + Vector2(27, 61) * s, 3.3 * s, a.call(DARK))
	ci.draw_circle(o + Vector2(28.2, 59.8) * s, 1.1 * s, a.call(Color.WHITE))
	ellipse(ci, o + Vector2(33, 71) * s, 4.2 * s, 2.6 * s, a.call(CHEEK))


## Apple filling `rect` (24×24 viewBox). `gray` draws the used-up apple.
static func apple(ci: CanvasItem, rect: Rect2, gray := false, alpha := 1.0) -> void:
	_init_shapes()
	var s := minf(rect.size.x, rect.size.y) / 24.0
	var o := rect.position + (rect.size - Vector2(24, 24) * s) / 2
	var red := Color("d9483b")
	var brown := SPIKE
	var green := Color("6aa84f")
	if gray:
		red = Color(0.62, 0.6, 0.57)
		brown = Color(0.5, 0.48, 0.45)
		green = Color(0.66, 0.64, 0.6)
	ci.draw_colored_polygon(_xf(_apple, o, s), Color(red, alpha))
	ci.draw_polyline(_xf(_stem, o, s), Color(brown, alpha), 1.4 * s, true)
	ci.draw_colored_polygon(_xf(_leaf, o, s), Color(green, alpha))


static func _arc(c: Vector2, r: float, a0: float, a1: float, steps := 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / steps))
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _icon_lines(name: String) -> Array:
	match name:
		"undo":
			var p := PackedVector2Array([Vector2(4, 9), Vector2(14.5, 9)])
			p.append_array(_arc(Vector2(14.5, 14.5), 5.5, -90, 90))
			p.append(Vector2(11, 20))
			return [PackedVector2Array([Vector2(9, 14), Vector2(4, 9), Vector2(9, 4)]), p]
		"hint":
			var b := _arc(Vector2(12, 9), 7, 124.85, 415.15, 24)
			b.append_array(PackedVector2Array([Vector2(15, 16.7), Vector2(15, 18), Vector2(9, 18), Vector2(9, 16.7), Vector2(8, 14.7)]))
			return [b, PackedVector2Array([Vector2(9, 18), Vector2(15, 18)]), PackedVector2Array([Vector2(10, 22), Vector2(14, 22)])]
		"erase":
			return [PackedVector2Array([Vector2(7, 21), Vector2(2.7, 16.7), Vector2(2.7, 15.3), Vector2(12.7, 5.3), Vector2(14.1, 5.3),
					Vector2(19.7, 10.9), Vector2(19.7, 12.3), Vector2(13, 19)]),
				PackedVector2Array([Vector2(22, 21), Vector2(7, 21)]), PackedVector2Array([Vector2(5, 11), Vector2(14, 20)])]
		"restart":
			var a := _arc(Vector2(12, 12), 9, 180, -137, 32)
			a.append(Vector2(3, 8))
			return [a, PackedVector2Array([Vector2(3, 3), Vector2(3, 8), Vector2(8, 8)])]
		"flag":
			return [PackedVector2Array([Vector2(5, 22), Vector2(5, 3)]),
				PackedVector2Array([Vector2(5, 4), Vector2(18, 4), Vector2(15.5, 8.5), Vector2(18, 13), Vector2(5, 13)])]
		"help":
			return [_arc(Vector2(12, 12), 10, 0, 360, 36),
				PackedVector2Array([Vector2(9.1, 9), Vector2(10, 7.4), Vector2(12, 6.9), Vector2(14, 7.6), Vector2(14.9, 9.2), Vector2(14.9, 10),
					Vector2(14.4, 11.3), Vector2(13.2, 12.2), Vector2(12, 13)])]
		"podium":
			return [PackedVector2Array([Vector2(9, 21), Vector2(9, 9), Vector2(15, 9), Vector2(15, 21)]),
				PackedVector2Array([Vector2(3, 21), Vector2(3, 14), Vector2(9, 14)]),
				PackedVector2Array([Vector2(15, 21), Vector2(15, 16), Vector2(21, 16), Vector2(21, 21)]),
				PackedVector2Array([Vector2(2, 21), Vector2(22, 21)])]
	return []


## Line icon (24×24 viewBox, 2px round strokes) filling `rect`.
static func icon(ci: CanvasItem, name: String, rect: Rect2, col: Color) -> void:
	var s := minf(rect.size.x, rect.size.y) / 24.0
	var o := rect.position + (rect.size - Vector2(24, 24) * s) / 2
	var w := maxf(1.5, 2.0 * s)
	for line in _icon_lines(name):
		var pts := _xf(line, o, s)
		ci.draw_polyline(pts, col, w, true)
		for q in [pts[0], pts[pts.size() - 1]]:
			ci.draw_circle(q, w / 2, col)
	if name == "help":
		ci.draw_circle(o + Vector2(12, 17) * s, w * 0.6, col)
	elif name == "podium":
		var star := PackedVector2Array()
		for i in 10:
			var a := deg_to_rad(-90 + 36 * i)
			star.append(o + (Vector2(12, 5.2) + Vector2(cos(a), sin(a)) * (2.9 if i % 2 == 0 else 1.25)) * s)
		ci.draw_colored_polygon(star, col)
