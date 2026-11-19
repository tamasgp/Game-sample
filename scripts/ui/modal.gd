## Modal: a helper that builds popup windows in code.
##
## Every popup in the game looks the same: a dark see-through layer over
## the whole screen (which also blocks clicks to what is behind it), and a
## panel in the middle with a title. This helper builds that frame and returns
## the VBoxContainer inside, so callers only add their own content:
##
##     var box := Modal.open(self, "Out of moves!")
##     box.add_child(UIStyle.label("Buy 5 more moves?"))
##     ...
##     Modal.close(box)    # removes the whole popup
##
## (Godot has a built-in class called "Popup", so we picked another name.)
class_name Modal
extends RefCounted


static func open(parent: Node, title: String, min_width: float = 560.0) -> VBoxContainer:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Draw on top of everything else, including the HUD (z 1000) and garden
	# objects. Only the dialog box (2100) is higher.
	overlay.z_index = 2000
	parent.add_child(overlay)

	# CenterContainer keeps its only child in the middle.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := UIStyle.panel()
	panel.custom_minimum_size = Vector2(min_width, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	if title != "":
		box.add_child(UIStyle.label(title, 44, UIStyle.ACCENT))

	# Remember the overlay so close() can find it later. Metadata lets you
	# attach any value to any Object under a name.
	box.set_meta("overlay", overlay)

	# A little "pop" animation: fade in.
	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.2)
	return box


static func close(box: Control) -> void:
	if box != null and is_instance_valid(box) and box.has_meta("overlay"):
		var overlay: Node = box.get_meta("overlay")
		overlay.queue_free()


## A row of buttons side by side (for "Yes / No" choices).
static func button_row(box: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	return row
