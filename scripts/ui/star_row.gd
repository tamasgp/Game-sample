## StarRow: a tiny custom Control that draws "★★☆" style ratings.
##
## CUSTOM DRAWING
## --------------
## Any CanvasItem (Node2D or Control) can override _draw() and use draw_*
## functions (draw_circle, draw_polygon, draw_line, ...). Godot calls _draw()
## once and caches the result; call queue_redraw() whenever the picture needs
## to change. Here, the `filled` setter does that automatically.
##
## We draw stars ourselves instead of using the "★" text character because
## not every font contains that character.
class_name StarRow
extends Control

## How many stars are filled in. Setting it redraws the control.
## (This is a GDScript "property with a setter": `stars.filled = 2` runs the
## code in `set(value)`.)
var filled: int = 0:
	set(value):
		filled = value
		queue_redraw()

var total: int = 3
var star_size: float = 28.0


func _init(p_filled: int = 0, p_star_size: float = 28.0, p_total: int = 3) -> void:
	filled = p_filled
	star_size = p_star_size
	total = p_total
	# Tell containers how much space we need.
	custom_minimum_size = Vector2(star_size * 2.2 * total, star_size * 2.2)
	# This control is only decoration: let clicks pass through it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var spacing := star_size * 2.2
	# Center the row of stars inside whatever size the container gave us.
	var start_x := (size.x - spacing * total) / 2.0 + spacing / 2.0
	for i in total:
		var center := Vector2(start_x + i * spacing, size.y / 2.0)
		var points := UIStyle.star_points(center, star_size, star_size * 0.45)
		var color := UIStyle.ACCENT if i < filled else Color(0.2, 0.25, 0.35)
		draw_colored_polygon(points, color)
		UIStyle.draw_outline(self, points, Color(0.05, 0.05, 0.1), 2.0)
