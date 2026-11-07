extends Node3D
## v6·Campground & Lake
##
## 把 polyfork 的 Campground & Lake kit（单文件场景 GLB，19.87MB / 533 mesh / 162k tris）
## 在 Godot 里跑起来，默认视角、背景、光照逐项对齐页面观看器：
##   https://polyfork.dev/kit/campground-lake-ad32b0
##
## 页面那边的真实参数（viewer.js + 页面 mountViewer 调用）：
##   PerspectiveCamera(fov 38, near 0.01, far 200)
##   d = 包围球半径 / sin(fov/2) * fit(0.525)，pitch 17.8°，yaw 0.61
##   HemisphereLight(0xffffff, 0xb8b0a4, 1.15)
##   DirectionalLight(0xfff2e0, 2.4) @ (4,7,5)  PCFSoft 4096 阴影
##   DirectionalLight(0xdfe8ff, 0.9) @ (-5,4,-6)
##   背景 0xeaf1fe（页面舞台同色）
## 参数都放在 data/look.json，改数不用改代码。

const GLB_PATH := "res://assets/kit_campground_lake/kit-campground-lake-ad32b0.glb"
const LOOK_PATH := "res://data/look.json"
const HEMI_SKY_SHADER := "res://shaders/hemi_sky.gdshader"

var look: Dictionary = {}
## 编辑器（scripts/editor.gd）继承本脚本时置 true：跳过取景后的出帧自退出
var edit_mode := false

var world_root: Node3D
var actors: ActorSystem
var center := Vector3.ZERO
var radius := 1.0
var bounds := AABB()

var cam: Camera3D
var yaw := 0.0
var pitch := 0.0
var distance := 1.0
var min_distance := 1.0
var max_distance := 1.0

var base_distance := 1.0
var _zoom_pivot := Vector3.ZERO
var _zoom_pivot_valid := false
var _zoom_factor := 0.85
var _touches := {}
var _pinch_prev := 0.0
var _pinch_mid := Vector2.ZERO
var _dragging := false
var _last_mouse := Vector2.ZERO
var _yaw_vel := 0.0
var _pitch_vel := 0.0
var _zoom_vel := 0.0

## three.js OrbitControls 的阻尼系数（enableDamping, dampingFactor 0.05）
const DAMPING := 0.05
const RECOVER := 0.95
const ROTATE_SPEED := 1.0
const ZOOM_SPEED := 1.0


func _ready() -> void:
	look = _load_look()
	_load_world()
	_build_environment()
	_build_lights()
	await _build_contact_shadow()
	_build_camera()
	_frame_camera()
	_print_stats()
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	if "--touchtest" in OS.get_cmdline_user_args():
		await _touchtest()
	if "--orbitest" in OS.get_cmdline_user_args():
		await _orbitest()
	if "--zoomtest" in OS.get_cmdline_user_args():
		await _zoomtest()
	var sim_t := _arg_value("--sim-t")
	if sim_t != "" and actors != null:
		actors.advance(float(sim_t))
		print("ACTORS sim-t=%.2fs" % float(sim_t))
		actors.report()
		var fa := _arg_value("--focus-actor")
		if fa != "" and actors.pos_of(fa) != null:
			center = actors.pos_of(fa)
			_apply_camera()
			print("ACTORS focus-actor=%s at %s" % [fa, str(center)])
	if "--bench" in OS.get_cmdline_user_args():
		await _bench()
	if not edit_mode:
		_maybe_shot()


# ---------------------------------------------------------------- 场景内容

## 世界来源二选一：map.json（part 库拼装，可编辑）或整张 GLB（原始备份）。
func _load_world() -> void:
	var map_path := _map_path()
	var world: Node3D = null
	if map_path != "":
		world = _build_from_map(map_path)
	if world == null:
		world = _build_from_glb()
	world_root = world
	add_child(world)
	_enable_vertex_colors(world)
	_dedupe_materials(world)
	_build_heightmap(world)
	if not edit_mode and "--no-actors" not in OS.get_cmdline_user_args():
		var acfg: Dictionary = look.get("actors", {})
		if bool(acfg.get("enabled", true)):
			actors = ActorSystem.new()
			actors.name = "Actors"
			add_child(actors)
			actors.setup(world, acfg)
	bounds = _world_bounds(world)
	center = bounds.get_center()
	# 与 three.js 的 Box3.getBoundingSphere 完全一致：半径 = 半对角线长
	radius = bounds.size.length() * 0.5


func _map_path() -> String:
	var p := _arg_value("--map")
	if p != "":
		return p if p.begins_with("res://") or p.begins_with("user://") else "res://" + p
	return String(look.get("map", ""))


func _build_from_map(path: String) -> Node3D:
	var data := MapWorld.load_map(path)
	if data.is_empty():
		push_warning("读不到地图 %s，回退到整张 GLB" % path)
		return null
	var map := Node3D.new()
	map.name = "Map"
	var n := MapWorld.build(data, map)
	print("MAP %s items=%d" % [path, n])
	return map


func _item_transform(it: Dictionary) -> Transform3D:
	return MapWorld.item_transform(it)


func _build_from_glb() -> Node3D:
	var scene: PackedScene = load(GLB_PATH)
	if scene == null:
		push_error("GLB 没有导入：%s" % GLB_PATH)
		return Node3D.new()
	var kit: Node3D = scene.instantiate()
	kit.name = "Kit"
	print("MAP 无 map.json，用整张 GLB")
	return kit


func _enable_vertex_colors(root: Node) -> void:
	## godot 的 glTF 导入没有自动打开 vertex_color_use_as_albedo（实测 536/536 都是 false），
	## 这套 kit 的颜色全在 COLOR_0 顶点色里，不打开就整片白。材质是共享资源，改一次即可。
	var seen := {}
	var n_mats := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat == null or not (mat is BaseMaterial3D):
				continue
			var id := mat.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			(mat as BaseMaterial3D).vertex_color_use_as_albedo = true
			n_mats += 1
	print("MATS vertex_color_use_as_albedo=true on %d materials" % n_mats)


func _dedupe_materials(root: Node) -> void:
	## 拆出来的 part 各自内嵌一份 StandardMaterial3D（参数其实重复），不去重的话
	## Godot 无法在 part 之间合批，帧时从 6.7 ms 涨到 11.9 ms。这里按参数签名合并。
	var canon := {}
	var replaced := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for surf in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(surf)
			if not (mat is BaseMaterial3D):
				continue
			var bm := mat as BaseMaterial3D
			var key := "%s|%.3f|%.3f|%s|%d|%d" % [
				str(bm.albedo_color), bm.roughness, bm.metallic,
				str(bm.vertex_color_use_as_albedo), int(bm.transparency), int(bm.shading_mode)]
			if canon.has(key):
				mi.mesh.surface_set_material(surf, canon[key])
				replaced += 1
			else:
				canon[key] = bm
	print("MATS dedupe: %d 份 → %d 份（替换 %d 个 surface）" % [
		canon.size() + replaced, canon.size(), replaced])


func _world_bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				if first:
					box = b
					first = false
				else:
					box = box.merge(b)
		for c in n.get_children():
			stack.push_back(c)
	return box


# ---------------------------------------------------------------- 环境

func _build_environment() -> void:
	var env := Environment.new()
	var grad: Dictionary = look.get("bg_gradient", {})
	if grad.is_empty():
		env.background_mode = Environment.BG_COLOR
		env.background_color = _color(look.bg)
	else:
		# 页面那边 canvas 是 alpha 透明的，舞台背景其实是 canvas 上的一层 CSS
		# 径向渐变。这里用 BG_CANVAS + 一张按 CSS 公式生成的贴图复现同一张底。
		env.background_mode = Environment.BG_CANVAS
		_build_bg_gradient(grad)

	var hemi: Dictionary = look.hemi
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load(HEMI_SKY_SHADER)
	sm.set_shader_parameter("sky_color", _color(hemi.sky))
	sm.set_shader_parameter("ground_color", _color(hemi.ground))
	sm.set_shader_parameter("radiance_scale", float(hemi.energy) / PI)
	# gl_compatibility（Web/WebGL2）的 sky 管线会把 COLOR 当作 sRGB 再解码成线性，
	# Forward+/mobile 则直接按线性用。按后端补一次编码，两边的半球环境光才一致。
	if String(RenderingServer.get_current_rendering_method()) == "gl_compatibility":
		sm.set_shader_parameter("srgb_output", true)
	sky.sky_material = sm

	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(look.ambient.energy)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED

	# three.js 这页没开 tone mapping / 泛光 / AO / 雾，这里保持同样的"直出"
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = float(look.tonemap.exposure)
	env.glow_enabled = false
	env.ssao_enabled = false
	env.fog_enabled = false
	env.adjustment_enabled = false

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


# ---------------------------------------------------------------- 背景渐变

var _bg_rect: TextureRect
var _bg_spec: Dictionary = {}
const BG_MAX_W := 2048


func _build_bg_gradient(grad: Dictionary) -> void:
	_bg_spec = grad
	_bg_rect = TextureRect.new()
	_bg_rect.name = "Background"
	_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_rect)
	_refresh_bg_texture()
	get_viewport().size_changed.connect(_refresh_bg_texture)


func _refresh_bg_texture() -> void:
	if _bg_rect == null or _bg_spec.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var w := clampi(int(vp.x), 8, BG_MAX_W)
	var h := maxi(8, int(round(float(w) * vp.y / maxf(1.0, vp.x))))
	_bg_rect.texture = ImageTexture.create_from_image(_gradient_image(w, h))


func _gradient_image(w: int, h: int) -> Image:
	## 按 CSS radial-gradient(120% 130% at 32% 18%, …) 的公式逐像素生成。
	## 注意 CSS 渐变在 sRGB 空间插值，Godot 的 2D 画布也是 sRGB，直接照抄即可。
	var c: Array = _bg_spec.center_pct
	var s: Array = _bg_spec.size_pct
	var cx := float(c[0]) * 0.01 * w
	var cy := float(c[1]) * 0.01 * h
	var rx := float(s[0]) * 0.01 * w
	var ry := float(s[1]) * 0.01 * h

	var stops: Array = _bg_spec.stops
	var lut := PackedByteArray()
	lut.resize(256 * 3)
	var li := 0
	for i in 256:
		var t := float(i) / 255.0
		var col := _stop_color(stops, t)
		lut[li] = clampi(int(round(col.r * 255.0)), 0, 255)
		lut[li + 1] = clampi(int(round(col.g * 255.0)), 0, 255)
		lut[li + 2] = clampi(int(round(col.b * 255.0)), 0, 255)
		li += 3

	var inv_rx := 1.0 / maxf(rx, 1e-6)
	var inv_ry := 1.0 / maxf(ry, 1e-6)
	var data := PackedByteArray()
	data.resize(w * h * 3)
	var p := 0
	for y in h:
		var dy := (float(y) - cy) * inv_ry
		var ty := dy * dy
		for x in w:
			var dx := (float(x) - cx) * inv_rx
			var t := sqrt(dx * dx + ty)
			var idx := clampi(int(t * 255.0), 0, 255) * 3
			data[p] = lut[idx]
			data[p + 1] = lut[idx + 1]
			data[p + 2] = lut[idx + 2]
			p += 3
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)


func _stop_color(stops: Array, t: float) -> Color:
	var prev_t := 0.0
	var prev := Color.WHITE
	for i in stops.size():
		var st: Array = stops[i]
		var at := float(st[0])
		var col := _color(st[1])
		if i == 0:
			prev_t = at
			prev = col
			if t <= at:
				return col
			continue
		if t <= at:
			var k := (t - prev_t) / maxf(at - prev_t, 1e-6)
			return prev.lerp(col, k)
		prev_t = at
		prev = col
	return prev


# ---------------------------------------------------------------- 光

func _build_lights() -> void:
	var key: Dictionary = look.key
	var sun := _dir_light("Sun", key.color, float(key.energy), key.dir, true)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = radius * float(key.shadow_distance_factor)
	sun.shadow_bias = float(key.bias)
	sun.shadow_normal_bias = float(key.normal_bias)
	sun.shadow_blur = float(key.blur)
	_set_prop(sun, ["light_size", "light_angular_distance"], float(key.angular))

	var rim: Dictionary = look.rim
	_dir_light("Rim", rim.color, float(rim.energy), rim.dir, false)


# ---------------------------------------------------------------- 地面

## 地形高度图：启动时把岛体网格的顶点栅格化成 0.5 m 网格，用来查「脚下地面」。
## 相机据此兜底（坡上、山体边缘不会钻进去），人物以后也能用它贴地。
var height_grid := PackedFloat32Array()
var height_origin := Vector2.ZERO
var height_step := 0.5
var height_n := 0


func _build_heightmap(world: Node3D) -> void:
	var tris: Array[Vector3] = []
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for n in world.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or String(mi.name).to_lower().contains("water"):
			continue
		var par := mi.get_parent()
		var is_terrain := false
		while par != null and par != world:
			if String(par.name).begins_with("campground-lake-terrain"):
				is_terrain = true
				break
			par = par.get_parent()
		if not is_terrain:
			continue
		var xf := mi.global_transform
		for f in mi.mesh.get_faces():
			var v := xf * f
			tris.append(v)
			lo = lo.min(v)
			hi = hi.max(v)
	if tris.is_empty():
		push_warning("没找到地形网格，高度图不可用")
		return

	var t0 := Time.get_ticks_msec()
	height_origin = Vector2(lo.x, lo.z)
	height_n = int(ceil(maxf(hi.x - lo.x, hi.z - lo.z) / height_step)) + 2
	height_grid = PackedFloat32Array()
	height_grid.resize(height_n * height_n)
	height_grid.fill(-INF)

	# 逐三角形栅格化：格子中心落在三角形内就按重心坐标求高度
	var filled := 0
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var x0 := int(floor((minf(a.x, minf(b.x, c.x)) - height_origin.x) / height_step))
		var x1 := int(ceil((maxf(a.x, maxf(b.x, c.x)) - height_origin.x) / height_step))
		var z0 := int(floor((minf(a.z, minf(b.z, c.z)) - height_origin.y) / height_step))
		var z1 := int(ceil((maxf(a.z, maxf(b.z, c.z)) - height_origin.y) / height_step))
		var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-9:
			continue
		for gz in range(maxi(0, z0), mini(height_n - 1, z1) + 1):
			var cz := height_origin.y + (float(gz) + 0.5) * height_step
			for gx in range(maxi(0, x0), mini(height_n - 1, x1) + 1):
				var cx := height_origin.x + (float(gx) + 0.5) * height_step
				var u := ((b.z - c.z) * (cx - c.x) + (c.x - b.x) * (cz - c.z)) / den
				var v := ((c.z - a.z) * (cx - c.x) + (a.x - c.x) * (cz - c.z)) / den
				if u < 0.0 or v < 0.0 or u + v > 1.0:
					continue
				var h := a.y + u * (b.y - a.y) + v * (c.y - a.y)
				var idx := gz * height_n + gx
				if h > height_grid[idx]:
					height_grid[idx] = h
					filled += 1

	var best := -INF
	var best_x := 0.0
	var best_z := 0.0
	for i in height_grid.size():
		if height_grid[i] > best:
			best = height_grid[i]
			best_x = height_origin.x + float(i % height_n) * height_step
			best_z = height_origin.y + float(i / height_n) * height_step
	print("GROUND heightmap %dx%d step=%.2f tris=%d 填充=%d 最高=%.1f m @(%.1f, %.1f) 耗时=%dms" % [
		height_n, height_n, height_step, tris.size() / 3, filled, best, best_x, best_z,
		Time.get_ticks_msec() - t0])


## 某个 XZ 处的地面高度；不在岛体上时返回 -INF。双线性采样，格内取 4 角有效值。
func _ground_at(x: float, z: float) -> float:
	if height_n <= 0:
		return -INF
	var fx := (x - height_origin.x) / height_step
	var fz := (z - height_origin.y) / height_step
	var gx := int(floor(fx))
	var gz := int(floor(fz))
	if gx < 0 or gz < 0 or gx + 1 >= height_n or gz + 1 >= height_n:
		return -INF
	var tx := fx - gx
	var tz := fz - gz
	var sum := 0.0
	var wsum := 0.0
	for dz in 2:
		for dx in 2:
			var h := height_grid[(gz + dz) * height_n + (gx + dx)]
			if h == -INF:
				continue
			var w := (tx if dx == 0 else 1.0 - tx) * (tz if dz == 0 else 1.0 - tz)
			sum += h * w
			wsum += w
	if wsum < 0.2:
		return -INF
	return sum / wsum


# ---------------------------------------------------------------- 接触阴影

func _build_contact_shadow() -> void:
	## 页面在模型最低点铺了一张 ShadowMaterial(opacity .18) 圆盘来接主光阴影
	## （viewer.js: ground = CircleGeometry(r*11), y = box.min.y - 0.001）。
	## Godot 没有 shadow-only 材质，这里用一盏同样的平行光在一个独立 SubViewport 里
	## 把"亮/暗"烘成一张正交贴图：白 = 见光，黑 = 投影或被模型盖住。
	if world_root == null:
		return
	var old := get_node_or_null("ContactShadow")
	if old != null:
		old.queue_free()
	var cfg: Dictionary = look.get("contact_shadow", {})
	if not bool(cfg.get("enabled", true)):
		return
	var res := int(cfg.get("resolution", 1024))
	var span := radius * float(cfg.get("span_factor", 1.6))
	var light_dir: Vector3 = _vec(look.key.dir).normalized()

	var vp := SubViewport.new()
	vp.name = "ShadowBake"
	vp.size = Vector2i(res, res)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)

	# 世界：黑底 + 只留平行光，避免环境光把阴影冲淡
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	vp.add_child(sun)
	sun.light_color = Color.WHITE
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = radius * 2.5
	sun.shadow_bias = float(look.key.bias)
	sun.shadow_normal_bias = float(look.key.normal_bias)
	sun.global_position = center + light_dir * radius * 2.0
	sun.look_at(center, Vector3.UP)

	# 烘阴影用"当前世界的复制品"（地图改了阴影跟着变）
	var kit: Node = world_root.duplicate()
	vp.add_child(kit)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	for n in kit.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = black

	# 接影盘：白色（见光 = 白），正好铺满正交视野
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(span * 4.0, span * 4.0)
	plane.mesh = pm
	var white := StandardMaterial3D.new()
	white.albedo_color = Color.WHITE
	white.roughness = 1.0
	white.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	white.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	plane.material_override = white
	plane.position = Vector3(center.x, bounds.position.y - 0.001, center.z)
	vp.add_child(plane)

	var c := Camera3D.new()
	c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.size = span * 2.0
	c.keep_aspect = Camera3D.KEEP_HEIGHT
	c.near = 0.5
	c.far = radius * 8.0
	vp.add_child(c)
	c.global_position = center + light_dir * radius * 3.0
	c.look_at(center, Vector3.UP)
	c.make_current()

	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	# 见光处不是纯白（白盘 * 光强 * dotNL），取四角近似值当归一化基准
	var lit_max := 0.0
	for corner in [Vector2i(2, 2), Vector2i(res - 3, 2), Vector2i(2, res - 3), Vector2i(res - 3, res - 3)]:
		lit_max = maxf(lit_max, img.get_pixel(corner.x, corner.y).r)
	lit_max = maxf(lit_max, 1e-3)
	if "--dump-shadow" in OS.get_cmdline_user_args() or not _arg_value("--dump-shadow").is_empty():
		var dump := _arg_value("--dump-shadow")
		if dump.is_empty():
			dump = "user://shadow_mask.png"
		img.save_png(dump)
	var tex := ImageTexture.create_from_image(img)

	# 地面接影盘（页面半径 r*11 的超大圆盘，这里用方块，正交贴图只在范围内生效）
	var ground := MeshInstance3D.new()
	ground.name = "ContactShadow"
	var gm := PlaneMesh.new()
	gm.size = Vector2(radius * 22.0, radius * 22.0)
	ground.mesh = gm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground_shadow.gdshader")
	mat.set_shader_parameter("mask_tex", tex)
	mat.set_shader_parameter("light_inv", c.global_transform.affine_inverse())
	mat.set_shader_parameter("half_extent", span)
	mat.set_shader_parameter("lit_max", lit_max)
	mat.set_shader_parameter("opacity", float(cfg.get("opacity", 0.18)))
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position = Vector3(center.x, bounds.position.y - 0.001, center.z)
	add_child(ground)

	vp.free()
	print("SHADOW bake %dx%d span=%.2f" % [res, res, span])


func _dir_light(node_name: String, color_hex: Variant, energy: float, dir: Variant, shadows: bool) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = node_name
	l.light_color = _color(color_hex)
	l.light_energy = energy
	l.shadow_enabled = shadows
	add_child(l)
	var d := Vector3(float(dir[0]), float(dir[1]), float(dir[2]))
	l.global_position = center + d.normalized() * radius
	l.look_at(center, Vector3.UP)
	return l


func _set_prop(obj: Object, names: Array, value: Variant) -> void:
	for n in names:
		if n in obj:
			obj.set(n, value)
			return


func _vec(v: Variant) -> Vector3:
	if v is Array:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return v as Vector3


# ---------------------------------------------------------------- 相机

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = float(look.cam.fov)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = maxf(0.01, radius * 0.012)
	cam.far = maxf(200.0, radius * 30.0)
	add_child(cam)


func _frame_camera() -> void:
	var fov := float(look.cam.fov)
	distance = radius / sin(deg_to_rad(fov * 0.5)) * float(look.cam.fit)
	# 取景距离保持页面默认；可缩放的上下限用绝对米数，默认给到能贴脸看细节
	var cam_cfg: Dictionary = look.cam
	min_distance = float(cam_cfg.get("min_distance", distance * float(cam_cfg.get("min_factor", 0.35))))
	max_distance = float(cam_cfg.get("max_distance", distance * float(cam_cfg.get("max_factor", 2.5))))
	base_distance = distance
	yaw = float(cam_cfg.yaw)
	pitch = deg_to_rad(float(cam_cfg.pitch_deg))
	var forced := _arg_value("--cam-dist")
	if forced != "":
		distance = clampf(float(forced), min_distance, max_distance)
	var forced_pitch := _arg_value("--cam-pitch")
	if forced_pitch != "":
		pitch = deg_to_rad(float(forced_pitch))
	# 取证用：把取景中心挪到某个世界点（"x,y,z"），方便贴脸看人物
	var focus := _arg_value("--focus")
	if focus != "":
		var v := focus.split(",")
		if v.size() == 3:
			center = Vector3(float(v[0]), float(v[1]), float(v[2]))
	_apply_camera()


## 相机高度不能低于「地面 + 余量」，据此反推最小俯角（随距离自适应）。
## 远看几乎能平视，贴近时下限自动抬高，所以拖动永远不会出现在地面以下、看得见岛底。
func _min_pitch() -> float:
	var cfg: Dictionary = look.cam
	var floor_y := float(cfg.get("floor_y", 0.0))
	var margin := float(cfg.get("floor_margin", 1.5))
	# 相机不得低于地面；但盯的是本身就在地面以下的东西（码头、水面）时，
	# 允许跟着目标降到它上方 0.8 m —— 否则贴地看低处会被顶成俯视。
	var cam_floor := minf(floor_y + margin, center.y + 0.8)
	var num := cam_floor - center.y
	var from_height := asin(clampf(num / maxf(distance, 0.001), -0.999, 0.999))
	# 再加一条硬下限：永远保持一点俯角，不给"贴地平视看见岛底"留口子
	var hard := deg_to_rad(float(cfg.get("min_pitch_deg", 8.0)))
	return maxf(from_height, hard)


func _apply_camera() -> void:
	if cam == null:
		return
	pitch = maxf(pitch, _min_pitch())
	var off := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)) * distance
	var pos := center + off
	# 关键：按相机脚下的真实地面高度兜底（坡上/山体边缘也不会钻进去）
	var margin := float(look.cam.get("floor_margin", 1.5))
	var local_floor := maxf(float(look.cam.get("floor_y", 0.0)), _ground_at(pos.x, pos.z))
	if pos.y < local_floor + margin:
		pos.y = local_floor + margin
	cam.global_position = pos
	cam.look_at(center, Vector3.UP)
	# near 跟着距离走：默认取景距离处仍是页面的 radius*0.012（保证默认视角逐像素一致），
	# 拉近时按比例收小，贴到 0.6 m 看细节也不裁切。
	var near_want := clampf(radius * 0.012 * distance / maxf(base_distance, 0.001), 0.02, radius * 0.012)
	if not is_equal_approx(cam.near, near_want):
		cam.near = near_want
		cam.far = maxf(200.0, radius * 30.0)


# ---------------------------------------------------------------- 交互（等价 OrbitControls）

var _perf_t := 0.0
var _perf_frames := 0


func _process(delta: float) -> void:
	if OS.is_debug_build():
		_perf_t += delta
		_perf_frames += 1
		if _perf_t >= 3.0:
			var args := OS.get_cmdline_user_args()
			var tag := "phone"
			for a in args:
				if String(a).begins_with("--perf-tag="):
					tag = String(a).substr(11)
			var calls := RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			var objs := RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
			var vmem := RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
			print("PERF %s fps=%.1f avg=%.2fms draws=%d objs=%d vmem=%.1fMB vp=%s" % [
				tag, float(_perf_frames) / _perf_t, 1000.0 * _perf_t / float(maxi(_perf_frames, 1)),
				calls, objs, float(vmem) / 1048576.0,
				str(get_viewport().get_visible_rect().size)])
			_perf_t = 0.0
			_perf_frames = 0

	var moved := false
	if absf(_yaw_vel) > 1e-6 or absf(_pitch_vel) > 1e-6:
		yaw += _yaw_vel * DAMPING
		pitch = clampf(pitch + _pitch_vel * DAMPING, _min_pitch(), PI * 0.5 - 0.001)
		_yaw_vel *= RECOVER
		_pitch_vel *= RECOVER
		moved = true
	if absf(_zoom_vel) > 1e-6:
		var k := pow(_zoom_factor, _zoom_vel * DAMPING)
		if _zoom_pivot_valid:
			center = center.lerp(_zoom_pivot, 1.0 - k)
		distance = clampf(distance * k, min_distance, max_distance)
		_zoom_vel *= RECOVER
		moved = true
	if moved:
		_apply_camera()


## 滚轮缩放：步进按当前距离成比例，并把取景中心往「光标下面的那个点」挪，
## 这样贴着看帐篷、码头时，能一直放大到想看的那一件，而不是只会往场景中心钻。
func _wheel_zoom(screen_pos: Vector2, step: float) -> void:
	if Input.is_key_pressed(KEY_CTRL):
		_zoom_factor = 0.60          # 快速拉远/拉近
	elif Input.is_key_pressed(KEY_SHIFT):
		_zoom_factor = 0.97          # 微调
	else:
		_zoom_factor = 0.85
	if step > 0.0:
		var pivot: Variant = _point_under_cursor(screen_pos)
		if pivot != null:
			_zoom_pivot = pivot as Vector3
			_zoom_pivot_valid = true
	_zoom_vel += step * ZOOM_SPEED


func _touch_span() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _touch_mid() -> Vector2:
	var pts: Array = _touches.values()
	if pts.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in pts:
		sum += p as Vector2
	return sum / float(pts.size())


func _touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		_touches[ev.index] = ev.position
		if _touches.size() == 2:
			_pinch_prev = _touch_span()
			_pinch_mid = _touch_mid()
			_yaw_vel = 0.0
			_pitch_vel = 0.0
	else:
		_touches.erase(ev.index)
		if _touches.size() < 2:
			_pinch_prev = 0.0


func _touch_drag(ev: InputEventScreenDrag) -> void:
	_touches[ev.index] = ev.position
	if _touches.size() == 1:
		# 单指拖动 = 环绕（与桌面左键拖动同一套阻尼）
		var h := maxf(1.0, float(get_viewport().get_visible_rect().size.y))
		_yaw_vel -= TAU * ev.relative.x / h * ROTATE_SPEED
		_pitch_vel += TAU * ev.relative.y / h * ROTATE_SPEED
		return
	if _touches.size() < 2:
		return
	# 双指：捏合缩放 + 一起平移
	var d := _touch_span()
	var mid := _touch_mid()
	if _pinch_prev > 1.0 and d > 1.0:
		var k := clampf(_pinch_prev / d, 0.5, 2.0)   # 两指张开(d 变大) = 拉近
		_pinch_zoom(k, mid)
	var dm := mid - _pinch_mid
	if dm.length() > 0.5:
		var scale := distance * 0.0016
		center -= cam.global_transform.basis.x * dm.x * scale
		center -= cam.global_transform.basis.y * dm.y * scale
		_apply_camera()
	_pinch_prev = d
	_pinch_mid = mid


## 以屏幕点为中心做一次缩放（k<1 拉近，k>1 推远），手机捏合直接用像素比。
func _pinch_zoom(k: float, screen_pos: Vector2) -> void:
	var pivot: Variant = _point_under_cursor(screen_pos)
	if pivot != null:
		center = center.lerp(pivot as Vector3, clampf(1.0 - k, 0.0, 0.6))
	distance = clampf(distance * k, min_distance, max_distance)
	_apply_camera()


func _point_under_cursor(screen_pos: Vector2) -> Variant:
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	# 与「过取景中心、垂直视线」的平面求交
	var n := (center - cam.global_position).normalized()
	var denom := dir.dot(n)
	if absf(denom) < 1e-5:
		return null
	var t := (center - from).dot(n) / denom
	if t <= 0.0:
		return null
	return from + dir * t


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_touch_drag(event as InputEventScreenDrag)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_last_mouse = mb.position
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# 滚轮向上 = 放大（按页面的方向约定），步进比页面更狠，才够一路贴到地面
			var step := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			_wheel_zoom(mb.position, step)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var h := maxf(1.0, float(get_viewport().get_visible_rect().size.y))
		# OrbitControls：rotateLeft(2PI * dx / height)
		_yaw_vel -= TAU * mm.relative.x / h * ROTATE_SPEED
		_pitch_vel += TAU * mm.relative.y / h * ROTATE_SPEED
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_LEFT:
				_yaw_vel += 0.25
			KEY_RIGHT:
				_yaw_vel -= 0.25
			KEY_UP:
				_pitch_vel += 0.15
			KEY_DOWN:
				_pitch_vel -= 0.15
			KEY_EQUAL, KEY_KP_ADD:
				_zoom_vel -= 1.0
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom_vel += 1.0
			KEY_R:
				_frame_camera()


## 自检：把"拖动 / 滚轮"这两个交互灌成本地事件，跑几十帧后核对相机是否按
## OrbitControls 的规则动了（方向、灵敏度、限位）。跑 shot 之前用它验交互。
func _selftest() -> void:
	var h := maxf(1.0, float(get_viewport().get_visible_rect().size.y))
	var y0 := yaw
	var p0 := pitch
	var d0 := distance

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	_unhandled_input(down)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(h * 0.1, 0.0)
	_unhandled_input(move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	_unhandled_input(up)
	for i in 80:
		await get_tree().process_frame
	var dyaw := yaw - y0
	# OrbitControls: dx=+0.1h → rotateLeft(2PI*0.1) ≈ 0.628 rad，方向为 yaw 减小
	var yaw_ok := dyaw < -0.5 and dyaw > -0.75

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_unhandled_input(wheel)
	for i in 80:
		await get_tree().process_frame
	var zoom_ok := distance < d0 and distance > min_distance * 0.999

	print("SELFTEST yaw %.4f→%.4f (Δ%.4f, 期望≈-0.628) pitch %.2f°→%.2f°" % [
		y0, yaw, dyaw, rad_to_deg(p0), rad_to_deg(pitch)])
	print("SELFTEST dist %.3f→%.3f (min %.3f max %.3f)" % [d0, distance, min_distance, max_distance])
	print("SELFTEST yaw_ok=%s zoom_in_ok=%s" % [str(yaw_ok), str(zoom_ok)])
	if not _has_shot():
		get_tree().quit()


# ---------------------------------------------------------------- 工具

func _arg_value(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix + "="):
			return a.substr(prefix.length() + 1)
	return ""

func _color(v: Variant) -> Color:
	## Godot 的 Color 属性（light_color / background_color / albedo_color / 材质颜色）
	## 都是 sRGB，上传时由引擎转线性（实测：gray 0.5 → 线性 0.212）。
	## three.js 也是把 #rrggbb 当 sRGB 再转线性，所以这里直接原样给，不要再手动转。
	if v is String:
		return Color(v)
	if v is Array:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return v as Color


func _load_look() -> Dictionary:
	var path := LOOK_PATH
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			path = a.substr(7)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("读不到 %s，用默认值" % path)
		return _default_look()
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return _default_look()


func _default_look() -> Dictionary:
	return {
		"cam": {"fov": 38.0, "fit": 0.525, "pitch_deg": 17.8, "yaw": 0.61, "min_factor": 0.35, "max_factor": 2.5},
		"bg": "#eaf1fe",
		"hemi": {"sky": "#ffffff", "ground": "#b8b0a4", "energy": 1.15},
		"key": {"color": "#fff2e0", "energy": 0.7639437, "dir": [4.0, 7.0, 5.0], "angular": 0.35, "bias": 0.02, "normal_bias": 1.0, "blur": 1.0, "shadow_distance_factor": 2.2},
		"rim": {"color": "#dfe8ff", "energy": 0.286479, "dir": [-5.0, 4.0, -6.0]},
		"ambient": {"energy": 1.0},
		"tonemap": {"exposure": 1.0},
	}


func _print_stats() -> void:
	var meshes := 0
	var tris := 0
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		meshes += 1
		tris += mi.mesh.get_faces().size() / 3
	print("KIT meshes=%d tris=%d bounds_size=%s center=%s radius=%.3f" % [
		meshes, tris, str(bounds.size), str(center), radius])
	print("CAM fov=%.1f d=%.3f pitch=%.1f° yaw=%.3f" % [
		cam.fov, distance, rad_to_deg(pitch), yaw])
	print("VIEWPORT %s" % str(get_viewport().get_visible_rect().size))


## 合成触摸事件跑一遍：单指拖动应改变 yaw，双指捏合应改变 distance。
func _touchtest() -> void:
	var y0 := yaw
	var d0 := distance
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = Vector2(500, 300)
	down.pressed = true
	_touch(down)
	var move := InputEventScreenDrag.new()
	move.index = 0
	move.position = Vector2(700, 300)
	move.relative = Vector2(200, 0)
	_touch_drag(move)
	for i in 60:
		await get_tree().process_frame
	var dyaw := yaw - y0

	# 先松开单指，再双指捏合（张开 = 放大）
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = Vector2(700, 300)
	up.pressed = false
	_touch(up)
	var t0 := InputEventScreenTouch.new()
	t0.index = 1
	t0.position = Vector2(400, 300)
	t0.pressed = true
	_touch(t0)
	var t1 := InputEventScreenTouch.new()
	t1.index = 2
	t1.position = Vector2(600, 300)
	t1.pressed = true
	_touch(t1)
	var d1 := InputEventScreenDrag.new()
	d1.index = 1
	d1.position = Vector2(300, 300)
	_touch_drag(d1)
	var d2 := InputEventScreenDrag.new()
	d2.index = 2
	d2.position = Vector2(700, 300)
	_touch_drag(d2)
	var pinch_ok := distance < d0 * 0.95
	var yaw_ok := dyaw < -0.3

	print("TOUCHTEST 单指拖 yaw Δ=%.3f（应显著为负）  捏合 distance %.2f→%.2f" % [dyaw, d0, distance])
	print("TOUCHTEST %s" % ("PASS" if yaw_ok and pinch_ok else "FAIL"))
	get_tree().quit()


# ---------------------------------------------------------------- 出静帧

## 一路滚到底/推到头，核对能贴到 min_distance、也能拉到 max_distance。
## 六个方位各自往下狂拖，核对相机始终在「脚下地面 + 余量」之上。
func _orbitest() -> void:
	var floor_y := float(look.cam.get("floor_y", 0.0))
	var margin := float(look.cam.get("floor_margin", 1.5))
	print("ORBITEST ground probe: center=%s  island_mid=%s  off=%s" % [
		str(_ground_at(center.x, center.z)), str(_ground_at(-2.0, -2.0)),
		str(_ground_at(200.0, 200.0))])
	var worst := INF
	var worst_yaw := 0.0
	for k in 6:
		yaw = TAU * float(k) / 6.0
		for i in 10:
			_pitch_vel -= 6.0
			for j in 12:
				await get_tree().process_frame
		var p := cam.global_position
		var need := maxf(floor_y, _ground_at(p.x, p.z)) + margin
		if p.y - need < worst:
			worst = p.y - need
			worst_yaw = yaw
		print("ORBITEST yaw=%.0f° pitch=%.2f° cam_y=%.2f 脚下地面=%.2f 余量=%+.2f" % [
			rad_to_deg(yaw), rad_to_deg(pitch), p.y,
			maxf(floor_y, _ground_at(p.x, p.z)), p.y - need])
	print("ORBITEST worst clearance=%+.3f m @yaw=%.0f°" % [worst, rad_to_deg(worst_yaw)])
	print("ORBITEST %s" % ("PASS" if worst >= -0.05 else "FAIL"))
	get_tree().quit()


func _zoomtest() -> void:
	print("ZOOMTEST start d=%.3f min=%.3f max=%.3f" % [distance, min_distance, max_distance])
	for i in 400:
		_zoom_vel += 1.0
	for i in 400:
		await get_tree().process_frame
	var near_d := distance
	# 朝右下角放大：中心应当朝那个方向挪
	var c0 := center
	_wheel_zoom(Vector2(1000, 800), 1.0)
	for i in 200:
		await get_tree().process_frame
	var moved_px := absf(center.x - c0.x) + absf(center.z - c0.z)
	print("ZOOMTEST cursor-zoom center moved=%.3f m" % moved_px)
	for i in 800:
		_zoom_vel -= 1.0
	for i in 400:
		await get_tree().process_frame
	print("ZOOMTEST in->%.3f (min %.3f)  out->%.3f (max %.3f)" % [
		near_d, min_distance, distance, max_distance])
	print("ZOOMTEST %s" % ("PASS" if is_equal_approx(near_d, min_distance)
			and is_equal_approx(distance, max_distance) and moved_px > 0.01 else "FAIL"))
	get_tree().quit()


func _bench() -> void:
	## 关掉 vsync 跑一段，报平均帧时与 draw call（本机参考值，不做指标）
	for i in 30:
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var frames := 120
	for i in frames:
		await get_tree().process_frame
	var ms := float(Time.get_ticks_msec() - t0)
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("BENCH viewport=%s frames=%d total=%.0fms avg=%.2fms fps=%.1f draw_calls=%d" % [
		str(get_viewport().get_visible_rect().size), frames, ms, ms / frames, 1000.0 * frames / ms, calls])
	get_tree().quit()

func _has_shot() -> bool:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--shot")
	return idx >= 0 and idx + 1 < args.size()


func _maybe_shot() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--shot")
	if idx < 0 or idx + 1 >= args.size():
		return
	var path := args[idx + 1]	# 等几何/材质/shader 都编译完再取帧
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("SHOT %s %dx%d err=%d" % [path, img.get_width(), img.get_height(), err])
	get_tree().quit()
