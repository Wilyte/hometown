extends SceneTree
## 拆件器：把整张 kit 场景 GLB 拆成「part 库 + 地图清单」。
##   godot --headless --path v6 -s res://tools/split_parts.gd
##
## 关键事实：同名 part 的不同实例**几何可能不一样**（松树丛、芦苇、码头这类是随机
## 变体，不是同一份网格的缩放）。所以按「名字 + 几何签名」分组：
##   一个变体 → <name>.tscn
##   多个变体 → <name>.tscn、<name>.v2.tscn、<name>.v3.tscn …
## 这样地图能 1:1 还原原始场景，同时保留可复用的 part 库。
##
## 产物：
##   res://assets/parts/<variant>.tscn   根节点恒等变换，几何以「脚底中心」为原点
##   res://data/maps/campground.json     174 条摆放记录（part / pos / rot_deg / scale）
##   res://assets/parts/parts.json       每个变体的锚点 / 尺寸 / 面数 / 实例数
##
## 坐标口径（part = 一个变体，W = 实例相对 kit 根的变换，a = part 局部包围盒脚底中心）：
##   拆出来的场景：根(恒等) → anchor(Translate(-a)) → 原子树      ← 不含 W
##   摆放记录：    pos = W * a，rot/scale 取自 W 的基
##   于是 I·Translate(-a)·X = W·X，几何位置与原图一致。

const SRC := "res://assets/kit_campground_lake/kit-campground-lake-ad32b0.glb"
const PARTS_DIR := "res://assets/parts"
const MAP_PATH := "res://data/maps/campground.json"
const PARTS_JSON := "res://assets/parts/parts.json"


func _initialize() -> void:
	_run()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	for f in DirAccess.get_files_at(PARTS_DIR):
		if f.ends_with(".tscn"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [PARTS_DIR, f]))

	var ps: PackedScene = load(SRC)
	if ps == null:
		push_error("载不到 %s" % SRC)
		return quit(1)
	var kit: Node = ps.instantiate()
	var comp: Node = kit
	if comp.get_child_count() == 1 and comp.get_child(0).get_child_count() > 1:
		comp = comp.get_child(0)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PARTS_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAP_PATH.get_base_dir()))

	var name_re := RegEx.create_from_string("^(.*?)(\\d+)$")
	var seen_bases := {}
	var recs: Array = []
	var groups := {}      # key -> {base, reps, ...}
	var order: Array = []

	# 第一遍：识别每个实例的基名 + 几何签名
	for p in comp.get_children():
		var pname := String(p.name)
		if not seen_bases.has(pname):
			var m := name_re.search(pname)
			if m != null and seen_bases.has(m.get_string(1)):
				pname = m.get_string(1)
		seen_bases[pname] = true

		var sig := _signature(p)
		var key := pname + "|" + sig
		if not groups.has(key):
			groups[key] = {"base": pname, "rep": p, "sig": sig, "count": 0}
			order.append(key)
		groups[key]["count"] = int(groups[key]["count"]) + 1

		var xf: Transform3D = (p as Node3D).transform
		var box := _local_aabb(p)
		var anchor := Vector3(box.position.x + box.size.x * 0.5, box.position.y,
				box.position.z + box.size.z * 0.5)
		recs.append({"key": key, "xf": xf, "anchor": anchor, "tris": _count_tris(p),
				"meshes": p.find_children("*", "MeshInstance3D", true, false).size()})

	# 第二遍：给每个变体定名（同基名多变体时 .v2/.v3…）
	var per_base := {}
	for key in order:
		var base: String = groups[key]["base"]
		per_base[base] = int(per_base.get(base, 0)) + 1
	var idx_of_base := {}
	var parts := {}
	for key in order:
		var g: Dictionary = groups[key]
		var base: String = g["base"]
		var n := int(per_base[base])
		var vname := base
		if n > 1:
			idx_of_base[base] = int(idx_of_base.get(base, 0)) + 1
			if int(idx_of_base[base]) > 1:
				vname = "%s.v%d" % [base, int(idx_of_base[base])]
		g["vname"] = vname
		groups[key] = g
		parts[vname] = {"file": "%s/%s.tscn" % [PARTS_DIR, vname], "instances": 0,
				"base": base, "variant": int(idx_of_base.get(base, 1))}

	# 第三遍：写地图条目
	var items: Array = []
	var tris_total := 0
	var meshes_total := 0
	var by_key := {}
	for key in order:
		by_key[key] = groups[key]["vname"]
	for r in recs:
		var key: String = r["key"]
		var vname: String = by_key[key]
		if not parts[vname].has("tris"):
			var box := _local_aabb(groups[key]["rep"])
			var anchor: Vector3 = r["anchor"]
			parts[vname]["anchor"] = [_r(anchor.x), _r(anchor.y), _r(anchor.z)]
			parts[vname]["size"] = [_r(box.size.x), _r(box.size.y), _r(box.size.z)]
			parts[vname]["tris"] = int(r["tris"])
		parts[vname]["instances"] = int(parts[vname]["instances"]) + 1
		tris_total += int(r["tris"])
		meshes_total += int(r["meshes"])

		var xf: Transform3D = r["xf"]
		var anchor2: Vector3 = r["anchor"]
		var pos: Vector3 = xf * anchor2
		var e := xf.basis.get_euler()
		var s := xf.basis.get_scale()
		items.append({
			"part": vname,
			"pos": [_r(pos.x), _r(pos.y), _r(pos.z)],
			"rot_deg": [_r(rad_to_deg(e.x)), _r(rad_to_deg(e.y)), _r(rad_to_deg(e.z))],
			"scale": [_r(s.x), _r(s.y), _r(s.z)],
		})

	# 第四遍：落盘 part 场景（会从原树上摘子节点，所以放最后）
	for key in order:
		var g: Dictionary = groups[key]
		_save_part(g["rep"], String(g["vname"]), _local_aabb(g["rep"]).position)

	_write_json(MAP_PATH, {
		"version": 1,
		"name": "campground",
		"source": SRC,
		"grid": 4.0,
		"items": items,
	})
	_write_json(PARTS_JSON, {"version": 1, "parts": parts})

	print("SPLIT base_parts=%d variants=%d items=%d meshes=%d tris=%d in %d ms" % [
		per_base.size(), parts.size(), items.size(), meshes_total, tris_total,
		Time.get_ticks_msec() - t0])
	kit.free()
	quit()


func _r(v: float) -> float:
	return snappedf(v, 0.0001)


## 几何签名：网格资源 + 每块网格相对 part 的变换 + 节点数。
## 同名但几何不同的实例会落到不同签名 → 拆成不同变体。
func _signature(p: Node) -> String:
	var parts: Array[String] = []
	parts.append("n=%d" % p.find_children("*", "", true, false).size())
	for n in p.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var rel := _rel(p, mi)
		parts.append("%s|%d|%s" % [mi.mesh.resource_path, mi.mesh.get_surface_count(),
				str(rel.origin.snapped(Vector3.ONE * 0.001))])
	return "|".join(parts).md5_text()


func _rel(ancestor: Node, n: Node) -> Transform3D:
	var chain: Array[Node] = []
	var cur: Node = n
	while cur != null and cur != ancestor:
		chain.push_front(cur)
		cur = cur.get_parent()
	var t := Transform3D()
	for c in chain:
		t = t * (c as Node3D).transform
	return t


func _local_aabb(p: Node) -> AABB:
	var box := AABB()
	var first := true
	for n in p.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = _rel(p, mi) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _count_tris(p: Node) -> int:
	var t := 0
	for n in p.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			t += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	return t


func _save_part(p: Node, vname: String, _unused: Vector3) -> void:
	var box := _local_aabb(p)
	var anchor := Vector3(box.position.x + box.size.x * 0.5, box.position.y,
			box.position.z + box.size.z * 0.5)

	var root := Node3D.new()
	root.name = vname
	var wrap := Node3D.new()
	wrap.name = "anchor"
	wrap.transform = Transform3D(Basis(), -anchor)
	root.add_child(wrap)

	for c in p.get_children():
		_clear_owner(c)
		p.remove_child(c)
		wrap.add_child(c)

	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, "%s/%s.tscn" % [PARTS_DIR, vname])
	if err != OK:
		push_error("存 %s 失败 err=%d" % [vname, err])
	root.free()


func _own(root: Node, n: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(root, c)


func _clear_owner(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_clear_owner(c)


func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("写不了 %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
