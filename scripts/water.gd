@tool
extends Sprite2D

@export var swe: SWESimulation

# Called when the node enters the scene tree for the first time.
func _ready():
	pass
	#self.texture = swe.texture
	self.material.set_shader_parameter("current_pos2d_scale", Vector4(0.0, 0.0, 1.0, 0.0))
	self.material.set_shader_parameter("velocity_map", swe.vel_texture)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
