extends Camera2D

#var localWaterNode = $root/WaterLocal
@export
var move_target: Sprite2D

var mouse_start_pos := Vector2.ZERO
var screen_start_position := Vector2.ZERO

var DRAG_THRESHOLD := 10  # Pixels
var drag_is_pressed := false
var dragging := false


func _input(event):
	if event.is_action("zoom_in"):
		zoom *= 1.05
	elif event.is_action("zoom_out"):
		zoom *= 1 / 1.05
		
	elif event.is_action("drag"):
		if event.is_pressed():
			mouse_start_pos = event.position
			screen_start_position = position
			drag_is_pressed = true
		else:
			if not dragging and move_target != null:
				#var inv_view := get_global_transform().affine_inverse()
				#inv_view. * event.position
				var half_vp_size := Vector2(get_viewport().size) * 0.5
				var target_position := position + (event.position as Vector2 - half_vp_size) / zoom
				move_target.move_to(target_position)
			drag_is_pressed = false
			dragging = false
			
	elif event is InputEventMouseMotion and drag_is_pressed:
		var mouse_diff := event.position as Vector2 - mouse_start_pos
		if mouse_diff.length() > DRAG_THRESHOLD:
			dragging = true
		if dragging:
			position = -mouse_diff / zoom + screen_start_position 
