## DialogBox: the story character talking at the bottom of the screen.
##
## Usage (from any coroutine):
##     var dialog := DialogBox.new()
##     add_child(dialog)
##     await dialog.say(["Hello!", "Second line."])
##     # ...continues here after the player tapped through every line
##
## The box covers the whole screen with an invisible layer, so taps anywhere
## advance the text (and can't reach the buttons behind it).
##
## TYPEWRITER EFFECT: Label.visible_ratio (0..1) controls how much of the text
## is shown. Tweening it from 0 to 1 makes the letters appear one by one.
## Tapping while the text is still typing shows it all at once. That's a small
## but important detail for impatient players.
class_name DialogBox
extends Control

## Emitted after the last line was dismissed.
signal finished

var _lines: Array = []
var _index: int = 0
var _text: Label
var _typing: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # swallow every tap
	z_index = 60
	visible = false

	var panel := UIStyle.panel()
	# Anchor the panel to the bottom of the screen, full width.
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20
	panel.offset_right = -20
	panel.offset_top = -330
	panel.offset_bottom = -140
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	row.add_child(Portrait.new())

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	var name_label := UIStyle.label(GardenData.HELPER_NAME, 30, UIStyle.ACCENT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(name_label)
	_text = UIStyle.label("", 26)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wrap long lines
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_text)
	var hint := UIStyle.label("tap to continue", 18, UIStyle.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(hint)


## Shows the lines one after another. `await` it to wait until done.
func say(lines: Array) -> void:
	if lines.is_empty():
		return
	_lines = lines
	_index = 0
	visible = true
	_show_line()
	await finished


func _show_line() -> void:
	_text.text = _lines[_index]
	_text.visible_ratio = 0.0
	if _typing != null:
		_typing.kill()
	_typing = create_tween()
	# Longer lines take longer to type: 0.03 seconds per character.
	_typing.tween_property(_text, "visible_ratio", 1.0, _text.text.length() * 0.03)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if _text.visible_ratio < 1.0:
		# Still typing: finish the line instantly.
		_typing.kill()
		_text.visible_ratio = 1.0
		return
	_index += 1
	if _index < _lines.size():
		_show_line()
	else:
		visible = false
		finished.emit()


## The gardener's face, drawn with circles. An INNER CLASS: a class defined
## inside another script, useful for small helpers nobody else needs.
class Portrait extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(130, 130)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 62.0, Color(0.55, 0.8, 0.5))                           # background
		draw_circle(c + Vector2(0, -8), 44.0, Color(0.45, 0.25, 0.12))        # hair
		draw_circle(c + Vector2(0, 6), 36.0, Color(1.0, 0.82, 0.66))          # face
		draw_circle(c + Vector2(-13, 2), 5.0, Color(0.15, 0.1, 0.1))          # eyes
		draw_circle(c + Vector2(13, 2), 5.0, Color(0.15, 0.1, 0.1))
		draw_arc(c + Vector2(0, 14), 12.0, 0.3, PI - 0.3, 12, Color(0.6, 0.2, 0.2), 3.0, true)   # smile
		draw_circle(c + Vector2(-22, 14), 6.0, Color(1, 0.55, 0.55, 0.6))     # cheeks
		draw_circle(c + Vector2(22, 14), 6.0, Color(1, 0.55, 0.55, 0.6))
		# A straw hat with a flower.
		draw_colored_polygon(UIStyle.ellipse_points(c + Vector2(0, -32), Vector2(58, 14), 20), Color(0.95, 0.82, 0.45))
		draw_colored_polygon(UIStyle.ellipse_points(c + Vector2(0, -44), Vector2(30, 18), 20), Color(0.95, 0.82, 0.45))
		draw_circle(c + Vector2(22, -40), 7.0, Color(1, 0.45, 0.6))
