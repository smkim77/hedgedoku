class_name BoardView
extends Control
## The puzzle board: draws regions, × marks, hedgehogs and the quill / mark animations, and turns
## mouse / touch / keyboard input into taps and drags. Game state lives in main.gd (`game`).

const LINE := Color("3b3226")
const GRID := Color(0.231, 0.196, 0.149, 0.16)
const SHADE := Color(0.18, 0.133, 0.078, 0.36)
const XCOL := Color("5c5142")
const DANGER := Color("c0443b")
const RING := Color("e0a456")
const REGION := [Color("fac6c1"), Color("fcd9b0"), Color("f9efad"), Color("e0f3b2"), Color("c2eac3"),
	Color("b6eae2"), Color("c0def7"), Color("cbcff8"), Color("dfc9f6"), Color("f6c8ec"), Color("e5dac9")]
const QUILL_S_PER_CELL := 0.055
const DIRS := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const BORDER := 3.0

var game: Node
var font: Font
var narrow := false            # phone-width layout: thinner region lines

# animation state (times in seconds, from now())
var pop := {}                  # cell -> start of the hedgehog pop
var stab := {}                 # cell -> start of the × mark animation
var ouch := {}                 # cell -> start of the wrong-placement shake (mark stays red while it is ×)
var glow := {}                 # cell -> start of the hint glow
var puff := {}                 # cell -> start of an idle puff
var quills := []               # {t0, dur, from: Vector2, dir: Vector2, start, end}
var revealed := false          # show the solution as faint hedgehogs (after a loss)
var fatal := -1
var shake_t0 := -10.0
var veiled := false
var cursor := 0                # keyboard cursor
var show_cursor := false

var blocked_until := 0.0     # input is ignored until then (right after a new board appears)
var press = null               # {i, last, moved, drag, pos, armed}
var _prev := []                # cell values at the last sync, to start animations on change


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false


func reset() -> void:
	pop.clear(); stab.clear(); ouch.clear(); glow.clear(); puff.clear(); quills.clear()
	revealed = false
	fatal = -1
	shake_t0 = -10.0
	_prev = game.cells.duplicate()
	cursor = clampi(cursor, 0, game.cells.size() - 1)
	queue_redraw()


## Called after every state change: new hedgehogs pop in.
func sync() -> void:
	var t := now()
	var cells: Array = game.cells
	for i in cells.size():
		var old = _prev[i] if i < _prev.size() else 0
		if cells[i] == 2 and old != 2:
			pop[i] = t
		if cells[i] != 1:
			ouch.erase(i)
	_prev = cells.duplicate()
	queue_redraw()


func n() -> int:
	return game.P.N


## Ignore board input for a moment, so taps meant for a just-closed card (or queued while the next
## puzzle was being made) don't land on the new board as × marks or hedgehogs.
func block_input(sec: float) -> void:
	blocked_until = now() + sec
	press = null


func cell_size() -> float:
	return (size.x - BORDER * 2) / n()


func cell_rect(i: int) -> Rect2:
	var cs := cell_size()
	return Rect2(BORDER + (i % n()) * cs, BORDER + (i / n()) * cs, cs, cs)


func cell_at(p: Vector2) -> int:
	var cs := cell_size()
	var col := int(floor((p.x - BORDER) / cs))
	var row := int(floor((p.y - BORDER) / cs))
	if row < 0 or row >= n() or col < 0 or col >= n():
		return -1
	return row * n() + col


# ---------- effects ----------

## Quills fly along the row, column and (one step) diagonals; new × marks land as a quill passes them.
func play_quills(i: int, newly: Array) -> void:
	var N := n()
	var r0 := i / N
	var c0 := i % N
	var t := now()
	for j in newly:
		var dr: int = j / N - r0
		var dc: int = j % N - c0
		var on_line: bool = dr == 0 or dc == 0 or (absi(dr) <= 1 and absi(dc) <= 1)
		var dist: int = maxi(absi(dr), absi(dc)) if on_line else ceili(N / 2.0) + 1
		stab[j] = t + dist * QUILL_S_PER_CELL
	var cs := cell_size()
	var from := cell_rect(i).get_center()
	for d in DIRS:
		var dr: int = d.x
		var dc: int = d.y
		var diag := dr != 0 and dc != 0
		var to_edge := 1 << 20
		if dr > 0: to_edge = mini(to_edge, N - 1 - r0)
		elif dr < 0: to_edge = mini(to_edge, r0)
		if dc > 0: to_edge = mini(to_edge, N - 1 - c0)
		elif dc < 0: to_edge = mini(to_edge, c0)
		var steps := mini(1, to_edge) if diag else to_edge
		if steps <= 0:
			continue
		var dir := Vector2(dc, dr).normalized()
		quills.append({"t0": t, "dur": steps * QUILL_S_PER_CELL + 0.04, "from": from, "dir": dir,
			"start": cs * 0.25, "end": steps * cs * (sqrt(2.0) if diag else 1.0)})
	queue_redraw()


func mark_now(i: int) -> void:
	stab[i] = now()


func play_ouch(i: int) -> void:
	ouch[i] = now()
	queue_redraw()


func play_glow(i: int) -> void:
	glow[i] = now()


func play_puff(i: int) -> void:
	puff[i] = now()
	play_quills(i, [])


func shake() -> void:
	shake_t0 = now()
	queue_redraw()


func animating() -> bool:
	var t := now()
	if not quills.is_empty() or t - shake_t0 < 0.6:
		return true
	for d in [pop, stab, ouch, glow, puff]:
		for k in d:
			if t - d[k] < 3.0:
				return true
	return false


func _process(_dt: float) -> void:
	if animating():
		queue_redraw()


# ---------- drawing ----------

func _draw() -> void:
	if game == null or game.P == null:
		return
	var t := now()
	var N := n()
	var cs := cell_size()
	var P = game.P
	var cells: Array = game.cells
	var off := Vector2.ZERO
	var st := t - shake_t0
	if st < 0.5:
		var k := st / 0.5
		off.x = [0.0, -7.0, 6.0, -4.0, 2.0, 0.0][int(k * 5)] if k < 1.0 else 0.0
	draw_set_transform(off)
	# frame
	var frame := StyleBoxFlat.new()
	frame.bg_color = LINE
	frame.set_corner_radius_all(10)
	draw_style_box(frame, Rect2(Vector2.ZERO, size))
	for i in N * N:
		var r := cell_rect(i)
		var sh := Vector2.ZERO
		if ouch.has(i) and t - ouch[i] < 0.35:
			sh.x = sin((t - ouch[i]) / 0.35 * TAU * 2) * 4
		draw_rect(Rect2(r.position + sh, r.size), REGION[P.colors[P.reg[i]]])
		if cells[i] == 1:
			var a := 1.0
			if stab.has(i):
				a = clampf((t - stab[i]) / 0.2, 0.0, 1.0)
			draw_rect(Rect2(r.position + sh, r.size), Color(SHADE, SHADE.a * a))
	# thin grid
	for k in range(1, N):
		var p := BORDER + k * cs
		draw_line(Vector2(p, BORDER), Vector2(p, size.y - BORDER), GRID, 1.0)
		draw_line(Vector2(BORDER, p), Vector2(size.x - BORDER, p), GRID, 1.0)
	# region borders
	var rb := 5.0 if not narrow else (2.2 if N >= 9 else 3.0)
	for i in N * N:
		var r := cell_rect(i)
		var row := i / N
		var col := i % N
		if col < N - 1 and P.reg[i] != P.reg[i + 1]:
			draw_line(Vector2(r.end.x, r.position.y - rb / 2), Vector2(r.end.x, r.end.y + rb / 2), LINE, rb)
		if row < N - 1 and P.reg[i] != P.reg[i + N]:
			draw_line(Vector2(r.position.x - rb / 2, r.end.y), Vector2(r.end.x + rb / 2, r.end.y), LINE, rb)
	# round off the inner corners
	var rad := 7.0
	for c in 4:
		var cx := BORDER if c % 2 == 0 else size.x - BORDER
		var cy := BORDER if c < 2 else size.y - BORDER
		var sx := 1.0 if c % 2 == 0 else -1.0
		var sy := 1.0 if c < 2 else -1.0
		var pts := PackedVector2Array([Vector2(cx, cy)])
		for k in 9:
			var a := PI / 2 * k / 8.0
			pts.append(Vector2(cx + sx * (rad - rad * sin(a)), cy + sy * (rad - rad * cos(a))))
		draw_colored_polygon(pts, LINE)
	# marks and hedgehogs
	var mark_size := int(clampf(cs * 0.42, 12, 26))
	for i in N * N:
		var r := cell_rect(i)
		var sh := Vector2.ZERO
		if ouch.has(i) and t - ouch[i] < 0.35:
			sh.x = sin((t - ouch[i]) / 0.35 * TAU * 2) * 4
		var v = cells[i]
		if v == 1:
			var k := 1.0
			if stab.has(i):
				k = clampf((t - stab[i]) / 0.24, 0.0, 1.0)
			if k > 0.0:
				var e := _back(k)
				var sc := lerpf(1.9, 1.0, e)
				var rot := deg_to_rad(lerpf(-25.0, 0.0, e))
				var col := DANGER if ouch.has(i) else Color(XCOL, 0.85)
				col.a *= k
				var c := r.get_center() + sh
				draw_set_transform(c + off, rot, Vector2(sc, sc))
				var w := font.get_string_size("×", HORIZONTAL_ALIGNMENT_LEFT, -1, mark_size).x
				draw_string(font, Vector2(-w / 2, mark_size * 0.36), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, mark_size, col)
				draw_set_transform(off)
		elif v == 2:
			var k := 1.0
			if pop.has(i):
				k = _back(clampf((t - pop[i]) / 0.28, 0.0, 1.0), 2.4)
				k = lerpf(0.3, 1.0, k)
			if puff.has(i):
				var pt: float = (t - puff[i]) / 0.35
				if pt < 1.0:
					k *= 1.0 + 0.18 * (pt / 0.4 if pt < 0.4 else (1.0 - pt) / 0.6)
			var hs := r.size.x * 0.82 * k
			Art.hog(self, Rect2(r.get_center() + sh - Vector2(hs, hs) / 2, Vector2(hs, hs)))
		if revealed and v != 2 and P.sol[i / N] == i % N:
			var hs := r.size.x * 0.82
			Art.hog(self, Rect2(r.get_center() - Vector2(hs, hs) / 2, Vector2(hs, hs)), 0.5)
		if glow.has(i):
			var gt: float = t - glow[i]
			if gt < 2.8:
				var a := 1.0 - fmod(gt, 1.4) / 1.4
				_ring(r.grow(-3), Color(RING, a), 3.0, 8)
	if fatal >= 0:
		_ring(cell_rect(fatal).grow(-2), DANGER, 3.0, 6)
	if show_cursor and has_focus():
		_ring(cell_rect(cursor).grow(-3), RING, 3.0, 4)
	# quills
	var alive := []
	for q in quills:
		var qt: float = (t - q.t0) / q.dur
		if qt >= 1.0:
			continue
		alive.append(q)
		var d: float = lerpf(q.start, q.end, qt)
		var a := 1.0 if qt < 0.9 else 1.0 - (qt - 0.9) / 0.1
		var tip: Vector2 = q.from + q.dir * d
		var back: Vector2 = tip - q.dir * 18.0
		var nrm := Vector2(-q.dir.y, q.dir.x) * 1.5
		draw_polygon(PackedVector2Array([back + nrm, tip, back - nrm]),
			PackedColorArray([Color(Art.BODY, a), Color(0.29, 0.184, 0.086, a), Color(Art.BODY, a)]))
	quills = alive
	# frame border on top, red after a loss
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.border_color = DANGER if st < 0.6 or fatal >= 0 else LINE
	border.set_border_width_all(int(BORDER))
	border.set_corner_radius_all(10)
	draw_style_box(border, Rect2(Vector2.ZERO, size))
	if veiled:
		var veil := StyleBoxFlat.new()
		veil.bg_color = Color(0.914, 0.925, 0.878, 0.82)
		veil.set_corner_radius_all(10)
		draw_style_box(veil, Rect2(Vector2.ZERO, size))
	draw_set_transform(Vector2.ZERO)


func _ring(r: Rect2, col: Color, w: float, radius: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = col
	sb.set_border_width_all(int(w))
	sb.set_corner_radius_all(radius)
	draw_style_box(sb, r)


static func _back(x: float, s := 1.6) -> float:
	# overshooting ease, like cubic-bezier(.2, 1.6, .4, 1)
	var c3 := s + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3) + s * pow(x - 1.0, 2)


# ---------- input ----------

func drag_threshold() -> float:
	return maxf(8.0, cell_size() * 0.35)


func _gui_input(ev: InputEvent) -> void:
	if game == null or game.P == null:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if now() < blocked_until:
				accept_event()
				return
			show_cursor = false
			var i := cell_at(ev.position)
			if i < 0 or not game.playing():
				return
			var v = game.cells[i]
			press = {"i": i, "last": i, "moved": false, "drag": "mark" if v == 0 else ("erase" if v == 1 else ""),
				"pos": ev.position, "armed": false}
			cursor = i
			accept_event()
		elif press != null:
			var p = press
			press = null
			if not p.moved:
				game.tap(p.i)
			else:
				game.drag_done()
			accept_event()
	elif ev is InputEventMouseMotion and press != null:
		_drag_to(ev.position)
		accept_event()
	elif ev is InputEventKey and ev.pressed and now() >= blocked_until:
		_key(ev)


func _drag_to(pos: Vector2) -> void:
	if not press.armed:
		if pos.distance_to(press.pos) < drag_threshold():
			return
		press.armed = true
	var j := cell_at(pos)
	if j < 0 or j == press.last:
		return
	if press.drag == "":
		press.moved = true
		press.last = j
		return
	var N := n()
	var from := 0 if press.drag == "mark" else 1
	var to := 1 if press.drag == "mark" else 0
	var changed := false
	var cells: Array = game.cells
	if not press.moved:
		press.moved = true
		game.push_history()
		cells[press.i] = to
		changed = true
		if to == 1:
			mark_now(press.i)
	var r0: int = press.last / N
	var c0: int = press.last % N
	var r1 := j / N
	var c1 := j % N
	var steps := maxi(absi(r1 - r0), absi(c1 - c0))
	for k in range(1, steps + 1):
		var idx := int(round(r0 + (r1 - r0) * float(k) / steps)) * N + int(round(c0 + (c1 - c0) * float(k) / steps))
		if cells[idx] == from:
			cells[idx] = to
			changed = true
			if to == 1:
				mark_now(idx)
	press.last = j
	if changed:
		game.render()


func _key(ev: InputEventKey) -> void:
	var N := n()
	var mv := {KEY_UP: -N, KEY_DOWN: N, KEY_LEFT: -1, KEY_RIGHT: 1}
	if mv.has(ev.keycode):
		var j: int = cursor + mv[ev.keycode]
		if j >= 0 and j < N * N and not (absi(mv[ev.keycode]) == 1 and j / N != cursor / N):
			cursor = j
		show_cursor = true
		queue_redraw()
		accept_event()
	elif ev.keycode == KEY_SPACE:
		show_cursor = true
		game.tap(cursor)
		accept_event()
	elif ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER:
		show_cursor = true
		game.place_direct(cursor)
		accept_event()
