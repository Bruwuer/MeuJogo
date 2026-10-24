extends GameTest

const S := CreatureBrain.State


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	return r


func _me(species: String, extra := {}) -> Dictionary:
	var me := {
		id = 1, genome = Genome.random(species, _rng()), pos = Vector3.ZERO, hp_ratio = 1.0, hunger = 0.0,
		is_night = false, pack_leader_pos = null, den_pos = Vector3.ZERO, mate = {}, raid_target = {},
		hostile_to_player = false,
	}
	me.merge(extra, true)
	return me


func _other(id: int, species: String, pos: Vector3, is_cub := false) -> Dictionary:
	var sp: Dictionary = GameConstants.SPECIES[species]
	return { id = id, kind = "creature", pos = pos, diet = sp.diet, species = species, is_cub = is_cub }


func _player(pos: Vector3) -> Dictionary:
	return { id = 99, kind = "player", pos = pos, diet = GameConstants.Diet.CARNIVORE, species = "", is_cub = false }


func test_herbivore_flees_carnivore() -> void:
	var d := CreatureBrain.decide(_me("cervo"), { nearby = [_other(2, "lobo", Vector3(5, 0, 0))] })
	assert_eq(d.state, S.FLEE)
	assert_true((d.target_pos as Vector3).x < 0.0, "should run away from the wolf: %s" % d.target_pos)


func test_carnivore_hunts_herbivore_when_hungry() -> void:
	var d := CreatureBrain.decide(_me("lobo", { hunger = 0.9 }), { nearby = [_other(2, "cervo", Vector3(10, 0, 0))] })
	assert_eq(d.state, S.HUNT)
	assert_eq(d.target_id, 2)


func test_fed_carnivore_ignores_prey() -> void:
	var d := CreatureBrain.decide(_me("lobo", { hunger = 0.1 }), { nearby = [_other(2, "cervo", Vector3(10, 0, 0))] })
	assert_true(d.state != S.HUNT and d.state != S.ATTACK, "fed wolf hunts: %d" % d.state)


func test_attacks_in_range() -> void:
	var d := CreatureBrain.decide(_me("lobo", { hunger = 0.9 }), { nearby = [_other(2, "cervo", Vector3(1, 0, 0))] })
	assert_eq(d.state, S.ATTACK)
	assert_eq(d.target_id, 2)


func test_hostile_attacks_player() -> void:
	var d := CreatureBrain.decide(_me("lobo", { hostile_to_player = true }), { nearby = [_player(Vector3(8, 0, 0))] })
	assert_eq(d.state, S.HUNT)
	assert_eq(d.target_id, 99)
	var calm := CreatureBrain.decide(_me("lobo"), { nearby = [_player(Vector3(8, 0, 0))] })
	assert_true(calm.state != S.HUNT and calm.state != S.ATTACK, "calm wolf attacks the player")


func test_nocturnal_sleeps_by_day() -> void:
	assert_eq(CreatureBrain.decide(_me("rastejante", { is_night = false }), { nearby = [] }).state, S.SLEEP)
	assert_true(CreatureBrain.decide(_me("rastejante", { is_night = true }), { nearby = [] }).state != S.SLEEP)
	assert_eq(CreatureBrain.decide(_me("cervo", { is_night = true }), { nearby = [] }).state, S.SLEEP)
	# A threat wakes a sleeper up.
	var d := CreatureBrain.decide(_me("cervo", { is_night = true }), { nearby = [_other(2, "lobo", Vector3(3, 0, 0))] })
	assert_eq(d.state, S.FLEE)


func test_follows_leader() -> void:
	var d := CreatureBrain.decide(_me("lobo", { pack_leader_pos = Vector3(20, 0, 0) }), { nearby = [] })
	assert_eq(d.state, S.FOLLOW)
	var near := CreatureBrain.decide(_me("lobo", { pack_leader_pos = Vector3(2, 0, 0) }), { nearby = [] })
	assert_true(near.state != S.FOLLOW, "follows a leader that is already close")


func test_low_hp_flees() -> void:
	var d := CreatureBrain.decide(_me("lobo", { hp_ratio = 0.1, hostile_to_player = true }), { nearby = [_player(Vector3(4, 0, 0))] })
	assert_eq(d.state, S.FLEE)


func test_mates_when_calm() -> void:
	var d := CreatureBrain.decide(_me("cervo", { mate = { id = 5, pos = Vector3(4, 0, 0) } }), { nearby = [] })
	assert_eq(d.state, S.MATE)
	assert_eq(d.target_id, 5)


func test_raid_targets_building() -> void:
	var me := _me("lobo", { raid_target = { id = 7, pos = Vector3(30, 0, 0) }, is_night = true })
	var d := CreatureBrain.decide(me, { nearby = [] })
	assert_eq(d.state, S.RAID)
	assert_eq(d.target_id, 7)
	assert_eq(d.target_pos, Vector3(30, 0, 0))
	# Without a raid target nothing draws it to buildings.
	var calm := CreatureBrain.decide(_me("lobo", { is_night = true }), { nearby = [] })
	assert_true(calm.state != S.RAID)


func test_territorial_fight() -> void:
	var me := _me("urso", { hunger = 0.2 })
	me.genome.aggression = 0.9
	var d := CreatureBrain.decide(me, { nearby = [_other(2, "lobo", Vector3(6, 0, 0))] })
	assert_true(d.state == S.HUNT or d.state == S.ATTACK, "aggressive bear ignores a rival: %d" % d.state)
	assert_eq(d.target_id, 2)
