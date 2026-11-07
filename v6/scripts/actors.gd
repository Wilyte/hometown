class_name ActorSystem
extends Node3D
## 让人物动起来：这套 kit 的 4 个角色共用同一副 31 根骨的 Mixamo 骨架
## （Hips / Spine / LeftUpLeg / LeftArm …），但 GLB 里没有动画片段，
## 所以这里用**程序化步态**驱动骨骼：迈腿、屈膝、摆臂、脊柱扭转、待机呼吸。
##
## 每个角色在自己的出生点附近随机游走（半径可调），到了就停 1~3 s 再走；
## 钓客（lake-angler）默认只待机——他在钓鱼。

const CHARACTERS := ["park-ranger", "backpacker", "kid-with-a-flashlight", "lake-angler"]

var cfg: Dictionary = {}
var actors: Array = []
var time := 0.0


func _process(delta: float) -> void:
	advance(delta)


## 不带渲染地推进时间（出图取证 / 自检用）
func advance(seconds: float) -> void:
	var step := 1.0 / 60.0
	var left := seconds
	while left > 0.0:
		var dt := minf(step, left)
		time += dt
		for a in actors:
			_tick(a, dt)
		left -= dt


func setup(world: Node3D, cfg_in: Dictionary) -> void:
	cfg = cfg_in
	seed(int(cfg.get("seed", 20261107)))   # 固定种子 → 取证与自检可复现
	var radius := float(cfg.get("wander_radius", 6.0))
	var speed := float(cfg.get("speed", 1.15))
	var per: Dictionary = cfg.get("per_part", {})
	for child in world.get_children():
		if not (child is Node3D):
			continue
		var base := String(child.name).split("#")[0].split(".")[0]
		if not CHARACTERS.has(base):
			continue
		var skel := _find_skeleton(child)
		if skel == null:
			continue
		var mode := String(per.get(base, {}).get("mode", "walk"))
		var a := {
			"node": child as Node3D,
			"skel": skel,
			"base": base,
			"mode": mode,
			"spawn": (child as Node3D).global_position,
			"target": (child as Node3D).global_position,
			"speed": speed,
			"radius": radius,
			"phase": randf() * TAU,
			"seed": randf() * TAU,
			"amp": 0.0,
			"wait": randf() * 2.0,
			"yaw": (child as Node3D).rotation.y,
			"base_local": {},
			"base_global": {},
			"idx": {},
		}
		for i in skel.get_bone_count():
			var nm := skel.get_bone_name(i)
			a["idx"][nm] = i
			# glTF 里角色的“手臂放下”是节点姿态，不是 bind 姿势（bind 是 T-pose）。
			# 所以我们以「导入后的初始姿态」为基准，在上面叠世界轴旋转。
			a["base_local"][nm] = skel.get_bone_pose_rotation(i)
			a["base_global"][nm] = skel.get_bone_global_pose(i).basis.get_rotation_quaternion()
		actors.append(a)
	var names: Array[String] = []
	for a in actors:
		names.append(String(a["base"]))
	print("ACTORS %d：%s" % [actors.size(), ", ".join(names)])


func pos_of(base: String) -> Variant:
	for a in actors:
		if String(a["base"]) == base:
			return (a["node"] as Node3D).global_position
	return null


func report() -> void:
	for a in actors:
		var n: Node3D = a["node"]
		var p := n.global_position
		print("ACTOR %-24s pos=(%.2f, %.2f, %.2f) amp=%.2f phase=%.2f" % [
			String(a["base"]), p.x, p.y, p.z, float(a["amp"]), float(a["phase"])])


func _find_skeleton(root: Node) -> Skeleton3D:
	var list := root.find_children("*", "Skeleton3D", true, false)
	return (list[0] as Skeleton3D) if not list.is_empty() else null


# ---------------------------------------------------------------- 每帧

func _tick(a: Dictionary, dt: float) -> void:
	var node: Node3D = a["node"]
	var moving := false

	if String(a["mode"]) == "walk":
		if float(a["wait"]) > 0.0:
			a["wait"] = float(a["wait"]) - dt
		else:
			var to: Vector3 = a["target"] - node.global_position
			to.y = 0.0
			var d := to.length()
			if d < 0.2:
				a["target"] = _new_target(a)
				a["wait"] = randf_range(1.0, 3.0)
			else:
				moving = true
				var dir := to / d
				node.global_position = node.global_position + dir * float(a["speed"]) * dt
				a["yaw"] = lerp_angle(float(a["yaw"]), atan2(dir.x, dir.z), clampf(dt * 8.0, 0.0, 1.0))

	# 步频：走得快时迈得密；停下时相位继续走一点再收住
	a["amp"] = lerpf(float(a["amp"]), 1.0 if moving else 0.0, clampf(dt * 6.0, 0.0, 1.0))
	var speed_now := maxf(float(a["speed"]) * float(a["amp"]), 0.0)
	a["phase"] = float(a["phase"]) + (speed_now * 2.6 + float(a["amp"]) * 1.2) * dt

	node.rotation.y = float(a["yaw"])
	var bob := absf(sin(float(a["phase"]))) * 0.035 * float(a["amp"])
	node.global_position.y = float(a["spawn"].y) + bob
	_pose(a)


func _new_target(a: Dictionary) -> Vector3:
	var ang := randf() * TAU
	var r := sqrt(randf()) * float(a["radius"])
	var s: Vector3 = a["spawn"]
	return Vector3(s.x + cos(ang) * r, s.y, s.z + sin(ang) * r)


func _pose(a: Dictionary) -> void:
	var amp: float = a["amp"]
	var ph: float = a["phase"]
	var swing := sin(ph)
	var breathe := sin(time * 1.6 + float(a["seed"])) * 0.02

	_rot(a, "LeftUpLeg", Vector3.RIGHT, swing * 0.32 * amp)
	_rot(a, "RightUpLeg", Vector3.RIGHT, -swing * 0.32 * amp)
	_rot(a, "LeftLeg", Vector3.RIGHT, -maxf(0.0, -swing) * 0.45 * amp)
	_rot(a, "RightLeg", Vector3.RIGHT, -maxf(0.0, swing) * 0.45 * amp)
	_rot(a, "LeftFoot", Vector3.RIGHT, maxf(0.0, -swing) * 0.25 * amp)
	_rot(a, "RightFoot", Vector3.RIGHT, maxf(0.0, swing) * 0.25 * amp)
	_rot(a, "LeftArm", Vector3.RIGHT, -swing * 0.22 * amp)
	_rot(a, "RightArm", Vector3.RIGHT, swing * 0.22 * amp)
	_rot(a, "LeftForeArm", Vector3.RIGHT, -0.12 * amp)
	_rot(a, "RightForeArm", Vector3.RIGHT, -0.12 * amp)
	_rot(a, "Spine1", Vector3.UP, swing * 0.05 * amp)
	_rot(a, "Spine", Vector3.RIGHT, breathe)
	_rot(a, "Head", Vector3.UP, sin(time * 0.4 + float(a["seed"])) * 0.18 * (1.0 - amp * 0.6))


## 以世界轴下指令，叠加在导入时的初始姿态上：
##   q_local = base_local · (base_global⁻¹ · R · base_global)
func _rot(a: Dictionary, bone: String, axis: Vector3, angle: float) -> void:
	var idx: Dictionary = a["idx"]
	if not idx.has(bone):
		return
	var i: int = idx[bone]
	var bl: Quaternion = a["base_local"][bone]
	var bg: Quaternion = a["base_global"][bone]
	var r := Quaternion(axis, angle)
	var q: Quaternion = bl * (bg.inverse() * r * bg)
	(a["skel"] as Skeleton3D).set_bone_pose_rotation(i, q)
