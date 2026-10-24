class_name Arrow
extends Node3D
## A flying arrow: moves with gravity and checks each physics step with a ray (terrain,
## obstacles and creatures). It hurts the first creature it hits and sticks where it lands.

var velocity := Vector3.ZERO
var damage := 0.0
var shooter: Node3D

var _stuck := false
var _left := GameConstants.ARROW_LIFETIME


func launch(pos: Vector3, dir: Vector3, speed: float, dmg: float, who: Node3D, scene: PackedScene) -> void:
	add_to_group("arrows")
	if scene:
		add_child(scene.instantiate())
	global_position = pos
	velocity = dir.normalized() * speed
	damage = dmg
	shooter = who
	_orient()
	reset_physics_interpolation()


func is_stuck() -> bool:
	return _stuck


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	if _stuck:
		return
	velocity.y -= GameConstants.ARROW_GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to,
			GameConstants.LAYER_TERRAIN | GameConstants.LAYER_OBSTACLES | GameConstants.LAYER_CREATURES)
	if shooter is CollisionObject3D:
		q.exclude = [(shooter as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		_orient()
		return
	var target := hit.collider as Creature
	if target and not target.is_dead():
		target.health.damage(damage, shooter)
		target.knockback(Vector3(velocity.x, 0.0, velocity.z).normalized() * GameConstants.WEAPONS[GameConstants.Weapon.BOW].knockback)
		queue_free()
		return
	global_position = hit.position
	_stuck = true
	_left = GameConstants.ARROW_STICK_SEC


## The model points along +Y; turn it along the flight direction.
func _orient() -> void:
	if velocity.length_squared() < 0.0001:
		return
	var y := velocity.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	global_basis = Basis(x, y, x.cross(y))
