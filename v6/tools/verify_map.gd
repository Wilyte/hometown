extends SceneTree
## 校验 map.json 重摆是否还原整张 GLB：逐条比对每个 part 实例的世界包围盒。
##   godot --headless --path v6 -s res://tools/verify_map.gd

const SRC := "res://assets/kit_campground_lake/kit-campground-lake-ad32b0.glb"
const MAP := "res://data/maps/campground.json"
const PART_DIR := "res://assets/parts"


func _initialize() -> void:
	_run()


func _run() -> void:
	var ps: PackedScene = load(SRC)
	var kit: Node = ps.instantiate()
	var comp: Node = kit
	if comp.get_child_count() == 1 and comp.get_child(0).get_child_count() > 1:
		comp = comp.get_child(0)
	var glb_parts := comp.get_children()

	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var items: Array = map["items"]

	var cache := {}
	var worst: Array = []
	var moved := 0
	for i in items.size():
		var it: Dictionary = items[i]
		var pname := String(it["part"])
		if not cache.has(pname):
			cache[pname] = load("%s/%s.tscn" % [PART_DIR, pname])
		var inst: Node3D = (cache[pname] as PackedScene).instantiate()
		inst.transform = _xf(it)

		var a := _mesh_bounds(comp, glb_parts[i])
		var b := _mesh_bounds(null, inst)
		var dc := a.get_center().distance_to(b.get_center())
		var ds := a.size.distance_to(b.size)
		if dc > 0.01 or ds > 0.01:
			moved += 1
			worst.append([maxf(dc, ds), pname, a.get_center(), b.get_center(), a.size, b.size,
					String(str((glb_parts[i] as Node3D).transform)), String(str(_xf(it)))])
		inst.free()
	print("VERIFY items=%d mismatched=%d" % [items.size(), moved])
	worst.sort_custom(func(x, y): return x[0] > y[0])
	for w in worst.slice(0, 3):
		print("  %-28s d=%.3f glb_c=%s map_c=%s" % [w[1], w[0], str(w[2]), str(w[3])])
		print("      glb_xf=%s" % w[6])
		print("      map_xf=%s" % w[7])
	kit.free()
	quit()


func _xf(it: Dictionary) -> Transform3D:
	var p: Array = it["pos"]
	var r: Array = it["rot_deg"]
	var s: Array = it["scale"]
	var b := Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])))
	b = b * Basis.from_scale(Vector3(s[0], s[1], s[2]))
	return Transform3D(b, Vector3(p[0], p[1], p[2]))


func _mesh_bounds(root: Node, part: Node) -> AABB:
	var box := AABB()
	var first := true
	for n in part.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = _rel(part, mi) * mi.mesh.get_aabb()
		b = _rel(root, part) * b
		box = b if first else box.merge(b)
		first = false
	return box


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
