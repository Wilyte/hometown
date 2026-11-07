extends SceneTree
## 探针：GLB 导入后，顶点色到底有没有进材质/网格。
##   godot --headless --path v6 -s res://tools/probe_glb.gd

const GLB := "res://assets/kit_campground_lake/kit-campground-lake-ad32b0.glb"


func _init() -> void:
	var ps: PackedScene = load(GLB)
	var root: Node = ps.instantiate()
	var meshes := 0
	var with_color := 0
	var mat_flags := {}
	var samples: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		meshes += 1
		var arr := mi.mesh.surface_get_arrays(0)
		var has_col := false
		if arr.size() > Mesh.ARRAY_COLOR:
			var cols: Variant = arr[Mesh.ARRAY_COLOR]
			if cols is PackedColorArray and (cols as PackedColorArray).size() > 0:
				has_col = true
		if has_col:
			with_color += 1
		var mat: Material = mi.mesh.surface_get_material(0)
		var mat_class := "null"
		var vc := "n/a"
		var albedo := "n/a"
		if mat != null:
			mat_class = mat.get_class()
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			vc = str(bm.vertex_color_use_as_albedo)
			albedo = str(bm.albedo_color)
		var key := mat_class + " vc=" + vc
		mat_flags[key] = int(mat_flags.get(key, 0)) + 1
		if has_col and samples.size() < 3:
			var cols2 := arr[Mesh.ARRAY_COLOR] as PackedColorArray
			var first: Array = []
			for i in min(3, cols2.size()):
				first.append(str(cols2[i]))
			samples.append("%s vc=%s albedo=%s colors=%s" % [mi.name, vc, albedo, str(first)])
	print("PROBE meshes=%d with_color=%d" % [meshes, with_color])
	print("PROBE matflags=", mat_flags)
	for s in samples:
		print("PROBE ", s)
	quit()
