## IconView: small icons drawn in code (heart, coin, star, shovel).
##
## One Control class with a `kind` string, and _draw() picks the drawing.
## A simple alternative to image files, and a nice example of using
## draw_* functions inside a Control (which then works in containers).
class_name IconView
extends Control

var kind: String = "star"
var icon_size: float = 40.0


func _init(p_kind: String = "star", p_size: float = 40.0) -> void:
	kind = p_kind
	icon_size = p_size
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Draw in the middle of whatever space the container gave us.
	var c := size / 2.0
	var r := icon_size * 0.45
	var outline := Color(0.12, 0.06, 0.02)
	match kind:
		"heart":
			# A heart outline from the classic parametric "heart curve".
			var points := PackedVector2Array()
			# 32 points; no repeated closing point, because draw_colored_polygon
			# can't triangulate a polygon whose first and last points are equal.
			for i in 32:
				# The classic "heart curve" from math class, scaled to our size.
				var t := i * TAU / 32.0
				var x := 16.0 * pow(sin(t), 3.0)
				var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
				points.append(c + Vector2(x, y) * (r / 17.0))
			draw_colored_polygon(points, UIStyle.HEART)
			UIStyle.draw_outline(self, points, outline, 2.0)
			draw_circle(c + Vector2(-r * 0.4, -r * 0.35), r * 0.15, Color(1, 1, 1, 0.6))
		"coin":
			draw_circle(c, r, UIStyle.COIN.darkened(0.25))
			draw_circle(c, r * 0.8, UIStyle.COIN)
			draw_arc(c, r, 0.0, TAU, 24, outline, 2.0, true)
			# A "$"-like mark: a vertical bar in the middle.
			draw_rect(Rect2(c - Vector2(r * 0.12, r * 0.45), Vector2(r * 0.24, r * 0.9)), UIStyle.COIN.darkened(0.3))
		"shovel":
			draw_line(c + Vector2(-r * 0.7, -r * 0.7), c + Vector2(r * 0.15, r * 0.15), Color(0.55, 0.35, 0.15), r * 0.25, true)
			draw_line(c + Vector2(-r * 0.9, -r * 0.5), c + Vector2(-r * 0.5, -r * 0.9), Color(0.55, 0.35, 0.15), r * 0.25, true)
			var blade := PackedVector2Array([
				c + Vector2(0.0, r * 0.25), c + Vector2(r * 0.25, 0.0),
				c + Vector2(r * 0.95, r * 0.6), c + Vector2(r * 0.6, r * 0.95)])
			draw_colored_polygon(blade, Color(0.75, 0.78, 0.82))
			UIStyle.draw_outline(self, blade, outline, 2.0)
		_:
			var star := UIStyle.star_points(c, r, r * 0.45)
			draw_colored_polygon(star, UIStyle.ACCENT)
			UIStyle.draw_outline(self, star, outline, 2.0)
