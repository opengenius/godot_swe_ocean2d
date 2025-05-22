@tool
extends Node
class_name SWELocalSimulation

const grid_step_base = 2.17 * 0.5

@export var texture_size : Vector2i = Vector2i(256, 256)
@export var map_height_texture : Texture2D
@export var camera: Camera2D
@export var visualNode: Sprite2D


var texture := Texture2DRD.new()
var vel_texture := Texture2DRD.new()
var foam_texture := Texture2DRD.new()

var grid_dxdy := grid_step_base
var current_camera_rel_pos := Vector2.ZERO
var current_lin_scale:int = 1


# Called when the node enters the scene tree for the first time.
func _ready():
	RenderingServer.call_on_render_thread(_initialize_compute_code.bind(texture_size))


func _exit_tree():
	# Make sure we clean up!
	texture.texture_rd_rid = RID()
	vel_texture.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_free_compute_resources)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	const global_water_size := 2048 * 0.903 # @Water texture width * scale
	#const sim_step_base := 0.125 # 1/8 of simulation width
	const sim_step_base := 0.0625 # 1/16
	
	var vp_rect := camera.get_viewport_rect()
	var global_vp_size := vp_rect.size / camera.zoom
	
	var step_padding_scale = 1.0 / (1.0 - 2.0 * sim_step_base)
	var sim_scale = global_vp_size.x / global_water_size * step_padding_scale
	
	sim_scale = max(sim_scale, 0.125)
	
	var camera_rel_pos := Vector2.ZERO
	var snap := false
	if sim_scale > 1.0:
		sim_scale = 1.0
		current_camera_rel_pos = Vector2.ZERO
		current_lin_scale = 0
	else:
		var scale_lin := log(1.0 / sim_scale) / log(2)
		var scale_lin_int := int(scale_lin)
		if current_lin_scale != scale_lin_int:
			current_lin_scale = scale_lin_int
			snap = true
			
		sim_scale = 1.0 / (2 ** current_lin_scale)
	
		var camera_pos := camera.transform.get_origin()
		var global_water_half_size = Vector2(global_water_size, global_water_size) * 0.5
		camera_rel_pos = (camera_pos - global_water_half_size * sim_scale) / global_water_size
		camera_rel_pos = camera_rel_pos.clampf(0.0, 1.0 - sim_scale)

	var camera_pos_dif := camera_rel_pos - current_camera_rel_pos
	var step = sim_step_base * sim_scale
	if snap or abs(camera_pos_dif.x) >= step or abs(camera_pos_dif.y) >= step:
		current_camera_rel_pos = camera_rel_pos.snappedf(step)
	
	
	if visualNode != null:
		visualNode.transform.origin = current_camera_rel_pos * global_water_size
		var node_scale = sim_scale * global_water_size / visualNode.get_rect().size.x
		visualNode.scale = Vector2(node_scale, node_scale)
		
	grid_dxdy = grid_step_base * sim_scale
	texture.texture_rd_rid = height_map_rd
	vel_texture.texture_rd_rid = texture_velocity_rd
	foam_texture.texture_rd_rid = texture_foam_rd
		
	RenderingServer.call_on_render_thread(_render_process.bind(
			texture_size, delta,
			current_camera_rel_pos, sim_scale))


###############################################################################
# Rendering thread

var rd : RenderingDevice

const TEXTURES_COUNT : int = 2
const VELOCITY_SET_INDEX = 2

var linear_sampler: RID

# heigths
var height_map_rd : RID
var height_uset : RID

# velocities
var texture_velocity_rd: RID
var velocity_set: RID

# temp
var tmp_r_map_rd : RID
var tmp_r_uset : RID
var tmp_rg_map_rd : RID
var tmp_rg_uset : RID

# foam
var texture_foam_rd: RID
var foam_uset: RID

var texture_height_rd: RID
var height_us: RID

var fill_shader : RID
var fill_pipeline : RID
var vel_advect_shader: RID
var vel_shader : RID
var vel_pipeline : RID
var shader : RID
var pipeline : RID
var foam_shader : RID
var foam_pipeline : RID
var foam_adv_shader : RID
var foam_adv_pipeline : RID


func _create_uniform_set(shader : RID, texture_rd : RID, set_index = 0) -> RID:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rd)
	return rd.uniform_set_create([uniform], shader, set_index)

func _create_texture_uniform_set(shader : RID, texture : RID, set_index = 0) -> RID:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = 0
	uniform.add_id(linear_sampler)
	uniform.add_id(texture)
	
	return rd.uniform_set_create([uniform], shader, set_index)

func _initialize_compute_code(init_with_texture_size):
	# As this becomes part of our normal frame rendering,
	# we use our main rendering device here.
	rd = RenderingServer.get_rendering_device()
	
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler = rd.sampler_create(ss)
	
	# fill shader
	var fill_shader_file = load("res://shaders/swe/swe_local_fill_with_waves.glsl")
	fill_shader = rd.shader_create_from_spirv(fill_shader_file.get_spirv())
	fill_pipeline = rd.compute_pipeline_create(fill_shader)
	
	# Velocities shader
	var vel_shader_file = load("res://shaders/swe/swe_local_update_velocities.glsl")
	vel_shader = rd.shader_create_from_spirv(vel_shader_file.get_spirv())
	vel_pipeline = rd.compute_pipeline_create(vel_shader)

	# Height shader
	var shader_file = load("res://shaders/swe/swe_update.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	
	# Foam shader
	foam_shader = rd.shader_create_from_spirv(load("res://shaders/swe/foam_generate.glsl").get_spirv())
	foam_pipeline = rd.compute_pipeline_create(foam_shader)
	foam_adv_shader = rd.shader_create_from_spirv(load("res://shaders/swe/foam_advection.glsl").get_spirv())
	foam_adv_pipeline = rd.compute_pipeline_create(foam_adv_shader)
	
	
	#
	# Create textures
	#
	var image := map_height_texture.get_image()
	image.convert(Image.FORMAT_R8)
	
	var fmt = RDTextureFormat.new()
	fmt.width = image.get_width()
	fmt.height = image.get_height()
	fmt.mipmaps = image.get_mipmap_count() + 1
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	if Engine.is_editor_hint():
		fmt.usage_bits += RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	texture_height_rd = rd.texture_create(fmt, RDTextureView.new(), [image.get_data()])
	height_us = _create_texture_uniform_set(vel_shader, texture_height_rd, 1)
	
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = init_with_texture_size.x
	tf.height = init_with_texture_size.y
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT  | RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	if Engine.is_editor_hint():
		tf.usage_bits += RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	height_map_rd = rd.texture_create(tf, RDTextureView.new(), [])
	rd.texture_clear(height_map_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)
	height_uset = _create_uniform_set(shader, height_map_rd)
	
	tmp_r_map_rd = rd.texture_create(tf, RDTextureView.new(), [])
	tmp_r_uset = _create_uniform_set(shader, tmp_r_map_rd)
	
	# velocity texture
	tf.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	
	tmp_rg_map_rd = rd.texture_create(tf, RDTextureView.new(), [])
	tmp_rg_uset = _create_uniform_set(shader, tmp_rg_map_rd, VELOCITY_SET_INDEX)
	
	var texture_rd := rd.texture_create(tf, RDTextureView.new(), [])
	texture_velocity_rd = texture_rd
	rd.texture_clear(texture_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)
	velocity_set = _create_uniform_set(shader, texture_rd, VELOCITY_SET_INDEX)
	
	# foam texture
	tf.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	texture_foam_rd = rd.texture_create(tf, RDTextureView.new(), [])
	
	rd.texture_clear(texture_foam_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)
	foam_uset = _create_uniform_set(foam_shader, texture_foam_rd, 1)


func _free_compute_resources():
	rd.free_rid(height_map_rd)
	rd.free_rid(tmp_r_map_rd)
	
	if texture_velocity_rd:
		rd.free_rid(texture_velocity_rd)

	if shader:
		rd.free_rid(shader)
	if vel_shader:
		rd.free_rid(vel_shader)
	if vel_advect_shader:
		rd.free_rid(vel_advect_shader)
	if fill_shader:
		rd.free_rid(fill_shader)
	# todo: pipeline, uniform sets?

var rtime = 0.0
var r_cam_pos := Vector2(100, 100)
var r_cam_scale := 1.0

func push_vec(arr : PackedFloat32Array, v: Vector4):
	arr.push_back(v.x)
	arr.push_back(v.y)
	arr.push_back(v.z)
	arr.push_back(v.w)

func _render_process(tex_size: Vector2i, delta: float, 
		camera_pos: Vector2, camera_zoom: float):
	rtime += delta
	
	var dxdy := grid_step_base * camera_zoom
	
	var camera_dscale := camera_zoom / r_cam_scale
	var camera_dpos := (camera_pos - r_cam_pos) / camera_zoom * camera_dscale

	var prev_pos2d_scale := Vector4(camera_dpos.x, camera_dpos.y, camera_dscale, 0)
	var pos2d_scale := Vector4(camera_pos.x, camera_pos.y, camera_zoom, 0)
	
	r_cam_pos = camera_pos
	r_cam_scale = camera_zoom
	
	#if camera_dpos.x != 0.0 or camera_dpos.y != 0.0:
		#rd.texture_clear(texture_foam_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)
	
	# We don't have structures (yet) so we need to build our push constant
	# "the hard way"...
	var push_constant : PackedFloat32Array = PackedFloat32Array()
	push_constant.push_back(tex_size.x)
	push_constant.push_back(tex_size.y)
	push_constant.push_back(dxdy)
	push_constant.push_back(delta)
	push_vec(push_constant, prev_pos2d_scale)
	push_vec(push_constant, pos2d_scale)

	# Calculate our dispatch group size.
	# We do `n - 1 / 8 + 1` in case our texture size is not nicely
	# divisible by 8.
	# In combination with a discard check in the shader this ensures
	# we cover the entire texture.
	var x_groups = (tex_size.x - 1) / 8 + 1
	var y_groups = (tex_size.y - 1) / 8 + 1
	
	#rd.capture_timestamp("SWE")
	
	var compute_list := rd.compute_list_begin()
	
	# fill heights
	var fill_constants : PackedFloat32Array = PackedFloat32Array()
	fill_constants.push_back(tex_size.x)
	fill_constants.push_back(tex_size.y)
	fill_constants.push_back(dxdy)
	fill_constants.push_back(rtime)
	push_vec(fill_constants, prev_pos2d_scale)
	push_vec(fill_constants, pos2d_scale)
	rd.compute_list_bind_compute_pipeline(compute_list, fill_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, height_uset, 0)
	rd.compute_list_bind_uniform_set(compute_list, tmp_r_uset, 1)
	rd.compute_list_bind_uniform_set(compute_list, height_us, 2)
	rd.compute_list_bind_uniform_set(compute_list, velocity_set, 3)
	rd.compute_list_bind_uniform_set(compute_list, tmp_rg_uset, 4)
	rd.compute_list_set_push_constant(compute_list, fill_constants.to_byte_array(), fill_constants.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# advect + update velocities
	rd.compute_list_bind_compute_pipeline(compute_list, vel_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, tmp_r_uset, 0)
	rd.compute_list_bind_uniform_set(compute_list, height_us, 1)
	rd.compute_list_bind_uniform_set(compute_list, tmp_rg_uset, 2)
	rd.compute_list_bind_uniform_set(compute_list, velocity_set, 3)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# update heights
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, tmp_r_uset, 0)
	rd.compute_list_bind_uniform_set(compute_list, height_uset, 1)
	rd.compute_list_bind_uniform_set(compute_list, velocity_set, VELOCITY_SET_INDEX)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 4 * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# update foam
	rd.compute_list_bind_compute_pipeline(compute_list, foam_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, velocity_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, foam_uset, 1)
	rd.compute_list_bind_uniform_set(compute_list, tmp_r_uset, 2)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 4 * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# advect foam
	rd.compute_list_bind_compute_pipeline(compute_list, foam_adv_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, velocity_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, tmp_r_uset, 1)
	rd.compute_list_bind_uniform_set(compute_list, foam_uset, 2)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 4 * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	rd.compute_list_end()
