## UIStyle: shared colors and small helper functions for building UI in code.
##
## BUILDING UI IN CODE vs. IN THE EDITOR
## ------------------------------------
## Most Godot projects build menus visually in the editor (drag nodes into a
## scene, set properties in the Inspector) and save them as .tscn files.
## This sample builds its UI in code instead, for two reasons:
##   1. Everything is in plain text you can read top to bottom with comments.
##   2. You can see exactly which properties matter.
## Once you're comfortable, try rebuilding the HUD in the editor. It's a
## good exercise (see docs/LEARNING_GUIDE.md).
##
## All functions are `static`, so you call them on the class itself:
##   var title := UIStyle.label("Hello", 48)
class_name UIStyle
extends RefCounted

# A small palette keeps the game looking consistent. Garden theme: fresh
# greens for backgrounds, warm wood/cream for panels.
const BG_TOP := Color(0.45, 0.75, 0.35)
const BG_BOTTOM := Color(0.15, 0.4, 0.15)
const PANEL := Color(0.25, 0.16, 0.08, 0.93)
const PANEL_BORDER := Color(1.0, 0.85, 0.55)
const ACCENT := Color(1.0, 0.78, 0.2)
const BUTTON := Color(0.15, 0.6, 0.35)
const BUTTON_HOVER := Color(0.2, 0.72, 0.42)
const BUTTON_PRESSED := Color(0.1, 0.45, 0.25)
const BUTTON_DISABLED := Color(0.3, 0.35, 0.4)
const TEXT := Color(1, 1, 1)
const TEXT_DIM := Color(0.95, 0.88, 0.72)
const COIN := Color(1.0, 0.82, 0.2)
const HEART := Color(0.95, 0.25, 0.35)
const ORANGE := Color(0.9, 0.5, 0.1)
const BLUE := Color(0.2, 0.45, 0.8)


## Creates a Label with a given font size and color.
static func label(text: String, font_size: int = 28, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# "Theme overrides" change one style property on one node only.
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	# A dark outline keeps text readable on top of the bright water.
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
	l.add_theme_constant_override("outline_size", maxi(2, int(font_size / 8.0)))
	return l


## Creates a rounded, colored Button.
static func button(text: String, font_size: int = 30, min_size: Vector2 = Vector2(0, 80),
		color: Color = BUTTON) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_disabled_color", Color(0.7, 0.7, 0.7))
	# A Button draws a different StyleBox for each state.
	b.add_theme_stylebox_override("normal", box(color, 18))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.15), 18))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.2), 18))
	b.add_theme_stylebox_override("disabled", box(BUTTON_DISABLED, 18))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## A rounded rectangle style, used for buttons and panels.
static func box(color: Color, radius: int = 16, border: Color = Color(0, 0, 0, 0),
		border_width: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	if border_width > 0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	return sb


## A translucent panel with a light border.
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL, 24, PANEL_BORDER, 3))
	return p


## Draws a vertical color gradient into `rect`. Call from inside a _draw().
## A polygon with a different color at each corner is blended by the GPU,
## which is the cheapest gradient there is.
static func draw_vertical_gradient(canvas: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	var points := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	canvas.draw_polygon(points, PackedColorArray([top, top, bottom, bottom]))


## Points of a star shape, alternating outer and inner radius.
static func star_points(center: Vector2, outer: float, inner: float, tips: int = 5) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in tips * 2:
		var radius := outer if i % 2 == 0 else inner
		# Start pointing straight up (-PI/2) and go around the circle.
		var angle := -PI / 2.0 + i * PI / tips
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Points of a regular polygon (triangle, square, hexagon, ...).
static func polygon_points(center: Vector2, radius: float, sides: int, rotation: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		var angle := rotation + i * TAU / sides
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Points of an ellipse, for shapes Godot has no built-in draw call for.
static func ellipse_points(center: Vector2, radii: Vector2, segments: int = 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := i * TAU / segments
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


## Draws `points` as a closed outline.
static func draw_outline(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	canvas.draw_polyline(closed, color, width, true)


## Points of a square with rounded corners, centered on (0, 0).
## Four quarter circles (one per corner) joined into one outline.
static func rounded_square_points(half: float, corner: float) -> PackedVector2Array:
	var points := PackedVector2Array()
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


## A small Control showing a board piece (normal or special). Used for goal
## icons and booster buttons. It reuses the real TileView drawing code.
static func piece_icon(color: int, special: int, icon_size: float = 56.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(icon_size, icon_size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tile := TileView.new()
	tile.setup(BoardModel.Piece.new(0, color, special), 80.0)
	tile.position = Vector2(icon_size, icon_size) / 2.0
	tile.scale = Vector2.ONE * (icon_size / 80.0) * 1.1
	holder.add_child(tile)
	return holder


## An HBox with an icon and a label, e.g. [heart] 5. Returns the box; the
## label is its second child, reachable with get_child(1).
static func icon_counter(kind: String, text: String, font_size: int = 28) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(IconView.new(kind, 40.0))
	var l := label(text, font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(l)
	return row
