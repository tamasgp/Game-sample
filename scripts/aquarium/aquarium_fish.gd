## AquariumFish: one fish that swims around the tank and chases food.
##
## STEERING BEHAVIOUR
## ------------------
## Instead of teleporting or moving in straight lines, the fish has a velocity
## and gently turns it toward where it WANTS to go (its "desired velocity").
## This simple trick, from Craig Reynolds' "steering behaviors", makes movement
## look smooth and alive:
##
##     desired  = direction_to_target * max_speed
##     velocity = velocity.lerp(desired, turn_rate * delta)
##     position += velocity * delta
##
## The fish has two moods:
##   * WANDER: pick a random point in the tank, swim to it, pick another.
##   * FOOD:   the aquarium tells us where the nearest food pellet is; swim
##             there faster.
class_name AquariumFish
extends Node2D

var item_id: String = ""
var body_color: Color = Color.ORANGE
var fin_color: Color = Color.ORANGE_RED
var length: float = 50.0
var speed: float = 70.0
var stripes: int = 0

## The rectangle the fish is allowed to swim in (set by the aquarium).
var swim_bounds: Rect2 = Rect2(0, 0, 720, 900)
var velocity: Vector2 = Vector2.ZERO

var has_food_target: bool = false
var food_target: Vector2 = Vector2.ZERO

var _wander_target: Vector2 = Vector2.ZERO
## +1 = facing right, -1 = facing left. We mirror the drawing instead of the node.
var _facing: float = 1.0
var _time: float = 0.0


## Reads the look and speed of the fish from its catalog entry.
func setup(item: Dictionary, bounds: Rect2) -> void:
	item_id = item["id"]
	body_color = item["body"]
	fin_color = item["fin"]
	length = item["size"]
	speed = item["speed"]
	stripes = item["stripes"]
	swim_bounds = bounds
	# Start each fish at a different moment of its animations, so they don't
	# all wiggle in sync (that would look robotic).
	_time = randf() * 10.0
	_pick_wander_target()


func set_bounds(bounds: Rect2) -> void:
	swim_bounds = bounds
	position = position.clamp(bounds.position, bounds.end)
	_pick_wander_target()


func _pick_wander_target() -> void:
	_wander_target = Vector2(
		randf_range(swim_bounds.position.x, swim_bounds.end.x),
		randf_range(swim_bounds.position.y, swim_bounds.end.y))


## The aquarium calls this when the fish eats a pellet: a happy little "gulp".
func on_ate() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.1)
	tween.tween_property(self, "scale", Vector2.ONE, 0.2)


func _process(delta: float) -> void:
	_time += delta

	var target := _wander_target
	var max_speed := speed
	if has_food_target:
		target = food_target
		max_speed = speed * 1.8  # hungry fish swim faster!

	var to_target := target - position
	if not has_food_target and to_target.length() < 20.0:
		_pick_wander_target()

	# Steering (see the comment at the top of the file).
	var desired := to_target.normalized() * max_speed
	var turn_rate := 3.0 if has_food_target else 1.2
	velocity = velocity.lerp(desired, clampf(turn_rate * delta, 0.0, 1.0))
	position += velocity * delta
	position = position.clamp(swim_bounds.position, swim_bounds.end)

	# Only flip when clearly moving sideways. Without this "dead zone" the fish
	# would flicker left/right when swimming straight up or down.
	if velocity.x > 8.0:
		_facing = 1.0
	elif velocity.x < -8.0:
		_facing = -1.0

	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing. The fish is drawn facing RIGHT around (0, 0); _p() mirrors it when
# facing left and adds a gentle up/down bob.
# ---------------------------------------------------------------------------

func _p(v: Vector2) -> Vector2:
	var bob := sin(_time * 2.0) * 3.0
	return Vector2(v.x * _facing, v.y + bob)


func _pts(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for v in points:
		result.append(_p(v))
	return result


func _draw() -> void:
	var half := length / 2.0
	# Pufferfish are round, angelfish are tall, others are long and slim.
	var body_height := length * 0.3
	if item_id == "pufferfish":
		body_height = length * 0.45
	elif item_id == "angelfish":
		body_height = length * 0.42

	# --- Tail: a triangle that swings with a sine wave ---
	var swing := sin(_time * 10.0) * 0.35
	var tail_base := Vector2(-half * 0.85, 0)
	var tail_top := tail_base + Vector2(-length * 0.35, -length * 0.25).rotated(swing)
	var tail_bottom := tail_base + Vector2(-length * 0.35, length * 0.25).rotated(swing)
	draw_colored_polygon(_pts([tail_base, tail_top, tail_bottom]), fin_color)

	# --- Top fin ---
	draw_colored_polygon(_pts([
		Vector2(-half * 0.3, -body_height * 0.8),
		Vector2(half * 0.1, -body_height * 1.45),
		Vector2(half * 0.35, -body_height * 0.75),
	]), fin_color)

	# --- Body: an ellipse ---
	var body := PackedVector2Array()
	for i in 24:
		var angle := i * TAU / 24.0
		body.append(_p(Vector2(cos(angle) * half, sin(angle) * body_height)))
	draw_colored_polygon(body, body_color)

	# --- Stripes: vertical white bands, as tall as the body at that x ---
	for s in stripes:
		var x := lerpf(half * 0.35, -half * 0.45, float(s) / maxf(1.0, stripes - 1.0))
		# Height of an ellipse at x:  h = b * sqrt(1 - (x/a)^2)
		var h := body_height * sqrt(maxf(0.0, 1.0 - pow(x / half, 2.0)))
		draw_line(_p(Vector2(x, -h)), _p(Vector2(x, h)), Color(1, 1, 1, 0.95), length * 0.09)

	# --- Side fin, slowly flapping ---
	var flap := sin(_time * 6.0) * 0.4
	draw_colored_polygon(_pts([
		Vector2(half * 0.05, body_height * 0.1),
		Vector2(-half * 0.3, body_height * 0.1) + Vector2(0, body_height * 0.5).rotated(flap),
		Vector2(-half * 0.25, body_height * 0.05),
	]), fin_color.darkened(0.15))

	# --- Eye ---
	var eye := Vector2(half * 0.55, -body_height * 0.2)
	draw_circle(_p(eye), length * 0.09, Color(1, 1, 1))
	draw_circle(_p(eye + Vector2(length * 0.02, 0)), length * 0.045, Color(0, 0, 0))
