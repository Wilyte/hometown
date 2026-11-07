extends SceneTree
## 探针：同名 part 的不同实例，几何是否"同一份资产 + 不同摆放"？
## 对每个实例的每块网格，算 W^-1 · 子树变换，看两个实例是否一致。
##   godot --headless --path v6 -s res://tools/probe_variants.gd

const SRC := "res://assets/kit_campground_lake/kit-campground-lake-ad32b0.glb"


func _initialize() -> void:
	var ps: PackedScene = load(SRC)
	var kit: Node = ps.instantiate()
	var comp: Node = kit
	if comp.get_child_count() == 1 and comp.get_child(0).get_child_count() > 1:
		comp = comp.get_child(0)

	var buckets := {}
	for p in comp.get_children():
		var n := String(p.name).rstrip("0123456789")
		buckets.get_or_add(n, []).append(p)

	for n in ["dome-tent", "campground-pine-stand", "folding-camp-chair", "lake-dock-run"]:
		var list: Array = buckets.get(n, [])
		if list.size() < 2:
			continue
		print("== %s (%d 实例)" % [n, list.size()])
		var sigs := []
		for p in list.slice(0, 3):
			var xf: Transform3D = (p as Node3D).transform
			var inv := xf.affine_inverse()
			var rows: Array[String] = []
			for mi in p.find_children("*", "MeshInstance3D", true, false):
				var rel := inv * _rel(p, mi)
				rows.append("%s @%s" % [(mi as MeshInstance3D).mesh.resource_path.get_file(),
						str(rel.origin.snapped(Vector3.ONE * 0.01))])
			sigs.append(" ; ".join(rows))
			print("   W=%s" % str(xf.origin))
		for i in sigs.size():
			print("   sig%d=%s" % [i, sigs[i]])
		print("   identical?", sigs[1] == sigs[0] if sigs.size() > 1 else "n/a")
	kit.free()
	quit()


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
