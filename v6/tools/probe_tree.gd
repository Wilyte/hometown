extends SceneTree
## 看一眼 GLB 实例化后的树：根节点、前两层、以及顶层 part 数量。
##   godot --headless --path v6 -s res://tools/probe_tree.gd

const SRC := "res://assets/kit_campground_lake/kit-campground-lake-ad32b0.glb"


func _init() -> void:
	var ps: PackedScene = load(SRC)
	var n: Node = ps.instantiate()
	print("ROOT ", n.name, " (", n.get_class(), ") children=", n.get_child_count())
	for c in n.get_children():
		print("  L1 ", c.name, " (", c.get_class(), ") children=", c.get_child_count(),
			" owner=", c.owner.name if c.owner else "<none>")
		for g in c.get_children().slice(0, 5):
			print("    L2 ", g.name, " (", g.get_class(), ") children=", g.get_child_count())
	n.free()
	quit()
