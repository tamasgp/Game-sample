## TileView: the picture of ONE piece on the board.
##
## Every Piece in the BoardModel gets one TileView node. BoardView moves these
## nodes around with tweens. A TileView only knows how to DRAW itself (color,
## shape, special overlay) and play small idle effects (selected highlight,
## hint pulse, sparkling specials).
##
## WHY SHAPES DRAWN IN CODE?
## A released game would use sprite images made by an artist. Drawing with
## code means this sample needs no image files, and you can see how the
## drawing API works. To switch to images, replace _draw() with a Sprite2D
## child whose texture is picked by color. Nothing else in the game changes.
##
## ACCESSIBILITY: every color also has a different SHAPE, so colorblind
## players can still tell the pieces apart.
class_name TileView
extends Node2D

## Color of each piece type (the index is Piece.color).
const COLORS: Array[Color] = [
	Color(0.92, 0.22, 0.25),   # 0 red apple      (circle)
	Color(1.0, 0.55, 0.12),    # 1 orange flower  (diamond)
	Color(1.0, 0.86, 0.18),    # 2 yellow star    (5-point star)
	Color(0.35, 0.8, 0.3),     # 3 green leaf     (hexagon)
	Color(0.25, 0.6, 1.0),     # 4 blue drop      (rounded square)
	Color(0.68, 0.32, 0.9),    # 5 purple berry   (triangle)
]

var color_index: int = 0
var special: int = BoardModel.Special.NONE
## Size of one board cell in pixels. The piece is drawn a bit smaller.
var tile_size: float = 80.0

## The `set(value):` blocks below are PROPERTY SETTERS: assigning
## `tile.selected = true` runs that code, which redraws the tile.
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

## When true, the piece pulses to show the player a possible move.
var hinting: bool = false:
	set(value):
		hinting = value
		if not hinting:
			scale = Vector2.ONE

var _time: float = 0.0


## Copies the look of a model piece.
func setup(piece: BoardModel.Piece, p_tile_size: float) -> void:
	tile_size = p_tile_size
	refresh(piece)


## Call again whenever the piece changes (e.g. it became a special).
func refresh(piece: BoardModel.Piece) -> void:
	color_index = piece.color
	special = piece.special
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if hinting:
		# sin() is a smooth wave between -1 and 1, perfect for pulsing.
		var pulse := 1.0 + 0.1 * sin(_time * 8.0)
		scale = Vector2(pulse, pulse)
	# Specials are animated (spinning, flapping), so redraw them every frame.
	if special != BoardModel.Special.NONE:
		queue_redraw()


# =============================================================================
# DRAWING
# =============================================================================
# In _draw(), (0, 0) is the node's own position, so we draw the piece centered
# on the origin. Moving the node moves the drawing with it.

func _draw() -> void:
	var r := tile_size * 0.38   # radius of the piece

	if selected:
		draw_circle(Vector2.ZERO, tile_size * 0.48, Color(1, 1, 1, 0.35))

	match special:
		BoardModel.Special.RAINBOW:
			_draw_rainbow(r)
			return
		BoardModel.Special.BUTTERFLY:
			_draw_butterfly(r)
			return

	var base: Color = COLORS[posmod(color_index, COLORS.size())]
	_draw_shape(color_index, r, base)

	match special:
		BoardModel.Special.ROCKET_H:
			_draw_rocket_marks(r, true)
		BoardModel.Special.ROCKET_V:
			_draw_rocket_marks(r, false)
		BoardModel.Special.BOMB:
			_draw_bomb_ring(r)


## The basic shape of a color, with an outline and a shine spot.
func _draw_shape(index: int, r: float, base: Color) -> void:
	var points: PackedVector2Array
	match posmod(index, 6):
		0:
			points = UIStyle.ellipse_points(Vector2.ZERO, Vector2(r, r), 28)
		1:
			points = UIStyle.polygon_points(Vector2.ZERO, r * 1.1, 4, -PI / 2.0)
		2:
			points = UIStyle.star_points(Vector2.ZERO, r * 1.15, r * 0.55)
		3:
			points = UIStyle.polygon_points(Vector2.ZERO, r, 6, PI / 6.0)
		4:
			points = UIStyle.rounded_square_points(r * 0.88, r * 0.3)
		_:
			points = UIStyle.polygon_points(Vector2(0, r * 0.12), r * 1.12, 3, -PI / 2.0)

	draw_colored_polygon(points, base)
	UIStyle.draw_outline(self, points, base.darkened(0.45), 3.0)
	# A small white "shine" makes a flat shape look round and glossy.
	draw_circle(Vector2(-r * 0.3, -r * 0.35), r * 0.2, Color(1, 1, 1, 0.55))
	# Little details per type make the pieces more recognizable.
	if posmod(index, 6) == 0:
		# apple stem and leaf
		draw_line(Vector2(0, -r), Vector2(r * 0.1, -r * 1.25), Color(0.4, 0.25, 0.1), 3.0)
		draw_colored_polygon(UIStyle.ellipse_points(Vector2(r * 0.3, -r * 1.1), Vector2(r * 0.22, r * 0.1), 10),
				Color(0.3, 0.7, 0.25))


## Rockets: white stripes and arrow tips pointing where they will fire.
func _draw_rocket_marks(r: float, horizontal: bool) -> void:
	var stripe := Color(1, 1, 1, 0.9)
	for offset in [-0.35, 0.0, 0.35]:
		var o: float = offset * r
		if horizontal:
			draw_line(Vector2(-r * 0.9, o), Vector2(r * 0.9, o), stripe, 4.0)
		else:
			draw_line(Vector2(o, -r * 0.9), Vector2(o, r * 0.9), stripe, 4.0)
	var tip := r * 1.05
	var white := Color(1, 1, 1)
	if horizontal:
		draw_colored_polygon(PackedVector2Array([Vector2(tip, 0), Vector2(tip - 10, -8), Vector2(tip - 10, 8)]), white)
		draw_colored_polygon(PackedVector2Array([Vector2(-tip, 0), Vector2(-tip + 10, -8), Vector2(-tip + 10, 8)]), white)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(0, tip), Vector2(-8, tip - 10), Vector2(8, tip - 10)]), white)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -tip), Vector2(-8, -tip + 10), Vector2(8, -tip + 10)]), white)


## Bomb: a dark core with sparks circling around it.
func _draw_bomb_ring(r: float) -> void:
	draw_circle(Vector2.ZERO, r * 0.45, Color(0.1, 0.1, 0.15))
	for i in 6:
		var angle := _time * 3.0 + i * TAU / 6.0
		draw_circle(Vector2(cos(angle), sin(angle)) * r * 0.75, 4.0, Color(1, 1, 0.6))


## Rainbow: a slowly rotating ring of every color.
func _draw_rainbow(r: float) -> void:
	var segments := COLORS.size()
	for i in segments:
		var a0 := _time * 1.5 + i * TAU / segments
		draw_arc(Vector2.ZERO, r * 0.8, a0, a0 + TAU / segments, 8, COLORS[i], r * 0.45, true)
	draw_circle(Vector2.ZERO, r * 0.38, Color(1, 1, 1))
	draw_circle(Vector2(-r * 0.12, -r * 0.12), r * 0.12, Color(1, 1, 1, 0.9))


## Butterfly: four wings that flap (their width follows a sine wave).
func _draw_butterfly(r: float) -> void:
	var flap := 0.55 + 0.45 * absf(sin(_time * 6.0))   # 0.1 .. 1.0
	var wing := Color(1.0, 0.45, 0.75)
	var wing_low := Color(0.55, 0.35, 1.0)
	for side in [-1.0, 1.0]:
		var s: float = side * flap
		draw_colored_polygon(UIStyle.ellipse_points(Vector2(s * r * 0.5, -r * 0.3), Vector2(r * 0.5 * flap, r * 0.45), 14), wing)
		draw_colored_polygon(UIStyle.ellipse_points(Vector2(s * r * 0.4, r * 0.35), Vector2(r * 0.38 * flap, r * 0.32), 12), wing_low)
		draw_circle(Vector2(s * r * 0.55, -r * 0.35), r * 0.12, Color(1, 1, 1, 0.8))
	# Body and antennae.
	draw_line(Vector2(0, -r * 0.55), Vector2(0, r * 0.6), Color(0.2, 0.12, 0.1), 6.0, true)
	draw_line(Vector2(0, -r * 0.55), Vector2(-r * 0.25, -r * 0.9), Color(0.2, 0.12, 0.1), 2.0, true)
	draw_line(Vector2(0, -r * 0.55), Vector2(r * 0.25, -r * 0.9), Color(0.2, 0.12, 0.1), 2.0, true)
