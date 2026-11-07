extends "res://scripts/main.gd"
## 地图编辑器（最小可用版）：拖动摆放 part、旋转缩放、增删复制、存成 map.json。
##
## 用法：
##   pwsh v6/tools/edit.ps1                      # 打开默认地图
##   pwsh v6/tools/edit.ps1 -Map my_map.json     # 打开/新建另一张图
##
## 操作：
##   左键拖空白     环绕   右键拖      平移   滚轮        缩放
##   左键点物体     选中   左键拖选中  在地面移动（4 m 吸附）
##   Shift+左键拖   上下移动（0.25 m 吸附）
##   Q / E          旋转 ±15°        [ / ]   旋转 ±1°
##   - / =          缩小 / 放大 ±10%
##   Del            删除选中          Ctrl+D  复制选中
##   Ctrl+Z         撤销              Ctrl+S  保存
##   点左侧 part 列表 → 刷子；再点地面 = 放一个
##   G 网格吸附开关   F 取景选中      Esc 取消选中/清刷子
##
## 存盘走 MapWorld.save_map，路径就是打开时那张图（默认 res://data/maps/campground_edit.json）。

const PARTS_JSON := "res://assets/parts/parts.json"
const DEFAULT_MAP := "res://data/maps/campground_edit.json"
const BASE_MAP := "res://data/maps/campground.json"

var map_path := DEFAULT_MAP
var map_data: Dictionary = {}
var items: Array = []
var nodes: Array[Node3D] = []

var part_cache := {}
var part_aabb := {}
var manifest := {}

var selected := -1
var brush := ""
var brush_variant := ""
var snapping := true
var dirty := false
var undo_stack: Array = []

var _drag_mode := ""          # "" / "move" / "move_y" / "orbit" / "pan"
var _drag_offset := Vector3.ZERO
var _mouse_down_pos := Vector2.ZERO

var hud: CanvasLayer
var info: Label
var list_box: VBoxContainer
var variant_box: HBoxContainer
var status: Label
var grid_root: Node3D


func _ready() -> void:
	edit_mode = true
	await super._ready()
	map_path = _resolve_map_path()
	var data := MapWorld.load_map(map_path)
	if data.is_empty():
		# 第一次编辑：拿默认地图当起点，另存成可编辑副本
		data = MapWorld.load_map(BASE_MAP)
		map_path = DEFAULT_MAP if _arg_value("--map") == "" else map_path
		dirty = true
	await _rebuild(data)
	_build_hud()
	_build_grid()
	_update_info()
	print("EDIT map=%s items=%d" % [map_path, items.size()])
	if "--edit-selftest" in OS.get_cmdline_user_args():
		await _edit_selftest()
	if "--shot" in OS.get_cmdline_user_args():
		_maybe_shot()


func _resolve_map_path() -> String:
	var p := _arg_value("--map")
	if p == "":
		return DEFAULT_MAP
	if p.begins_with("res://") or p.begins_with("user://"):
		return p
	return "res://data/maps/%s" % p


# ---------------------------------------------------------------- 世界重建

func _rebuild(data: Dictionary) -> void:
	if world_root != null:
		world_root.queue_free()
		await get_tree().process_frame
	map_data = data
	items = map_data.get("items", [])
	nodes.clear()
	var map := Node3D.new()
	map.name = "Map"
	for it in items:
		var part := String(it.get("part", ""))
		var inst := _instantiate_part(part)
		if inst == null:
			continue
		inst.transform = MapWorld.item_transform(it) * inst.transform
		map.add_child(inst)
		nodes.append(inst)
	world_root = map
	add_child(map)
	_enable_vertex_colors(map)
	_dedupe_materials(map)
	_build_heightmap(map)
	bounds = _world_bounds(map)
	center = bounds.get_center()
	radius = maxf(bounds.size.length() * 0.5, 1.0)
	selected = -1


func _instantiate_part(part: String) -> Node3D:
	if not part_cache.has(part):
		var p := MapWorld.part_path(part)
		part_cache[part] = load(p) if ResourceLoader.exists(p) else null
	if part_cache[part] == null:
		push_warning("缺 part：%s" % part)
		return null
	var inst: Node3D = (part_cache[part] as PackedScene).instantiate()
	return inst


func _part_aabb(part: String) -> AABB:
	if part_aabb.has(part):
		return part_aabb[part]
	var inst := _instantiate_part(part)
	if inst == null:
		return AABB()
	var box := AABB()
	var first := true
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	inst.free()
	part_aabb[part] = box
	return box


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if not edit_mode:
		return super._unhandled_input(event)
	if event is InputEventMouseButton:
		_editor_mouse_button(event)
	elif event is InputEventMouseMotion:
		_editor_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_editor_key(event)


func _editor_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var step := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		_wheel_zoom(mb.position, step)
		return
	if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_drag_mode = "pan"
		_mouse_down_pos = mb.position
		return
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var hit := _pick(mb.position)
		if brush != "" and hit < 0:
			_place_at(mb.position)
			return
		if hit >= 0:
			_select(hit)
			var ground = _ground_point(mb.position)
			if ground != null:
				_drag_mode = "move_y" if Input.is_key_pressed(KEY_SHIFT) else "move"
				_drag_offset = (ground as Vector3) - nodes[hit].global_position
			return
		_select(-1)
		_drag_mode = "orbit"
		_mouse_down_pos = mb.position
		return
	if not mb.pressed:
		_drag_mode = ""


func _editor_mouse_motion(mm: InputEventMouseMotion) -> void:
	match _drag_mode:
		"orbit":
			var h := maxf(1.0, float(get_viewport().get_visible_rect().size.y))
			_yaw_vel -= TAU * mm.relative.x / h * ROTATE_SPEED
			_pitch_vel += TAU * mm.relative.y / h * ROTATE_SPEED
		"pan":
			var k := distance * 0.0016
			center -= cam.global_transform.basis.x * mm.relative.x * k
			center -= cam.global_transform.basis.y * mm.relative.y * k
			_apply_camera()
		"move", "move_y":
			if selected < 0:
				return
			if _drag_mode == "move":
				var g = _ground_point(mm.position)
				if g != null:
					var p: Vector3 = (g as Vector3) - _drag_offset
					p.y = nodes[selected].global_position.y
					nodes[selected].global_position = _snap(p)
			else:
				var p2: Vector3 = nodes[selected].global_position
				p2.y -= mm.relative.y * 0.05
				p2.y = snappedf(p2.y, 0.25)
				nodes[selected].global_position = p2
			_commit_transform(selected)


func _editor_key(k: InputEventKey) -> void:
	var ctrl := k.ctrl_pressed
	match k.keycode:
		KEY_Q:
			_rotate_selected(-15.0)
		KEY_E:
			_rotate_selected(15.0)
		KEY_BRACKETLEFT:
			_rotate_selected(-1.0)
		KEY_BRACKETRIGHT:
			_rotate_selected(1.0)
		KEY_MINUS:
			_scale_selected(0.9)
		KEY_EQUAL:
			_scale_selected(1.1)
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selected()
		KEY_D:
			if ctrl:
				_duplicate_selected()
		KEY_Z:
			if ctrl:
				_undo()
		KEY_S:
			if ctrl:
				_save()
		KEY_G:
			snapping = not snapping
			_update_info()
		KEY_F5:
			await _build_contact_shadow()
			status.text = "接触阴影已重烘"
			_update_info()
		KEY_F:
			_frame_selected()
		KEY_ESCAPE:
			brush = ""
			brush_variant = ""
			_select(-1)
			_refresh_variants()


# ---------------------------------------------------------------- 编辑动作

func _snap(p: Vector3) -> Vector3:
	if not snapping:
		return p
	var g := float(map_data.get("grid", 4.0))
	return Vector3(snappedf(p.x, g), p.y, snappedf(p.z, g))


func _ground_point(screen_pos: Vector2) -> Variant:
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-5:
		return null
	var t := (0.0 - from.y) / dir.y
	if t < 0:
		return null
	return from + dir * t


func _pick(screen_pos: Vector2) -> int:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var best := -1
	var best_t := INF
	for i in nodes.size():
		var it: Dictionary = items[i]
		var box := _part_aabb(String(it.get("part", "")))
		var world: AABB = nodes[i].global_transform * box
		var t := _ray_box(from, dir, world)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = i
	return best


func _ray_box(o: Vector3, d: Vector3, b: AABB) -> float:
	var tmin := -INF
	var tmax := INF
	for a in 3:
		var oa := o[a]
		var da := d[a]
		var lo := b.position[a]
		var hi := b.position[a] + b.size[a]
		if absf(da) < 1e-9:
			if oa < lo or oa > hi:
				return -1.0
			continue
		var t1 := (lo - oa) / da
		var t2 := (hi - oa) / da
		if t1 > t2:
			var tt := t1
			t1 = t2
			t2 = tt
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	if tmax < 0.0:
		return -1.0
	return maxf(tmin, 0.0)


func _select(i: int) -> void:
	selected = i
	_update_info()


func _snapshot() -> void:
	undo_stack.append(JSON.stringify(map_data))
	if undo_stack.size() > 60:
		undo_stack.pop_front()
	dirty = true


func _undo() -> void:
	if undo_stack.is_empty():
		return
	var txt: String = undo_stack.pop_back()
	var data: Variant = JSON.parse_string(txt)
	if data is Dictionary:
		await _rebuild(data)
		_update_info()


func _commit_transform(i: int) -> void:
	var part := String(items[i].get("part", ""))
	items[i] = MapWorld.item_from_transform(part, nodes[i].global_transform)
	_update_info()


func _rotate_selected(deg: float) -> void:
	if selected < 0:
		return
	_snapshot()
	var n: Node3D = nodes[selected]
	var p := n.global_position
	var yaw := deg_to_rad(deg)
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw) * n.global_transform.basis, p)
	_commit_transform(selected)


func _scale_selected(k: float) -> void:
	if selected < 0:
		return
	_snapshot()
	var n: Node3D = nodes[selected]
	var s: Vector3 = n.global_transform.basis.get_scale() * k
	n.global_transform = Transform3D(
			n.global_transform.basis.orthonormalized() * Basis.from_scale(s),
			n.global_position)
	_commit_transform(selected)


func _delete_selected() -> void:
	if selected < 0:
		return
	_snapshot()
	nodes[selected].queue_free()
	nodes.remove_at(selected)
	items.remove_at(selected)
	selected = -1
	_update_info()


func _duplicate_selected() -> void:
	if selected < 0:
		return
	_snapshot()
	var it: Dictionary = items[selected]
	var part := String(it.get("part", ""))
	var inst := _instantiate_part(part)
	if inst == null:
		return
	var xf: Transform3D = nodes[selected].global_transform
	xf.origin += Vector3(float(map_data.get("grid", 4.0)), 0, 0)
	inst.transform = xf * inst.transform
	world_root.add_child(inst)
	nodes.append(inst)
	items.append(MapWorld.item_from_transform(part, xf))
	selected = nodes.size() - 1
	_update_info()


func _place_at(screen_pos: Vector2) -> void:
	var g = _ground_point(screen_pos)
	if g == null:
		return
	_snapshot()
	var p := _snap(g as Vector3)
	var inst := _instantiate_part(brush)
	if inst == null:
		return
	inst.transform = Transform3D(Basis(), p) * inst.transform
	world_root.add_child(inst)
	nodes.append(inst)
	items.append(MapWorld.item_from_transform(brush, inst.transform))
	selected = nodes.size() - 1
	_update_info()


func _frame_selected() -> void:
	if selected < 0:
		return
	var box: AABB = nodes[selected].global_transform * _part_aabb(String(items[selected].get("part", "")))
	center = box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.5)
	distance = clampf(r / sin(deg_to_rad(cam.fov * 0.5)) * 2.2, min_distance, max_distance)
	_apply_camera()
	_update_info()


func _save() -> void:
	map_data["items"] = items
	map_data["version"] = 1
	map_data["grid"] = float(map_data.get("grid", 4.0))
	var err := MapWorld.save_map(map_path, map_data)
	dirty = err != OK
	status.text = ("已保存 %s (%d 条)" % [map_path, items.size()]) if err == OK else ("保存失败 %s" % map_path)


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	var help := PanelContainer.new()
	help.position = Vector2(12, 12)
	help.custom_minimum_size = Vector2(560, 0)
	hud.add_child(help)
	var vb := VBoxContainer.new()
	help.add_child(vb)
	var title := Label.new()
	title.text = "地图编辑器 · %s" % map_path.get_file()
	vb.add_child(title)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	vb.add_child(info)

	var var_panel := PanelContainer.new()
	var_panel.position = Vector2(12, 132)
	var_panel.custom_minimum_size = Vector2(560, 0)
	hud.add_child(var_panel)
	variant_box = HBoxContainer.new()
	var_panel.add_child(variant_box)

	var list_panel := PanelContainer.new()
	list_panel.position = Vector2(12, 186)
	list_panel.custom_minimum_size = Vector2(240, 640)
	hud.add_child(list_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(228, 620)
	list_panel.add_child(scroll)
	list_box = VBoxContainer.new()
	scroll.add_child(list_box)
	_populate_parts()

	var status_panel := PanelContainer.new()
	status_panel.position = Vector2(12, 866)
	hud.add_child(status_panel)
	status = Label.new()
	status.text = "Ctrl+S 保存 · Ctrl+Z 撤销 · G 吸附开关 · F5 重烘阴影 · Esc 取消"
	status_panel.add_child(status)


func _populate_parts() -> void:
	if not FileAccess.file_exists(PARTS_JSON):
		return
	manifest = JSON.parse_string(FileAccess.get_file_as_string(PARTS_JSON)).get("parts", {})
	var by_base := {}
	for name in manifest.keys():
		var base := String(manifest[name].get("base", name))
		by_base.get_or_add(base, []).append(name)
	for base in by_base.keys():
		var names: Array = by_base[base]
		names.sort()
		var b := Button.new()
		b.text = "%s (%d)" % [base, names.size()]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_choose_base.bind(base, names))
		list_box.add_child(b)


func _choose_base(base: String, names: Array) -> void:
	brush = String(names[0])
	brush_variant = brush
	status.text = "刷子：%s（点地面放置，Esc 取消）" % base
	_refresh_variants(base, names)


func _refresh_variants(base: String = "", names: Array = []) -> void:
	for c in variant_box.get_children():
		c.queue_free()
	if base == "" or names.is_empty():
		return
	var lbl := Label.new()
	lbl.text = "%s：变体" % base
	variant_box.add_child(lbl)
	for nm in names:
		var b := Button.new()
		b.text = "v1" if nm == base else String(nm).substr(base.length() + 1)
		b.toggle_mode = true
		b.button_pressed = brush == nm
		b.pressed.connect(func():
			brush = String(nm)
			status.text = "刷子：%s" % nm
			_refresh_variants(base, names))
		variant_box.add_child(b)


func _update_info() -> void:
	if info == null:
		return
	var lines := []
	lines.append("items=%d  吸附=%s  网格=%.0fm%s" % [
		items.size(), "开" if snapping else "关", float(map_data.get("grid", 4.0)),
		"  ●未保存" if dirty else ""])
	if selected >= 0 and selected < items.size():
		var it: Dictionary = items[selected]
		var p: Array = it["pos"]
		var s: Array = it["scale"]
		lines.append("选中 #%d %s" % [selected, it["part"]])
		lines.append("  pos (%.2f, %.2f, %.2f)" % [p[0], p[1], p[2]])
		lines.append("  rot %.1f°  scale %.2f" % [float(it["rot_deg"][1]), float(s[0])])
	else:
		lines.append("未选中：左键点物体选中，点左侧列表选刷子")
	info.text = "\n".join(lines)


# ---------------------------------------------------------------- 自检

## 不用鼠标证明编辑链路通：放一个 part → 存盘 → 重新读 → 核对条数与坐标。
func _edit_selftest() -> void:
	var before := items.size()
	var probe := "dome-tent" if part_cache.has("dome-tent") else String(items[0].get("part", ""))
	var pos := Vector3(40, 0, 40)
	brush = probe
	_snapshot()
	var inst := _instantiate_part(brush)
	if inst == null:
		print("EDIT-SELFTEST FAIL 没有 part：%s" % probe)
		return get_tree().quit(1)
	inst.transform = Transform3D(Basis(), pos)
	world_root.add_child(inst)
	nodes.append(inst)
	items.append(MapWorld.item_from_transform(brush, inst.transform))
	selected = items.size() - 1
	_commit_transform(selected)

	var tmp := "res://data/maps/_selftest.json"
	map_data["items"] = items
	var err := MapWorld.save_map(tmp, map_data)
	var reload := MapWorld.load_map(tmp)
	var ritems: Array = reload.get("items", [])
	var last: Dictionary = ritems[ritems.size() - 1]
	var p: Array = last["pos"]
	var moved := Vector2(float(p[0]) - pos.x, float(p[2]) - pos.z).length()
	var ok := err == OK and ritems.size() == items.size() and moved < 0.01
	print("EDIT-SELFTEST part=%s items %d→%d save_err=%d reload=%d moved=%.3f" % [
		probe, before, items.size(), err, ritems.size() - before, moved])
	print("EDIT-SELFTEST %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------- 网格

func _build_grid() -> void:
	grid_root = Node3D.new()
	grid_root.name = "Grid"
	add_child(grid_root)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var half := 100.0
	var g := float(map_data.get("grid", 4.0))
	var i := -half
	while i <= half:
		var col := Color(0.35, 0.45, 0.6, 0.55) if absf(i) > 0.01 else Color(0.25, 0.35, 0.55, 0.9)
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(i, 0.02, -half))
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(i, 0.02, half))
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(-half, 0.02, i))
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(half, 0.02, i))
		i += g
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid_root.add_child(mi)
