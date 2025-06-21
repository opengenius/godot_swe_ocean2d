@tool
extends Sprite2D

const SWELocal = preload("res://scripts/swe/swe_local.gd")

@export var swe: SWELocalSimulation
@export var movingObj: Sprite2D
const DRAW_LINES = false
const GRID_SIZE = 74

var movingObjPrevPos := Vector2()
const objRadius = 1.0


# Called when the node enters the scene tree for the first time.
func _ready():
	self.material.set_shader_parameter(&"sim_height_map", swe.texture)
	self.material.set_shader_parameter(&"velocity_map", swe.vel_texture)
	self.material.set_shader_parameter(&"foam_mask_map", swe.foam_texture)


func move_to(target_pos: Vector2):
	if movingObj == null: return
	
	var lpos := to_local(target_pos)
	var rpos := lpos / get_rect().size
	movingObj.move_to(rpos * Vector2(swe.texture_size))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	await RenderingServer.frame_post_draw
	
	# movingObj is positions int the space of its viewport(512x512)(should be the same as swe sim size)
	if movingObj != null:
		var deltaPos = movingObj.position - movingObjPrevPos
		#if true:
		if deltaPos.length() >= 0.001: #objRadius * 0.25:
			movingObjPrevPos = movingObj.position
			var imp = SWELocal.ImpulseData.new()
			imp.pos = movingObj.position
			imp.dir = deltaPos.normalized()
			imp.radius = objRadius
			imp.strength = 0.15 * delta
			swe.add_impulse(imp)
		
	
	var pos_scale := Vector4.ZERO
	pos_scale.x = swe.current_camera_rel_pos.x
	pos_scale.y = swe.current_camera_rel_pos.y
	pos_scale.z = 1.0 / (2 ** swe.current_lin_scale)
	self.material.set_shader_parameter(&"current_pos2d_scale", pos_scale)


func _draw():
	
	if not DRAW_LINES:
		return
		
	var w = get_rect().size.x
	var h = get_rect().size.y
	for yi in range(GRID_SIZE):
		var y = float(yi) / GRID_SIZE * h
		draw_line(Vector2(0, y), Vector2(w, y), Color.BLACK)
	for xi in range(GRID_SIZE):
		var x = float(xi) / GRID_SIZE * w
		draw_line(Vector2(x, 0), Vector2(x, h), Color.BLACK)
