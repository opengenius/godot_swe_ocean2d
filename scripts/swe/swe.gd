@tool
extends Node
class_name SWESimulation

const dxdy := 1.084 #0.4

@export var texture_size : Vector2i = Vector2i(512, 512)
@export var map_height_texture : Texture2D

var texture := Texture2DRD.new()
var vel_texture := Texture2DRD.new()
var foam_texture := Texture2DRD.new()
var next_texture : int = 0


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
	# Increase our next texture index.
	next_texture = (next_texture + 1) % TEXTURES_COUNT

	# Update our texture to show our next result (we are about to create).
	# Note that `_initialize_compute_code` may not have run yet so the first
	# frame this my be an empty RID.
	texture.texture_rd_rid = texture_rds[next_texture]
	vel_texture.texture_rd_rid = texture_velocity_rd
	foam_texture.texture_rd_rid = texture_foam_rd
		
	RenderingServer.call_on_render_thread(_render_process.bind(next_texture, texture_size, delta))


###############################################################################
# Rendering thread

const TEXTURES_COUNT : int = 2
const VELOCITY_SET_INDEX = 2

var rd : RenderingDevice

var linear_sampler: RID

var init_shader : RID
var init_pipeline : RID
var fill_shader : RID
var fill_pipeline : RID
var vel_advect_shader: RID
var vel_advect_pipeline : RID
var vel_shader : RID
var vel_pipeline : RID
var shader : RID
var pipeline : RID
var foam_shader : RID
var foam_pipeline : RID
var foam_adv_shader : RID
var foam_adv_pipeline : RID

# heigths
var texture_rds : Array = []

# velocity
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

var texture_sets : Array = []

var init_heights = true
var rtime = 0.0


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

	var init_shader_file = load("res://shaders/swe/swe_fill_initial_heights.glsl")
	init_shader = rd.shader_create_from_spirv(init_shader_file.get_spirv())
	init_pipeline = rd.compute_pipeline_create(init_shader)
	
	var fill_shader_file = load("res://shaders/swe/swe_fill_with_waves.glsl")
	fill_shader = rd.shader_create_from_spirv(fill_shader_file.get_spirv())
	fill_pipeline = rd.compute_pipeline_create(fill_shader)

	# Advect velocities shader
	var vel_advect_shader_file = load("res://shaders/swe/swe_local_advect_velocities.glsl")
	vel_advect_shader = rd.shader_create_from_spirv(vel_advect_shader_file.get_spirv())
	vel_advect_pipeline = rd.compute_pipeline_create(vel_advect_shader)
	
	# Velocities shader
	var vel_shader_file = load("res://shaders/swe/swe_update_velocities.glsl")
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
	
	for i in range(TEXTURES_COUNT):
		texture_rds.push_back(rd.texture_create(tf, RDTextureView.new(), []))
		rd.texture_clear(texture_rds[i], Color(0, 0, 0, 0), 0, 1, 0, 1)
		texture_sets.push_back(_create_uniform_set(shader, texture_rds[i]))
	
	tmp_r_map_rd = rd.texture_create(tf, RDTextureView.new(), [])
	tmp_r_uset = _create_uniform_set(shader, tmp_r_map_rd)
	
	# velocities texture
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
	# Note that our sets and pipeline are cleaned up automatically as they are dependencies :P
	for i in range(TEXTURES_COUNT):
		if texture_rds[i]:
			rd.free_rid(texture_rds[i])
	rd.free_rid(texture_velocity_rd)

	if shader:
		rd.free_rid(shader)
	if vel_shader:
		rd.free_rid(vel_shader)
	if fill_shader:
		rd.free_rid(fill_shader)
	# todo: pipeline, uniform sets?


func _render_process(param_next_texture, tex_size, delta):
	rtime += delta
	
	# We don't have structures (yet) so we need to build our push constant
	# "the hard way"...
	var push_constant : PackedFloat32Array = PackedFloat32Array()
	push_constant.push_back(tex_size.x)
	push_constant.push_back(tex_size.y)
	push_constant.push_back(dxdy)
	push_constant.push_back(delta)
	push_constant.push_back(0.0)
	push_constant.push_back(0.0)
	push_constant.push_back(1.0)
	push_constant.push_back(0.0)
	push_constant.push_back(0.0)
	push_constant.push_back(0.0)
	push_constant.push_back(1.0)
	push_constant.push_back(0.0)

	# Calculate our dispatch group size.
	# We do `n - 1 / 8 + 1` in case our texture size is not nicely
	# divisible by 8.
	# In combination with a discard check in the shader this ensures
	# we cover the entire texture.
	var x_groups = (tex_size.x - 1) / 8 + 1
	var y_groups = (tex_size.y - 1) / 8 + 1
	
	var current_tex_index = (param_next_texture - 1) % TEXTURES_COUNT
	
	var compute_list := rd.compute_list_begin()
	
	if init_heights:
		init_heights = false
		# fill initial heights
		var fill_constants : PackedFloat32Array = PackedFloat32Array()
		fill_constants.push_back(tex_size.x)
		fill_constants.push_back(tex_size.y)
		fill_constants.push_back(0.0)
		fill_constants.push_back(0.0)
		rd.compute_list_bind_compute_pipeline(compute_list, init_pipeline)
		rd.compute_list_bind_uniform_set(compute_list, texture_sets[current_tex_index], 0)
		rd.compute_list_bind_uniform_set(compute_list, height_us, 1)
		rd.compute_list_set_push_constant(compute_list, fill_constants.to_byte_array(), fill_constants.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# fill heights
	var fill_constants : PackedFloat32Array = PackedFloat32Array()
	fill_constants.push_back(tex_size.x)
	fill_constants.push_back(tex_size.y)
	fill_constants.push_back(dxdy)
	fill_constants.push_back(rtime)
	rd.compute_list_bind_compute_pipeline(compute_list, fill_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, texture_sets[current_tex_index], 0)
	rd.compute_list_bind_uniform_set(compute_list, height_us, 1)
	rd.compute_list_set_push_constant(compute_list, fill_constants.to_byte_array(), fill_constants.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# advect velocities
	rd.compute_list_bind_compute_pipeline(compute_list, vel_advect_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, velocity_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, tmp_rg_uset, 1)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# update velocities
	rd.compute_list_bind_compute_pipeline(compute_list, vel_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, texture_sets[current_tex_index], 0)
	rd.compute_list_bind_uniform_set(compute_list, height_us, 1)
	rd.compute_list_bind_uniform_set(compute_list, velocity_set, VELOCITY_SET_INDEX)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 4 * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# update heights
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, texture_sets[current_tex_index], 0)
	rd.compute_list_bind_uniform_set(compute_list, texture_sets[param_next_texture], 1)
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
