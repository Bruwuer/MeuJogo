class_name RainFx
extends GPUParticles3D
## The drops of a rainy day (stage 11): thin streaks falling in a box that follows the player.
## Made by code (an effect, not a model): a stretched quad, a falling process material.


func _init() -> void:
	name = "Rain"
	amount = GameConstants.RAIN_DROPS
	lifetime = GameConstants.RAIN_LIFETIME
	emitting = false
	visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = GameConstants.RAIN_BOX
	mat.direction = Vector3(0.15, -1.0, 0.05)
	mat.spread = 2.0
	mat.initial_velocity_min = GameConstants.RAIN_SPEED * 0.9
	mat.initial_velocity_max = GameConstants.RAIN_SPEED
	mat.gravity = Vector3(0, -GameConstants.RAIN_SPEED, 0)
	process_material = mat
	var drop := QuadMesh.new()
	drop.size = GameConstants.RAIN_DROP_SIZE
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = GameConstants.RAIN_COLOR
	look.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = look
	draw_pass_1 = drop
