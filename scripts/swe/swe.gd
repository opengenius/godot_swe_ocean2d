@tool
extends Node
class_name SWESimulation

const dxdy := 1.084 * 0.5

@export var texture_size : Vector2i = Vector2i(512, 512)
@export var map_height_texture : Texture2D

var texture := Texture2DRD.new()
var vel_texture := Texture2DRD.new()
var foam_texture := Texture2DRD.new()


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
	# Update our texture to show our next result (we are about to create).
	# Note that `_initialize_compute_code` may not have run yet so the first
	# frame this my be an empty RID.
	texture.texture_rd_rid = dyn_height_rd
	vel_texture.texture_rd_rid = texture_velocity_rd
	foam_texture.texture_rd_rid = texture_foam_rd
		
	RenderingServer.call_on_render_thread(_render_process.bind(texture_size, delta))


###############################################################################
# Rendering thread

var rd : RenderingDevice

var linear_sampler: RID

var init_shader : RID
var init_pipeline : RID
var fill_shader : RID
var fill_pipeline : RID
var vel_shader : RID
var vel_pipeline : RID
var shader : RID
var pipeline : RID
var foam_shader : RID
var foam_pipeline : RID
var foam_adv_shader : RID
var foam_adv_pipeline : RID

# heigth
var dyn_height_rd : RID

# velocity
var texture_velocity_rd: RID

# temp
var tmp_r_map_rd : RID
var tmp_rg_map_rd : RID

# foam
var texture_foam_rd: RID

var sim_us : RID

var init_heights = true
var rtime = 0.0


func _make_image_uniform(binding_index: int, texture_rd: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding_index
	uniform.add_id(texture_rd)
	return uniform
	
func _make_linear_sampler_uniform(binding_index: int, texture_rd: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding_index
	uniform.add_id(linear_sampler)
	uniform.add_id(texture_rd)
	return uniform
	
func _make_ub_uniform(binding_index: int, ub_rd: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = binding_index
	uniform.add_id(ub_rd)
	return uniform

func push_vec(arr : PackedFloat32Array, v: Vector4):
	arr.push_back(v.x)
	arr.push_back(v.y)
	arr.push_back(v.z)
	arr.push_back(v.w)
	
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
	
	dyn_height_rd = rd.texture_create(tf, RDTextureView.new(), [])
	rd.texture_clear(dyn_height_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)
	
	tmp_r_map_rd = rd.texture_create(tf, RDTextureView.new(), [])
	
	# velocities texture
	tf.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	
	tmp_rg_map_rd = rd.texture_create(tf, RDTextureView.new(), [])
	
	texture_velocity_rd = rd.texture_create(tf, RDTextureView.new(), [])
	rd.texture_clear(texture_velocity_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)
	
	# foam texture
	tf.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	texture_foam_rd = rd.texture_create(tf, RDTextureView.new(), [])
	
	rd.texture_clear(texture_foam_rd, Color(0, 0, 0, 0), 0, 1, 0, 1)
	
	var wave_params : PackedFloat32Array = PackedFloat32Array()
	push_vec(wave_params, Vector4(0.011, 2.83, 2.7, 0.942))
	push_vec(wave_params, Vector4(0.01, 3.032, 2.6, 0.954))
	push_vec(wave_params, Vector4(0.007, 3.266, 2.5, 0.967))
	# dirs
	push_vec(wave_params, Vector4(0.707, 0.707, 0.0, 0.0))
	push_vec(wave_params, Vector4(0.928, 0.371, 0.0, 0.0))
	push_vec(wave_params, Vector4(0.819, 0.573, 0.0, 0.0))
	var wave_params_ub := rd.uniform_buffer_create(wave_params.size() * 4, wave_params.to_byte_array())
	
	var texture_height_rd := RenderingServer.texture_get_rd_texture(map_height_texture.get_rid())
	
	sim_us = rd.uniform_set_create(
		[_make_image_uniform(0, dyn_height_rd),
		_make_image_uniform(1, texture_velocity_rd), 
		_make_linear_sampler_uniform(2, texture_height_rd),
		_make_image_uniform(3, tmp_r_map_rd),
		_make_image_uniform(4, tmp_rg_map_rd),
		_make_image_uniform(5, texture_foam_rd),
		_make_ub_uniform(6, wave_params_ub)],
		vel_shader, 0)


func _free_compute_resources():
	# Note that our sets and pipeline are cleaned up automatically as they are dependencies :P
	rd.free_rid(dyn_height_rd)
	rd.free_rid(texture_velocity_rd)

	if shader:
		rd.free_rid(shader)
	if vel_shader:
		rd.free_rid(vel_shader)
	if fill_shader:
		rd.free_rid(fill_shader)
	# todo: pipeline, uniform sets?


func _render_process(tex_size, delta):
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
		rd.compute_list_bind_uniform_set(compute_list, sim_us, 0)
		rd.compute_list_set_push_constant(compute_list, fill_constants.to_byte_array(), fill_constants.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# fill heights
	var fill_constants : PackedFloat32Array = PackedFloat32Array()
	fill_constants.push_back(tex_size.x)
	fill_constants.push_back(tex_size.y)
	fill_constants.push_back(dxdy)
	fill_constants.push_back(rtime)
	rd.compute_list_bind_compute_pipeline(compute_list, fill_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sim_us, 0)
	rd.compute_list_set_push_constant(compute_list, fill_constants.to_byte_array(), fill_constants.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
		# advect + update velocities
	rd.compute_list_bind_compute_pipeline(compute_list, vel_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sim_us, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# update heights
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sim_us, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 4 * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
		# update foam
	rd.compute_list_bind_compute_pipeline(compute_list, foam_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sim_us, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 8 * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	# advect foam
	rd.compute_list_bind_compute_pipeline(compute_list, foam_adv_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sim_us, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 4 * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	rd.compute_list_end()
