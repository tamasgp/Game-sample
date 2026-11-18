## TileView: the picture of ONE piece on the board.
##
## Each Piece in the BoardModel gets one TileView node. The BoardView moves
## these nodes around with tweens. The TileView only knows how to DRAW itself
## (color, shape, special overlay) and play small idle effects (selection
## highlight, hint pulse).
##
## WHY DRAW SHAPES IN CODE?
## A real game would use sprite images (PNG files) made by an artist. Drawing
## with code means this sample needs no image files at all, and you can see how
## the drawing API works. To switch to sprites later, replace _draw() with a
## Sprite2D child and pick its texture by color. Nothing else has to change.
##
## ACCESSIBILITY TIP: every color also has a different SHAPE, so colorblind
## players can still tell the pieces apart.
class_name TileView
extends Node2D

## Color per piece color index. Must have at least 6 entries.
const COLORS: Array[Color] = [
	Color(0.95, 0.25, 0.3),   # 0 red shell     (circle)
	Color(1.0, 0.55, 0.15),   # 1 orange star   (diamond)
	Color(1.0, 0.88, 0.2),    # 2 yellow star   (5-point star)
	Color(0.3, 0.85, 0.35),   # 3 green leaf    (hexagon)
	Color(0.25, 0.6, 1.0),    # 4 blue pearl    (rounded square)
	Color(0.7, 0.35, 0.95),   # 5 purple urchin (triangle)
]

var color_index: int = 0
var special: int = BoardModel.Special.NONE
## Size of one board cell in pixels (the piece is drawn a bit smaller).
var tile_size: float = 80.0

var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

## When true, the piece gently pulses to show the player a possible move.
var hinting: bool = false:
	set(value):
		hinting = value
		if not hinting:
			scale = Vector2.ONE

var _time: float = 0.0


## Copies the look of a model piece. Call again if the piece changes
## (for example after a shuffle recolors it).
func setup(piece: BoardModel.Piece, p_tile_size: float) -> void:
	tile_size = p_tile_size
	refresh(piece)


func refresh(piece: BoardModel.Piece) -> void:
	color_index = piece.color
	special = piece.special
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if hinting:
		# sin() gives a smooth wave between -1 and 1: perfect for pulsing.
		var pulse := 1.0 + 0.1 * sin(_time * 8.0)
		scale = Vector2(pulse, pulse)
	# Specials sparkle a bit, so we redraw them every frame.
	if special != BoardModel.Special.NONE:
		queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
# Godot calls _draw() with the node's own position as (0, 0), so we draw the
# piece centered on the origin. Moving the node moves the drawing.

func _draw() -> void:
	var r := tile_size * 0.38  # radius of the piece

	if selected:
		draw_circle(Vector2.ZERO, tile_size * 0.48, Color(1, 1, 1, 0.35))

	if special == BoardModel.Special.RAINBOW:
		_draw_rainbow(r)
		return

	var base: Color = COLORS[color_index % COLORS.size()]
	_draw_shape(color_index, r, base)

	match special:
		BoardModel.Special.ROCKET_H:
			_draw_stripes(r, true)
		BoardModel.Special.ROCKET_V:
			_draw_stripes(r, false)
		BoardModel.Special.BOMB:
			_draw_bomb_ring(r)


## Draws the basic shape for a color, with an outline and a shine spot.
func _draw_shape(index: int, r: float, base: Color) -> void:
	var outline := base.darkened(0.45)
	var points: PackedVector2Array
	match index % 6:
		0:
			points = UIStyle.ellipse_points(Vector2.ZERO, Vector2(r, r), 28)
		1:
			points = UIStyle.polygon_points(Vector2.ZERO, r * 1.1, 4, -PI / 2.0)
		2:
			points = UIStyle.star_points(Vector2.ZERO, r * 1.15, r * 0.55)
		3:
			points = UIStyle.polygon_points(Vector2.ZERO, r, 6, PI / 6.0)
		4:
			points = _rounded_square(r * 0.88, r * 0.3)
		_:
			points = UIStyle.polygon_points(Vector2(0, r * 0.12), r * 1.12, 3, -PI / 2.0)

	draw_colored_polygon(points, base)
	UIStyle.draw_outline(self, points, outline, 3.0)
	# A small white "shine" makes flat shapes look round and glossy.
	draw_circle(Vector2(-r * 0.3, -r * 0.35), r * 0.2, Color(1, 1, 1, 0.55))


func _rounded_square(half: float, corner: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	# Four quarter circles, one per corner, connected into one outline.
	var corners := [
		Vector2(half - corner, -half + corner),
		Vector2(half - corner, half - corner),
		Vector2(-half + corner, half - corner),
		Vector2(-half + corner, -half + corner),
	]
	for i in 4:
		var start_angle := -PI / 2.0 + i * PI / 2.0
		for step in 5:
			var angle := start_angle + step * (PI / 2.0) / 4.0
			points.append(corners[i] + Vector2(cos(angle), sin(angle)) * corner)
	return points


## Rockets: white stripes across the piece, in the direction they will fire.
func _draw_stripes(r: float, horizontal: bool) -> void:
	var stripe_color := Color(1, 1, 1, 0.9)
	for offset in [-0.35, 0.0, 0.35]:
		var o: float = offset * r
		if horizontal:
			draw_line(Vector2(-r * 0.9, o), Vector2(r * 0.9, o), stripe_color, 4.0)
		else:
			draw_line(Vector2(o, -r * 0.9), Vector2(o, r * 0.9), stripe_color, 4.0)
	# Little arrow heads show the firing direction.
	var tip := r * 1.05
	var arrow_color := Color(1, 1, 1)
	if horizontal:
		draw_colored_polygon(PackedVector2Array([Vector2(tip, 0), Vector2(tip - 10, -8), Vector2(tip - 10, 8)]), arrow_color)
		draw_colored_polygon(PackedVector2Array([Vector2(-tip, 0), Vector2(-tip + 10, -8), Vector2(-tip + 10, 8)]), arrow_color)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(0, tip), Vector2(-8, tip - 10), Vector2(8, tip - 10)]), arrow_color)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -tip), Vector2(-8, -tip + 10), Vector2(8, -tip + 10)]), arrow_color)


## Bombs: a dark core with a spinning sparkle ring.
func _draw_bomb_ring(r: float) -> void:
	draw_circle(Vector2.ZERO, r * 0.45, Color(0.1, 0.1, 0.15))
	var spin := _time * 3.0
	for i in 6:
		var angle := spin + i * TAU / 6.0
		var p := Vector2(cos(angle), sin(angle)) * r * 0.75
		draw_circle(p, 4.0, Color(1, 1, 0.6))


## Rainbow: a ring of every color, slowly rotating.
func _draw_rainbow(r: float) -> void:
	var segments := COLORS.size()
	var spin := _time * 1.5
	for i in segments:
		var a0 := spin + i * TAU / segments
		var a1 := a0 + TAU / segments
		draw_arc(Vector2.ZERO, r * 0.8, a0, a1, 8, COLORS[i], r * 0.45, true)
	draw_circle(Vector2.ZERO, r * 0.38, Color(1, 1, 1))
	draw_circle(Vector2(-r * 0.12, -r * 0.12), r * 0.12, Color(1, 1, 1, 0.9))
