#@tool
extends Sprite2D

@export var swe: SWELocalSimulation

# Called when the node enters the scene tree for the first time.
func _ready():
	self.material.set_shader_parameter("velocity_map", swe.vel_texture)
	self.material.set_shader_parameter("foam_mask_map", swe.foam_texture)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
	var pos_scale := Vector4.ZERO
	pos_scale.x = swe.current_camera_rel_pos.x
	pos_scale.y = swe.current_camera_rel_pos.y
	pos_scale.z = 1.0 / (2 ** swe.current_lin_scale)
	self.material.set_shader_parameter("current_pos2d_scale", pos_scale)
