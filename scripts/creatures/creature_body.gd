class_name CreatureBody
extends Node3D
## Visual body of a creature, assembled from Blender parts chosen by its genome and animated by
## code (the "rig" is this node hierarchy: legs pivot at the hips, head at the neck, tail at its
## base). The root sits on the ground; the whole body is scaled by genome.size.

const _WALK_FREQ := 7.0 ## Leg cycles (radians/s) at speed_ratio 1.
const _RUN_FREQ_BONUS := 4.0
const _WALK_SWING := deg_to_rad(28.0)
const _RUN_SWING := deg_to_rad(48.0)
const _BOB := 0.04
const _BREATH_FREQ := 2.2
const _BREATH := 0.015
const _TAIL_SWAY := 0.35
const _LUNGE := deg_to_rad(-25.0)
const _ACTION_TIME := 0.25

var genome: Dictionary

var _torso: Node3D
var _head: Node3D
var _tail: Node3D
var _legs: Array[Node3D] = []
var _torso_base_y := 0.0
var _phase := 0.0
var _time := 0.0


func build(g: Dictionary, library: ModelLibrary) -> void:
	genome = g
	var sockets: Dictionary = GameConstants.BODY_SOCKETS[g.body]
	scale = Vector3.ONE * g.size
	_torso = Node3D.new()
	_torso.name = "Body"
	_torso_base_y = sockets.leg_length - (sockets.legs[0] as Vector3).y
	_torso.position.y = _torso_base_y
	add_child(_torso)
	_attach(_torso, library, "body", GameConstants.Body, g.body)

	_head = _pivot("Head", _torso, sockets.head)
	_attach(_head, library, "head", GameConstants.Head, g.head)
	if g.tail != GameConstants.Tail.NONE:
		_tail = _pivot("Tail", _torso, sockets.tail)
		_attach(_tail, library, "tail", GameConstants.Tail, g.tail)
	if g.extra != GameConstants.Extra.NONE:
		var on_head: bool = GameConstants.EXTRA_ON_HEAD.has(g.extra)
		var extra := _pivot("Extra", _head if on_head else _torso, GameConstants.HEAD_TOP if on_head else sockets.extra)
		_attach(extra, library, "extra", GameConstants.Extra, g.extra)
	for i in 4:
		var leg := _pivot("Leg%d" % i, _torso, sockets.legs[i])
		var mesh_holder := Node3D.new()
		mesh_holder.scale = Vector3(1.0, sockets.leg_length, 1.0) # unit-length leg mesh
		leg.add_child(mesh_holder)
		_attach(mesh_holder, library, "leg", GameConstants.Legs, g.legs)
		_legs.append(leg)
	_recolor()


## Height of the torso center above the ground, in world units.
func standing_height() -> float:
	return _torso_base_y * genome.size


func leg_angle(i: int) -> float:
	return _legs[i].rotation.x


## speed_ratio: 0 = standing, 1 = walking, > 1 = running.
func animate(delta: float, speed_ratio: float) -> void:
	_time += delta
	if speed_ratio < 0.05:
		for leg in _legs:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, minf(1.0, delta * 10.0))
		_torso.position.y = _torso_base_y + sin(_time * _BREATH_FREQ) * _BREATH
	else:
		var running := speed_ratio > 1.0
		_phase += delta * (_WALK_FREQ * minf(speed_ratio, 1.0) + (_RUN_FREQ_BONUS if running else 0.0))
		var swing := _RUN_SWING if running else _WALK_SWING * minf(speed_ratio, 1.0)
		# Diagonal pairs move together (0 with 3, 1 with 2).
		_legs[0].rotation.x = sin(_phase) * swing
		_legs[3].rotation.x = sin(_phase) * swing
		_legs[1].rotation.x = -sin(_phase) * swing
		_legs[2].rotation.x = -sin(_phase) * swing
		_torso.position.y = _torso_base_y + absf(sin(_phase)) * _BOB
	if _tail:
		_tail.rotation.y = sin(_time * 3.0) * _TAIL_SWAY


func play_attack() -> void:
	var tw := create_tween()
	tw.tween_property(_head, "rotation:x", _LUNGE, _ACTION_TIME * 0.4)
	tw.tween_property(_head, "rotation:x", 0.0, _ACTION_TIME * 0.6)


func play_hurt() -> void:
	var tw := create_tween()
	tw.tween_property(_torso, "rotation:z", 0.15, _ACTION_TIME * 0.3)
	tw.tween_property(_torso, "rotation:z", 0.0, _ACTION_TIME * 0.7)


func play_death() -> void:
	var tw := create_tween()
	tw.tween_property(_torso, "rotation:z", PI * 0.5, _ACTION_TIME * 2.0)


func _pivot(node_name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


func _attach(parent: Node3D, library: ModelLibrary, slot: String, enum_dict: Dictionary, value: int) -> void:
	var part := "%s_%s" % [slot, (enum_dict.keys()[value] as String).to_lower()]
	var scene := library.part_scene(part)
	if scene:
		parent.add_child(scene.instantiate())


## One duplicated material per color slot, shared by all of this creature's surfaces.
func _recolor() -> void:
	var own := {}
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat == null or not (mat.resource_name in ["primary", "secondary"]):
				continue
			if not own.has(mat.resource_name):
				var copy := mat.duplicate() as ShaderMaterial
				copy.set_shader_parameter("albedo", genome.color_a if mat.resource_name == "primary" else genome.color_b)
				own[mat.resource_name] = copy
			mi.set_surface_override_material(s, own[mat.resource_name])
