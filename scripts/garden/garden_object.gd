## GardenObject: one restorable thing in the garden (fountain, bench, ...).
##
## Every object has two looks:
##     restored == false   the "before" state: broken, dirty, overgrown
##     restored == true    the "after" state, in the style the player chose
##
## The garden screen creates one GardenObject per entry in GardenData, places
## it, and flips `restored` when the player completes the matching task.
##
## ============================================================================
## DRAWING CONVENTIONS
## ============================================================================
## * Everything is drawn in "design units": the screen is 720 units wide.
##   The garden screen sets our `scale` so that 720 units = the real screen
##   width. Then the drawing code never has to think about screen sizes.
## * For standing objects (tree, bench, gate...) the origin (0, 0) is the
##   point where the object touches the ground, and we draw UPWARDS
##   (negative y). Objects lying flat (path, pond) are centered on the origin.
## * z_index is set from the y position by the garden screen, so objects
##   lower on the screen (closer to the viewer) are drawn in front.
class_name GardenObject
extends Node2D

## Fixed palettes for the style options, in the same order as the option
## names in garden_data.gd.
const FOUNTAIN_COLORS: Array[Color] = [Color(0.72, 0.72, 0.75), Color(0.3, 0.55, 0.85), Color(0.9, 0.75, 0.25)]
const FLOWER_COLORS: Array[Color] = [Color(0.9, 0.15, 0.2), Color(1.0, 0.85, 0.2), Color(0.65, 0.5, 0.9)]
const BENCH_COLORS: Array[Color] = [Color(0.6, 0.4, 0.2), Color(0.95, 0.95, 0.92), Color(0.8, 0.2, 0.2)]
const LANTERN_COLORS: Array[Color] = [Color(1.0, 0.8, 0.35), Color(0.5, 0.8, 1.0), Color(1.0, 0.55, 0.8)]
const LILY_COLORS: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.6, 0.75), Color(1.0, 0.9, 0.4)]
const BRIDGE_COLORS: Array[Color] = [Color(0.6, 0.42, 0.22), Color(0.8, 0.2, 0.15), Color(0.65, 0.65, 0.68)]
const GAZEBO_COLORS: Array[Color] = [Color(0.95, 0.95, 0.95), Color(0.35, 0.65, 0.4), Color(0.35, 0.5, 0.85)]

var object_id: String = ""
var kind: String = ""
var restored: bool = false:
	set(value):
		restored = value
		queue_redraw()
var option: int = 0:
	set(value):
		option = value
		queue_redraw()
## How far from the origin (in design units) a tap still counts as hitting
## this object. Used by the garden screen for tapping to change styles.
var hit_radius: float = 110.0

var _time: float = 0.0


func setup(p_id: String, p_kind: String) -> void:
	object_id = p_id
	kind = p_kind
	_time = randf() * 10.0


## Is a point (in global/screen coordinates) on this object?
func contains_point(global_point: Vector2) -> bool:
	# to_local() undoes our position AND scale, so the result is in design units.
	var local := to_local(global_point)
	# Standing objects are drawn above the origin, so test around their middle.
	return (local - Vector2(0, -hit_radius * 0.6)).length() < hit_radius


func _process(delta: float) -> void:
	_time += delta
	# Only animated things need a redraw every frame.
	if restored and kind in ["fountain", "lanterns", "pond", "reeds", "tree"]:
		queue_redraw()


func _draw() -> void:
	match kind:
		"gate": _draw_gate()
		"tree": _draw_tree()
		"path": _draw_path()
		"fountain": _draw_fountain()
		"flowerbed": _draw_flowerbed()
		"bench": _draw_bench()
		"lanterns": _draw_lanterns()
		"weeds": _draw_weeds()
		"pond": _draw_pond()
		"lilies": _draw_lilies()
		"bridge": _draw_bridge()
		"gazebo": _draw_gazebo()
		"boat": _draw_boat()
		"reeds": _draw_reeds()


# Small helpers to keep the drawing code short.
func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	draw_colored_polygon(UIStyle.ellipse_points(center, radii, 28), color)


func _pick(colors: Array[Color]) -> Color:
	return colors[clampi(option, 0, colors.size() - 1)]


# =============================================================================
# OLD COURTYARD
# =============================================================================

func _draw_gate() -> void:
	var stone := Color(0.6, 0.58, 0.55)
	# Two stone pillars.
	for side in [-1.0, 1.0]:
		var x: float = side * 90.0
		draw_rect(Rect2(x - 22, -190, 44, 190), stone)
		draw_rect(Rect2(x - 28, -205, 56, 18), stone.lightened(0.15))
	if not restored:
		# One door fell over, the other hangs crooked; no arch.
		var rotten := Color(0.4, 0.3, 0.2)
		draw_colored_polygon(PackedVector2Array([Vector2(-68, -150), Vector2(-5, -130), Vector2(-5, 0), Vector2(-68, 0)]), rotten)
		draw_colored_polygon(PackedVector2Array([Vector2(10, -10), Vector2(70, -30), Vector2(75, 0), Vector2(15, 5)]), rotten.darkened(0.2))
		return
	# Restored: an arch with an iron gate and climbing vines.
	draw_arc(Vector2(0, -190), 90.0, PI, TAU, 24, stone.lightened(0.1), 16.0, true)
	var iron := Color(0.15, 0.15, 0.18)
	for i in 7:
		var x := -66.0 + i * 22.0
		draw_line(Vector2(x, -150), Vector2(x, 0), iron, 4.0)
		draw_circle(Vector2(x, -156), 5.0, iron)
	draw_line(Vector2(-68, -110), Vector2(68, -110), iron, 5.0)
	draw_line(Vector2(-68, -30), Vector2(68, -30), iron, 5.0)
	for i in 9:
		var angle := PI + i * PI / 8.0
		draw_circle(Vector2(0, -190) + Vector2(cos(angle), sin(angle)) * 90.0, 10.0, Color(0.25, 0.6, 0.25))
		draw_circle(Vector2(0, -190) + Vector2(cos(angle), sin(angle)) * 90.0 + Vector2(4, -4), 4.0, Color(1, 0.6, 0.7))


func _draw_tree() -> void:
	var bark := Color(0.45, 0.3, 0.15)
	if not restored:
		# A sad old stump with growth rings.
		draw_rect(Rect2(-30, -40, 60, 40), bark)
		_ellipse(Vector2(0, -40), Vector2(30, 10), bark.lightened(0.3))
		draw_arc(Vector2(0, -40), 15.0, 0.0, TAU, 16, bark, 2.0)
		return
	draw_rect(Rect2(-16, -150, 32, 150), bark)
	# The canopy: overlapping circles look like a fluffy crown. The slow sway
	# uses the same trick as everywhere else: sin(time).
	var sway := sin(_time * 0.8) * 3.0
	var leaf := Color(0.25, 0.6, 0.22)
	for blob in [Vector2(0, -210), Vector2(-60, -180), Vector2(60, -180), Vector2(-35, -250), Vector2(35, -250)]:
		draw_circle(blob + Vector2(sway, 0), 62.0, leaf)
	for blob in [Vector2(-20, -230), Vector2(30, -200)]:
		draw_circle(blob + Vector2(sway, 0), 35.0, leaf.lightened(0.15))
	for apple in [Vector2(-50, -190), Vector2(20, -260), Vector2(55, -200), Vector2(-15, -170), Vector2(0, -230)]:
		draw_circle(apple + Vector2(sway, 0), 9.0, Color(0.9, 0.15, 0.15))


func _draw_path() -> void:
	# The path is centered on its origin and runs from the gate down the screen.
	if not restored:
		# Broken stones at odd angles with gaps of mud between them.
		var mud := Color(0.45, 0.35, 0.22)
		draw_rect(Rect2(-45, -380, 90, 640), mud)
		var stone := Color(0.55, 0.53, 0.5)
		for i in 9:
			var y := -360.0 + i * 70.0
			var x := -25.0 if i % 2 == 0 else 5.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, y), Vector2(x + 30, y + 6), Vector2(x + 26, y + 30), Vector2(x - 4, y + 24)]), stone)
		return
	var slab := Color(0.75, 0.72, 0.66)
	draw_rect(Rect2(-55, -380, 110, 640), slab.darkened(0.3))
	for i in 16:
		var y := -376.0 + i * 40.0
		draw_rect(Rect2(-51, y, 49, 36), slab)
		draw_rect(Rect2(2, y, 49, 36), slab.lightened(0.05))


func _draw_fountain() -> void:
	var color := _pick(FOUNTAIN_COLORS) if restored else Color(0.5, 0.48, 0.45)
	# Basin: an ellipse for the rim, a darker ellipse for the inside.
	_ellipse(Vector2(0, -30), Vector2(130, 45), color.darkened(0.25))
	draw_rect(Rect2(-130, -30, 260, 30), color.darkened(0.25))
	_ellipse(Vector2(0, 0), Vector2(130, 45), color.darkened(0.25))
	_ellipse(Vector2(0, -30), Vector2(115, 36), color)
	if not restored:
		# Dry, cracked, with a broken pillar and leaves inside.
		_ellipse(Vector2(0, -30), Vector2(100, 28), Color(0.4, 0.33, 0.22))
		draw_rect(Rect2(-14, -80, 28, 50), color)
		draw_line(Vector2(-60, -40), Vector2(-20, -20), Color(0.2, 0.2, 0.2), 2.0)
		draw_line(Vector2(40, -45), Vector2(70, -25), Color(0.2, 0.2, 0.2), 2.0)
		for leaf in [Vector2(-50, -30), Vector2(30, -25), Vector2(60, -35)]:
			_ellipse(leaf, Vector2(10, 5), Color(0.6, 0.4, 0.15))
		return
	# Water with a moving shine, a pillar, and spraying water drops.
	_ellipse(Vector2(0, -30), Vector2(100, 28), Color(0.35, 0.65, 0.95))
	_ellipse(Vector2(sin(_time) * 30.0, -32), Vector2(30, 6), Color(1, 1, 1, 0.4))
	draw_rect(Rect2(-14, -130, 28, 100), color)
	_ellipse(Vector2(0, -130), Vector2(40, 12), color.lightened(0.15))
	for i in 10:
		# Each drop follows a parabola. `fposmod` makes the phase loop 0..1.
		var phase := fposmod(_time * 0.8 + i * 0.1, 1.0)
		var dir := -1.0 if i % 2 == 0 else 1.0
		var x := dir * phase * 70.0
		var y := -140.0 - 60.0 * (1.0 - pow(phase * 2.0 - 1.0, 2.0)) + phase * 90.0
		draw_circle(Vector2(x, y), 5.0, Color(0.6, 0.85, 1.0, 0.9))


func _draw_flowerbed() -> void:
	var soil := Color(0.4, 0.27, 0.15)
	_ellipse(Vector2(0, -25), Vector2(110, 40), soil.darkened(0.2))
	_ellipse(Vector2(0, -30), Vector2(100, 34), soil)
	if not restored:
		# Dry sticks.
		for x in [-50.0, -10.0, 35.0, 60.0]:
			draw_line(Vector2(x, -30), Vector2(x + 8, -55), Color(0.5, 0.4, 0.25), 3.0)
		return
	var petal := _pick(FLOWER_COLORS)
	var spots := [Vector2(-70, -35), Vector2(-40, -50), Vector2(-10, -30), Vector2(20, -52),
			Vector2(50, -32), Vector2(75, -45), Vector2(-55, -15), Vector2(0, -12), Vector2(45, -15)]
	for spot in spots:
		var s: Vector2 = spot
		draw_line(s, s + Vector2(0, -28), Color(0.2, 0.55, 0.2), 3.0)
		var head := s + Vector2(0, -32)
		if option == 2:
			# Lavender: a column of small dots instead of a round flower.
			for k in 4:
				draw_circle(head + Vector2(0, -k * 6.0), 5.0, petal)
		else:
			for k in 5:
				var angle := k * TAU / 5.0
				draw_circle(head + Vector2(cos(angle), sin(angle)) * 7.0, 6.0, petal)
			draw_circle(head, 4.0, Color(1, 0.9, 0.4) if option == 0 else Color(0.9, 0.5, 0.1))


func _draw_bench() -> void:
	if not restored:
		# Broken planks lying in the grass.
		var rotten := Color(0.42, 0.32, 0.22)
		draw_colored_polygon(PackedVector2Array([Vector2(-80, -10), Vector2(30, -25), Vector2(32, -12), Vector2(-78, 3)]), rotten)
		draw_colored_polygon(PackedVector2Array([Vector2(-20, -5), Vector2(75, 5), Vector2(73, 18), Vector2(-22, 8)]), rotten.darkened(0.15))
		return
	var wood := _pick(BENCH_COLORS)
	var iron := Color(0.2, 0.2, 0.22)
	# Legs, seat, backrest slats.
	for x in [-70.0, 60.0]:
		draw_rect(Rect2(x, -45, 10, 45), iron)
	draw_rect(Rect2(-85, -55, 170, 16), wood)
	for i in 3:
		draw_rect(Rect2(-85, -120 + i * 20, 170, 13), wood.darkened(0.08 * i))
	draw_rect(Rect2(-80, -125, 8, 75), iron)
	draw_rect(Rect2(72, -125, 8, 75), iron)


func _draw_lanterns() -> void:
	# Four posts along the path (the origin is the path's center).
	var posts := [Vector2(-90, -250), Vector2(90, -250), Vector2(-90, 50), Vector2(90, 50)]
	for post in posts:
		var p: Vector2 = post
		draw_rect(Rect2(p.x - 4, p.y - 110, 8, 110), Color(0.2, 0.2, 0.22))
		if restored:
			var light := _pick(LANTERN_COLORS)
			# A soft glow that "breathes": a big transparent circle whose alpha
			# follows a sine wave.
			var glow := 0.25 + 0.1 * sin(_time * 2.0 + p.x)
			draw_circle(p + Vector2(0, -120), 40.0, Color(light, glow))
			draw_rect(Rect2(p.x - 12, p.y - 135, 24, 28), light)
			draw_rect(Rect2(p.x - 14, p.y - 140, 28, 6), Color(0.2, 0.2, 0.22))


## Weeds are the only object that DISAPPEARS when restored.
func _draw_weeds() -> void:
	if restored:
		return
	var clumps := [Vector2(-250, -200), Vector2(220, -220), Vector2(-180, 40), Vector2(240, 120),
			Vector2(-60, 220), Vector2(120, -60), Vector2(-280, 230), Vector2(60, 180), Vector2(-120, -120)]
	for clump in clumps:
		var c: Vector2 = clump
		for k in 7:
			var angle := -PI / 2.0 + (k - 3) * 0.3
			var length := 35.0 + (k % 3) * 12.0
			draw_line(c, c + Vector2(cos(angle), sin(angle)) * length, Color(0.35, 0.45, 0.12), 5.0, true)


# =============================================================================
# LAKESIDE
# =============================================================================

func _draw_pond() -> void:
	_ellipse(Vector2.ZERO, Vector2(310, 175), Color(0.45, 0.4, 0.3))   # muddy shore
	if not restored:
		_ellipse(Vector2.ZERO, Vector2(290, 158), Color(0.32, 0.38, 0.2))  # murky water
		# Junk floating around.
		draw_circle(Vector2(-120, -40), 22.0, Color(0.15, 0.15, 0.15))
		draw_circle(Vector2(-120, -40), 11.0, Color(0.32, 0.38, 0.2))
		draw_line(Vector2(60, 50), Vector2(150, 20), Color(0.35, 0.25, 0.15), 8.0)
		_ellipse(Vector2(130, -70), Vector2(30, 12), Color(0.25, 0.3, 0.15))
		return
	_ellipse(Vector2.ZERO, Vector2(290, 158), Color(0.25, 0.55, 0.85))
	_ellipse(Vector2(0, -20), Vector2(230, 110), Color(0.35, 0.65, 0.92))
	# Moving ripples and a couple of fish shadows.
	for i in 3:
		var phase := fposmod(_time * 0.3 + i / 3.0, 1.0)
		draw_arc(Vector2(-60 + i * 80, 30 - i * 30), 20.0 + phase * 40.0, 0.0, TAU, 24,
				Color(1, 1, 1, 0.4 * (1.0 - phase)), 2.0, true)
	for i in 2:
		var x := sin(_time * 0.5 + i * 3.0) * 150.0
		_ellipse(Vector2(x, 60 - i * 90), Vector2(22, 8), Color(0.1, 0.25, 0.4, 0.5))


func _draw_lilies() -> void:
	if not restored:
		return
	var flower := _pick(LILY_COLORS)
	for pad in [Vector2(-180, -60), Vector2(-120, 70), Vector2(160, -40), Vector2(200, 60), Vector2(-40, -110)]:
		var p: Vector2 = pad
		# A lily pad: a circle with a slice cut out (draw_circle + a triangle in
		# water color would also work; here we build the pad as a polygon).
		var points := PackedVector2Array([p])
		for k in 21:
			var angle := 0.4 + k * (TAU - 0.8) / 20.0
			points.append(p + Vector2(cos(angle) * 30.0, sin(angle) * 18.0))
		draw_colored_polygon(points, Color(0.25, 0.6, 0.25))
		for k in 6:
			var angle := k * TAU / 6.0
			draw_circle(p + Vector2(cos(angle) * 8.0, sin(angle) * 5.0 - 6.0), 6.0, flower)
		draw_circle(p + Vector2(0, -6), 4.0, Color(1, 0.85, 0.3))


func _draw_bridge() -> void:
	if not restored:
		# Just a few planks floating in the water.
		var plank := Color(0.42, 0.32, 0.22)
		for i in 3:
			draw_rect(Rect2(-90 + i * 70, 20 + (i % 2) * 15, 40, 12), plank)
		return
	var color := _pick(BRIDGE_COLORS)
	# An arch: the deck follows a sine curve from one bank to the other.
	var deck_top := PackedVector2Array()
	var deck_bottom := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		var x := lerpf(-260.0, 260.0, t)
		var y := 40.0 - sin(t * PI) * 70.0
		deck_top.append(Vector2(x, y - 22))
		deck_bottom.append(Vector2(x, y))
	var deck := deck_top.duplicate()
	for i in range(deck_bottom.size() - 1, -1, -1):
		deck.append(deck_bottom[i])
	draw_colored_polygon(deck, color)
	# Railing posts and rail.
	var rail := PackedVector2Array()
	for i in range(0, 21, 2):
		var top: Vector2 = deck_top[i]
		draw_line(top, top + Vector2(0, -35), color.darkened(0.3), 5.0)
		rail.append(top + Vector2(0, -35))
	draw_polyline(rail, color.darkened(0.3), 6.0, true)


func _draw_gazebo() -> void:
	var stone := Color(0.7, 0.68, 0.64)
	_ellipse(Vector2(0, 0), Vector2(110, 30), stone.darkened(0.2))
	_ellipse(Vector2(0, -8), Vector2(105, 26), stone)
	if not restored:
		# Two broken pillars.
		draw_rect(Rect2(-80, -70, 18, 62), stone.darkened(0.1))
		draw_rect(Rect2(55, -40, 18, 32), stone.darkened(0.1))
		return
	var color := _pick(GAZEBO_COLORS)
	for x in [-85.0, -30.0, 25.0, 75.0]:
		draw_rect(Rect2(x, -170, 12, 162), Color(0.95, 0.95, 0.92))
	# Roof: a wide triangle plus a little top ball.
	draw_colored_polygon(PackedVector2Array([Vector2(-125, -165), Vector2(125, -165), Vector2(0, -260)]), color)
	draw_rect(Rect2(-125, -175, 250, 14), color.darkened(0.2))
	draw_circle(Vector2(0, -262), 9.0, Color(0.9, 0.75, 0.25))


func _draw_boat() -> void:
	if not restored:
		# An upside-down wreck with a hole.
		var hull := Color(0.4, 0.38, 0.35)
		draw_colored_polygon(PackedVector2Array([Vector2(-80, 0), Vector2(80, 0), Vector2(60, -40), Vector2(-60, -40)]), hull)
		_ellipse(Vector2(10, -20), Vector2(14, 9), Color(0.15, 0.12, 0.1))
		return
	var paint := Color(0.85, 0.35, 0.2)
	# Gentle bobbing on the water.
	var bob := sin(_time * 1.5) * 3.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(-90, -40 + bob), Vector2(90, -40 + bob), Vector2(65, 0 + bob), Vector2(-65, 0 + bob)]), paint)
	draw_rect(Rect2(-90, -46 + bob, 180, 8), Color(0.95, 0.95, 0.9))
	draw_line(Vector2(-40, -45 + bob), Vector2(-110, -5 + bob), Color(0.55, 0.4, 0.2), 5.0)
	draw_line(Vector2(40, -45 + bob), Vector2(110, -5 + bob), Color(0.55, 0.4, 0.2), 5.0)


func _draw_reeds() -> void:
	if not restored:
		for i in 6:
			var x := -60.0 + i * 24.0
			draw_line(Vector2(x, 0), Vector2(x + 4, -18), Color(0.55, 0.45, 0.25), 4.0)
		return
	for i in 9:
		var x := -80.0 + i * 20.0
		var height := 110.0 + (i % 3) * 25.0
		var sway := sin(_time * 1.2 + i) * 6.0
		var top := Vector2(x + sway, -height)
		draw_line(Vector2(x, 0), top, Color(0.3, 0.6, 0.2), 4.0, true)
		if i % 2 == 0:
			# Cattail heads.
			draw_line(top + Vector2(0, 10), top + Vector2(0, 32), Color(0.45, 0.28, 0.12), 9.0, true)
