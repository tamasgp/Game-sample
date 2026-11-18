## BoardEffect: a short-lived visual effect (rocket beam, bomb blast, sparkle).
##
## "FIRE AND FORGET" NODES
## -----------------------
## Effects are created, animate themselves with a Tween, and then delete
## themselves with queue_free(). Nobody needs to keep track of them.
## This is a very common pattern for particles, popups and floating text.
class_name BoardEffect
extends Node2D

enum Kind { ROW_BEAM, COLUMN_BEAM, BLAST, SPARKLE }

var kind: int = Kind.SPARKLE
## For beams: how long the beam is. For blasts: the radius.
var extent: float = 100.0
var thickness: float = 40.0
var color: Color = Color(1, 1, 0.8)


## Creates the effect, adds it to `parent` at `pos`, and starts it.
static func spawn(parent: Node, p_kind: int, pos: Vector2, p_extent: float, p_thickness: float,
		p_color: Color = Color(1, 1, 0.8)) -> BoardEffect:
	var effect := BoardEffect.new()
	effect.kind = p_kind
	effect.position = pos
	effect.extent = p_extent
	effect.thickness = p_thickness
	effect.color = p_color
	parent.add_child(effect)
	effect._play()
	return effect


func _play() -> void:
	# A Tween animates properties over time. This one animates our "modulate"
	# (a color multiplied onto everything we draw), so the effect fades out,
	# and our scale, so it grows. Then it calls queue_free to delete the node.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.35).from(1.0)
	if kind == Kind.BLAST or kind == Kind.SPARKLE:
		tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.35).from(Vector2(0.4, 0.4))
	elif kind == Kind.ROW_BEAM:
		tween.tween_property(self, "scale:y", 0.1, 0.35).from(1.0)
	else:
		tween.tween_property(self, "scale:x", 0.1, 0.35).from(1.0)
	# chain() means: wait until everything above is finished, then continue.
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	match kind:
		Kind.ROW_BEAM:
			var rect := Rect2(-extent / 2.0, -thickness / 2.0, extent, thickness)
			draw_rect(rect, Color(color, 0.8))
			draw_rect(rect.grow_individual(0, -thickness * 0.3, 0, -thickness * 0.3), Color(1, 1, 1))
		Kind.COLUMN_BEAM:
			var rect := Rect2(-thickness / 2.0, -extent / 2.0, thickness, extent)
			draw_rect(rect, Color(color, 0.8))
			draw_rect(rect.grow_individual(-thickness * 0.3, 0, -thickness * 0.3, 0), Color(1, 1, 1))
		Kind.BLAST:
			draw_circle(Vector2.ZERO, extent, Color(color, 0.5))
			draw_arc(Vector2.ZERO, extent, 0.0, TAU, 40, Color(1, 1, 1), 6.0, true)
		_:
			for i in 8:
				var angle := i * TAU / 8.0
				var dir := Vector2(cos(angle), sin(angle))
				draw_line(dir * extent * 0.3, dir * extent, color, 4.0, true)
