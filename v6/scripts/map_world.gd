class_name MapWorld
extends RefCounted
## 地图数据的读写与拼装（观看器和编辑器共用）。
##
## 地图 JSON：
##   { "version": 1, "name": "campground", "grid": 4.0,
##     "items": [ { "part": "dome-tent", "pos": [x,y,z], "rot_deg": [x,y,z],
##                  "scale": [sx,sy,sz] } ] }
##
## part 文件解析顺序：assets/parts_over/<name>.tscn|.glb（人工改过的）→
##                  assets/parts/<name>.tscn（拆件器生成）。

const PARTS_DIR := "res://assets/parts"
const OVER_DIR := "res://assets/parts_over"


static func load_map(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	if not (data is Dictionary):
		return {}
	if not (data as Dictionary).has("items"):
		return {}
	return data


static func save_map(path: String, data: Dictionary) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("写不了 %s (err=%d)" % [path, FileAccess.get_open_error()])
		return FAILED
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return OK


static func part_path(part: String) -> String:
	for ext in [".tscn", ".glb"]:
		var p := "%s/%s%s" % [OVER_DIR, part, ext]
		if ResourceLoader.exists(p):
			return p
	return "%s/%s.tscn" % [PARTS_DIR, part]


static func item_transform(it: Dictionary) -> Transform3D:
	var pos: Array = it.get("pos", [0, 0, 0])
	var rot: Array = it.get("rot_deg", [0, 0, 0])
	var scl: Array = it.get("scale", [1, 1, 1])
	var b := Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])),
			deg_to_rad(float(rot[2]))))
	b = b * Basis.from_scale(Vector3(float(scl[0]), float(scl[1]), float(scl[2])))
	return Transform3D(b, Vector3(float(pos[0]), float(pos[1]), float(pos[2])))


static func item_from_transform(part: String, xf: Transform3D) -> Dictionary:
	var e := xf.basis.get_euler()
	var s := xf.basis.get_scale()
	return {
		"part": part,
		"pos": [_r(xf.origin.x), _r(xf.origin.y), _r(xf.origin.z)],
		"rot_deg": [_r(rad_to_deg(e.x)), _r(rad_to_deg(e.y)), _r(rad_to_deg(e.z))],
		"scale": [_r(s.x), _r(s.y), _r(s.z)],
	}


## 把 items 拼成节点树；返回成功实例化的个数。
static func build(data: Dictionary, parent: Node3D) -> int:
	var cache := {}
	var n := 0
	for it in data.get("items", []):
		var part := String(it.get("part", ""))
		if part == "":
			continue
		if not cache.has(part):
			var p := part_path(part)
			cache[part] = load(p) if ResourceLoader.exists(p) else null
			if cache[part] == null:
				push_warning("缺 part：%s（%s）" % [part, p])
		if cache[part] == null:
			continue
		var inst: Node3D = (cache[part] as PackedScene).instantiate()
		n += 1
		inst.name = "%s#%d" % [part, n]
		# 与 part 场景自带的根变换相乘：parts_over 里的覆盖文件可以直接在根部
		# 加缩放/朝向来做「这一件模型整体微调」，不会被摆放变换抹掉。
		inst.transform = item_transform(it) * inst.transform
		parent.add_child(inst)
	return n


static func _r(v: float) -> float:
	return snappedf(v, 0.0001)
