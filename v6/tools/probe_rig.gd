extends SceneTree
## 探针：这些人物 part 到底有没有骨架、骨头叫什么、有多少根。
##   godot --headless --path v6 -s res://tools/probe_rig.gd

const NAMES := ["park-ranger", "backpacker", "kid-with-a-flashlight", "lake-angler"]


func _initialize() -> void:
	for base in NAMES:
		for suffix in ["", ".v2", ".v3", ".v4"]:
			var nm: String = base + suffix
			var path := "res://assets/parts/%s.tscn" % nm
			if not ResourceLoader.exists(path):
				continue
			var inst: Node = (load(path) as PackedScene).instantiate()
			var skels := inst.find_children("*", "Skeleton3D", true, false)
			var skinned := 0
			for n in inst.find_children("*", "MeshInstance3D", true, false):
				if (n as MeshInstance3D).skin != null:
					skinned += 1
			print("== %s  skeleton=%d  skinned_mesh=%d" % [nm, skels.size(), skinned])
			for s in skels:
				var sk := s as Skeleton3D
				var names: Array[String] = []
				for i in sk.get_bone_count():
					names.append(sk.get_bone_name(i))
				print("   bones(%d): %s" % [names.size(), ", ".join(names)])
			inst.free()
			if suffix == "":
				break
	quit()
