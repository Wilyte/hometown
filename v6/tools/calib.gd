extends Node3D
## 光照/颜色标定：把 Godot 的归一化系数和"Color 是不是 sRGB→线性"两件事一次测清。
##   pwsh v6/tools/calib.ps1   →  shots/calib_*.png，再由 read_calib.py 读像素
##
## 平板始终正对太阳（dotNL=1）：
##   B  albedo 白、太阳白、E=0.25        → 直接给平行光的系数 k_dir
##   C  albedo 白、太阳灰(0.5)、E=0.25   → 说明 light_color 是否被 sRGB→线性
##   D  albedo 白、环境色灰(0.5)、E=1.0  → 说明 ambient_light_color 的处理
##   E  albedo 灰(0.5)、太阳白、E=1.0    → 说明 albedo_color 是否被 sRGB→线性
##   A  背景灰(0.5)                      → 说明 background_color 的处理

const GRAY := 0.5
const WHITE := 1.0

var _sun: DirectionalLight3D
var _plane: MeshInstance3D
var _mat: StandardMaterial3D
var _env: Environment
var _we: WorldEnvironment
var _out_dir := "user://"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--calib-dir="):
			_out_dir = a.substr(12).trim_suffix("/") + "/"


func _ready() -> void:
	_plane = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	_plane.mesh = pm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(WHITE, WHITE, WHITE)
	_mat.roughness = 1.0
	_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mat.metallic = 0.0
	_plane.material_override = _mat
	add_child(_plane)

	var cam := Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	cam.global_position = Vector3(0, 6, 0)
	cam.look_at(Vector3.ZERO, Vector3.FORWARD)

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0, 0, 0)
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.tonemap_exposure = 1.0
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_we = WorldEnvironment.new()
	_we.environment = _env
	add_child(_we)

	_sun = DirectionalLight3D.new()
	add_child(_sun)
	_sun.global_position = Vector3(0, 10, 0)
	_sun.look_at(Vector3.ZERO, Vector3.FORWARD)
	_sun.light_energy = 1.0
	_sun.light_color = Color.WHITE
	_sun.shadow_enabled = false

	await get_tree().process_frame
	await _run()
	get_tree().quit()


func _run() -> void:
	# A：背景灰
	_plane.visible = false
	_sun.visible = false
	_env.background_color = Color(GRAY, GRAY, GRAY)
	await _shot("calib_A_bg_gray50.png")

	# B：albedo 白 + 太阳白 E=0.25
	_plane.visible = true
	_env.background_color = Color(0, 0, 0)
	_mat.albedo_color = Color(WHITE, WHITE, WHITE)
	_sun.visible = true
	_sun.light_color = Color(WHITE, WHITE, WHITE)
	_sun.light_energy = 0.25
	await _shot("calib_B_sun_white_e025.png")

	# C：太阳灰(0.5) E=0.25
	_sun.light_color = Color(GRAY, GRAY, GRAY)
	_sun.light_energy = 0.25
	await _shot("calib_C_sun_gray50_e025.png")

	# D：环境色灰(0.5) E=1.0
	_sun.visible = false
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.set("ambient_light_color", Color(GRAY, GRAY, GRAY))
	_env.ambient_light_energy = 1.0
	await _shot("calib_D_amb_gray50_e100.png")

	# E：albedo 灰(0.5) + 太阳白 E=1.0
	_sun.visible = true
	_sun.light_color = Color.WHITE
	_sun.light_energy = 1.0
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_mat.albedo_color = Color(GRAY, GRAY, GRAY)
	await _shot("calib_E_albedo_gray50_e100.png")

	# F：天光纯白 radiance_scale=1，albedo 白
	_mat.albedo_color = Color(WHITE, WHITE, WHITE)
	_sun.visible = false
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/hemi_sky.gdshader")
	sm.set_shader_parameter("sky_color", Color(WHITE, WHITE, WHITE))
	sm.set_shader_parameter("ground_color", Color(WHITE, WHITE, WHITE))
	sm.set_shader_parameter("radiance_scale", 1.0)
	sky.sky_material = sm
	_env.sky = sky
	await _shot("calib_F_sky_white_e100.png")


func _shot(file_name: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir + file_name)
	print("CALIB saved %s%s" % [_out_dir, file_name])
