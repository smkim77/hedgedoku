class_name DrawBox
extends Control
## A small drawn picture: the hedgehog, an apple (with the "lost apple" drop animation), the hint
## button's "−🍎" badge, or one of the line icons from Art.

var kind := "hog"
var color := Color("2e2a21")
var gray := false
var drop := false
var born := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	if drop and Time.get_ticks_msec() / 1000.0 - born < 0.7:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		"hog":
			Art.hog(self, r)
		"apple":
			var t := Time.get_ticks_msec() / 1000.0 - born
			if drop and t < 0.6:
				# the apple just lost: pops up, then falls and fades to the used-up look
				var k := t / 0.6
				var sc := lerpf(1.35, 1.2, k / 0.4) if k < 0.4 else lerpf(1.2, 0.85, (k - 0.4) / 0.6)
				var dy := lerpf(0.0, -4.0, k / 0.4) if k < 0.4 else lerpf(-4.0, 6.0, (k - 0.4) / 0.6)
				var s := r.size * sc
				var rr := Rect2(r.get_center() - s / 2 + Vector2(0, dy), s)
				Art.apple(self, rr, k > 0.4, 1.0 if k < 0.4 else lerpf(1.0, 0.3, (k - 0.4) / 0.6))
			elif gray:
				var s := r.size * 0.85
				Art.apple(self, Rect2(r.get_center() - s / 2, s), true, 0.3)
			else:
				Art.apple(self, r)
		"badge":
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("f6f7ef")
			sb.border_color = Color(0.231, 0.196, 0.149, 0.16)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(9)
			draw_style_box(sb, r)
			var f := get_theme_default_font()
			draw_string(f, Vector2(5, size.y * 0.74), "−", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("2e2a21"))
			Art.apple(self, Rect2(Vector2(15, 2), Vector2(size.y - 4, size.y - 4)))
		_:
			Art.icon(self, kind, r, color)
