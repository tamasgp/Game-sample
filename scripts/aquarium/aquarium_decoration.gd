## AquariumDecoration: plants, rocks, coral, a treasure chest and a castle.
##
## The node's position is the point where the decoration touches the sand,
## and everything is drawn UPWARDS from there (negative y). This "anchor at the
## bottom" convention makes placing objects on the ground easy.
class_name AquariumDecoration
extends Node2D

var shape: String = "rock"
var color: Color = Color.GRAY
var size_factor: float = 1.0
var _time: float = 0.0


func setup(item: Dictionary) -> void:
	shape = item["shape"]
	color = item["color"]
	size_factor = item["scale"]
	_time = randf() * 10.0


func _process(delta: float) -> void:
	_time += delta
	# Only plants move, so only they need to be redrawn every frame.
	if shape == "plant":
		queue_redraw()


func _draw() -> void:
	match shape:
		"plant":
			_draw_plant()
		"rock":
			_draw_rock()
		"coral":
			_draw_coral(Vector2.ZERO, -PI / 2.0, 70.0 * size_factor, 4)
		"chest":
			_draw_chest()
		"castle":
			_draw_castle()


## Seaweed: several blades, each a line that sways more toward its tip.
func _draw_plant() -> void:
	var height := 170.0 * size_factor
	for blade in 5:
		var base := Vector2((blade - 2) * 12.0, 0)
		var points := PackedVector2Array()
		var segments := 10
		for i in segments + 1:
			var t := float(i) / segments          # 0 at the base, 1 at the tip
			var sway := sin(_time * 1.5 + blade * 0.9 + t * 2.5) * 14.0 * t
			var blade_height := height * (0.7 + 0.15 * (blade % 3))
			points.append(base + Vector2(sway + (blade - 2) * 6.0 * t, -blade_height * t))
		var c := color.lightened(0.1 * (blade % 2))
		draw_polyline(points, c, 9.0, true)


## A rock: a lumpy polygon. The "random" radii are fixed numbers, so the rock
## looks the same every frame (truly random values would make it jitter).
func _draw_rock() -> void:
	var radii := [1.0, 0.85, 0.95, 0.8, 1.05, 0.9, 1.0, 0.88, 0.97, 0.83]
	var points := PackedVector2Array()
	for i in radii.size():
		var angle := PI + i * PI / (radii.size() - 1)  # upper half only
		var r: float = radii[i] * 60.0 * size_factor
		points.append(Vector2(cos(angle) * r * 1.4, sin(angle) * r))
	draw_colored_polygon(points, color)
	draw_circle(Vector2(-25, -35) * size_factor, 10.0 * size_factor, color.lightened(0.25))


## Coral: a recursive "tree". Each branch draws itself, then two smaller
## branches at angles. Recursion is a neat way to draw natural shapes.
func _draw_coral(start: Vector2, angle: float, branch_length: float, depth: int) -> void:
	if depth == 0:
		draw_circle(start, 6.0, color.lightened(0.3))
		return
	var end := start + Vector2(cos(angle), sin(angle)) * branch_length
	draw_line(start, end, color, depth * 3.5, true)
	_draw_coral(end, angle - 0.45, branch_length * 0.7, depth - 1)
	_draw_coral(end, angle + 0.4, branch_length * 0.7, depth - 1)


func _draw_chest() -> void:
	var s := size_factor
	var body := Rect2(Vector2(-55, -60) * s, Vector2(110, 60) * s)
	draw_rect(body, color)
	draw_rect(body, color.darkened(0.4), false, 4.0)
	# Lid, slightly open, with gold coins peeking out.
	draw_circle(Vector2(-20, -62) * s, 10 * s, Color(1, 0.85, 0.2))
	draw_circle(Vector2(5, -66) * s, 10 * s, Color(1, 0.85, 0.2))
	draw_circle(Vector2(25, -62) * s, 10 * s, Color(1, 0.85, 0.2))
	var lid := PackedVector2Array([
		Vector2(-58, -62) * s, Vector2(58, -78) * s, Vector2(58, -98) * s, Vector2(-58, -86) * s])
	draw_colored_polygon(lid, color.lightened(0.1))
	# Gold bands and lock.
	draw_rect(Rect2(Vector2(-35, -60) * s, Vector2(8, 60) * s), Color(0.9, 0.75, 0.2))
	draw_rect(Rect2(Vector2(27, -60) * s, Vector2(8, 60) * s), Color(0.9, 0.75, 0.2))
	draw_rect(Rect2(Vector2(-8, -45) * s, Vector2(16, 18) * s), Color(0.95, 0.8, 0.25))


func _draw_castle() -> void:
	var s := size_factor
	var dark := color.darkened(0.3)
	# Main wall and two towers.
	draw_rect(Rect2(Vector2(-70, -110) * s, Vector2(140, 110) * s), color)
	draw_rect(Rect2(Vector2(-100, -170) * s, Vector2(45, 170) * s), color)
	draw_rect(Rect2(Vector2(55, -170) * s, Vector2(45, 170) * s), color)
	# Crenellations (the "teeth" on top of castle walls).
	for i in 3:
		draw_rect(Rect2(Vector2(-100 + i * 16, -185) * s, Vector2(10, 15) * s), color)
		draw_rect(Rect2(Vector2(55 + i * 16, -185) * s, Vector2(10, 15) * s), color)
	for i in 5:
		draw_rect(Rect2(Vector2(-65 + i * 28, -125) * s, Vector2(16, 15) * s), color)
	# Door: a rectangle with a half circle on top = an arch.
	draw_rect(Rect2(Vector2(-22, -50) * s, Vector2(44, 50) * s), dark)
	draw_circle(Vector2(0, -50) * s, 22 * s, dark)
	# Windows.
	draw_rect(Rect2(Vector2(-85, -140) * s, Vector2(14, 22) * s), dark)
	draw_rect(Rect2(Vector2(71, -140) * s, Vector2(14, 22) * s), dark)
