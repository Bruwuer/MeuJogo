extends GameTest


func _pack(species := "lobo") -> Dictionary:
	return { id = 1, species = species, den = Vector3.ZERO, hunger = 0.0, territory = 0.0, grudge = 0.0,
			cubs_alarm = 0.0, leader_id = -1, raid_kingdom = -1, next_raid_hour = 0.0 }


func _ctx(extra := {}) -> Dictionary:
	var c := { prey_count = 10, buildings_in_territory = 0, player_near_den = false, cubs = 0 }
	c.merge(extra, true)
	return c


func _genome(species := "lobo", s := 1) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return Genome.random(species, r)


func _species_records(s: WorldState, species: String) -> Array:
	return s.all_creatures().filter(func(c: Dictionary) -> bool: return c.genome.species == species)


func test_hunger_rises_and_prey_scarcity() -> void:
	var fed := _pack()
	var starving := _pack()
	for i in 24:
		PackMotives.update(fed, _ctx(), 1.0)
		PackMotives.update(starving, _ctx({ prey_count = 0 }), 1.0)
	assert_true(fed.hunger < 0.2, "plenty of prey keeps hunger low: %f" % fed.hunger)
	assert_true(starving.hunger > 0.6, "no prey should starve the pack: %f" % starving.hunger)
	assert_true(starving.hunger <= 1.0)


func test_grudge_from_kills_decays() -> void:
	var p := _pack()
	PackMotives.add_grudge(p, true)
	var cub_grudge: float = p.grudge
	var q := _pack()
	PackMotives.add_grudge(q, false)
	assert_true(cub_grudge > q.grudge and q.grudge > 0.0, "killing a cub should anger more")
	for i in 48:
		PackMotives.update(p, _ctx(), 1.0)
	assert_true(p.grudge < cub_grudge * 0.5, "grudge should fade over two days: %f" % p.grudge)


func test_territory_from_buildings() -> void:
	var p := _pack()
	PackMotives.update(p, _ctx({ buildings_in_territory = 0 }), 1.0)
	assert_eq(p.territory, 0.0)
	PackMotives.update(p, _ctx({ buildings_in_territory = 6 }), 1.0)
	assert_eq(p.territory, 1.0)


func test_cubs_alarm() -> void:
	var p := _pack("javali")
	PackMotives.update(p, _ctx({ player_near_den = true, cubs = 0 }), 1.0)
	assert_eq(p.cubs_alarm, 0.0, "no cubs, nothing to defend")
	PackMotives.update(p, _ctx({ player_near_den = true, cubs = 2 }), 1.0)
	assert_eq(p.cubs_alarm, 1.0)
	PackMotives.update(p, _ctx({ cubs = 2 }), 6.0)
	assert_true(p.cubs_alarm < 0.2)


func test_no_motive_no_raid() -> void:
	var p := _pack()
	assert_true(not PackMotives.wants_raid(p, 0.9), "a calm, fed pack raids")
	p.hunger = 0.4
	assert_true(not PackMotives.wants_raid(p, 0.6))
	p.hunger = 0.95
	assert_true(PackMotives.wants_raid(p, 0.6), "a starving pack should raid")
	var deer := _pack("cervo")
	deer.grudge = 1.0
	deer.territory = 1.0
	assert_true(not PackMotives.wants_raid(deer, 0.1), "deer never raid")
	var boar := _pack("javali")
	boar.hunger = 1.0
	assert_true(not PackMotives.wants_raid(boar, 0.7), "herbivores do not raid out of hunger")
	boar.cubs_alarm = 1.0
	assert_true(PackMotives.wants_raid(boar, 0.7), "boars defend their cubs")


func test_dominant_motive_message() -> void:
	var p := _pack("urso")
	p.hunger = 0.3
	p.territory = 0.9
	assert_eq(PackMotives.dominant(p), "territory")
	var msg := PackMotives.message(p, "Valdemar")
	assert_true(msg.contains("ursos") and msg.contains("Valdemar") and msg.contains("território"), msg)
	p.grudge = 1.0
	assert_eq(PackMotives.dominant(p), "grudge")
	for motive in ["hunger", "territory", "grudge", "cubs"]:
		assert_true(GameConstants.RAID_MESSAGES.has(motive), "missing message for %s" % motive)


func test_offscreen_raid_damages_non_seat() -> void:
	var s := WorldState.new()
	var cabin := s.add_building(GameConstants.Building.CABIN, Vector3(100, 0, 100), 0)
	var fence := s.add_building(GameConstants.Building.FENCE, Vector3(106, 0, 100), 0)
	var k := s.add_kingdom("Valdemar", Color.RED, cabin.pos, cabin.id)
	var p := s.add_pack("lobo", Vector3(140, 0, 100))
	for i in 4:
		s.add_creature(_genome("lobo", i), Vector3(140 + i, 0, 100), p.id)
	p.hunger = 1.0
	var sim := PackSim.new()
	add_child(sim)
	sim.setup(s, null)
	var destroyed := sim.resolve_offscreen_raid(p, k)
	assert_eq(destroyed, ["Cerca"])
	assert_eq(s.building(fence.id), {})
	assert_true(not s.building(cabin.id).is_empty(), "the seat survived")
	var entries_log := s.chronicle(k.id, 10)
	assert_eq(entries_log.size(), 1, "the raid goes to the ADM log")
	if entries_log.size() == 1:
		assert_true((entries_log[0].text as String).contains("Cerca"), entries_log[0].text)
	assert_true(p.hunger < 1.0, "raiding feeds them a little")


func test_sim_starts_raid_from_motive_only() -> void:
	var s := WorldState.new()
	var cabin := s.add_building(GameConstants.Building.CABIN, Vector3(100, 0, 100), 0)
	s.add_building(GameConstants.Building.FENCE, Vector3(106, 0, 100), 0)
	s.add_kingdom("Valdemar", Color.RED, cabin.pos, cabin.id)
	var p := s.add_pack("lobo", Vector3(160, 0, 100))
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(p.den), 4):
		s.mark_visited(c) # every deer around is known: removing them empties the region
	for i in 3:
		s.add_creature(_genome("lobo", i), Vector3(160 + i, 0, 100), p.id)
	for i in 10:
		s.add_creature(_genome("cervo", 10 + i), Vector3(170, 0, 110 + i), -1)
	var sim := PackSim.new()
	add_child(sim)
	sim.setup(s, null)
	var raids := []
	sim.raid_started.connect(func(_pack: Dictionary, _kingdom: Dictionary, motive: String) -> void: raids.append(motive))
	sim.is_night_override = true
	for i in 48:
		sim.tick_hours(1.0)
	assert_eq(raids.size(), 0, "a fed pack with plenty of deer around raided")
	for c in _species_records(s, "cervo"):
		s.remove_creature(c.id)
	for i in 24:
		sim.tick_hours(1.0)
	assert_true(raids.size() >= 1 and raids[0] == "hunger", "starving pack never raided: %s" % [raids])


func test_unvisited_land_counts_as_prey() -> void:
	var s := WorldState.new()
	var p := s.add_pack("lobo", Vector3(300, 0, 300))
	for i in 3:
		s.add_creature(_genome("lobo", i), Vector3(300 + i, 0, 300), p.id)
	var sim := PackSim.new()
	add_child(sim)
	sim.setup(s, null)
	for i in 24:
		sim.tick_hours(1.0)
	assert_true(p.hunger < 0.3, "wolves starve next to land nobody has visited yet: %f" % p.hunger)


func test_offscreen_raid_reports_destroyed_buildings() -> void:
	var s := WorldState.new()
	var cabin := s.add_building(GameConstants.Building.CABIN, Vector3(100, 0, 100), 0)
	s.add_building(GameConstants.Building.FENCE, Vector3(106, 0, 100), 0)
	var k := s.add_kingdom("Valdemar", Color.RED, cabin.pos, cabin.id)
	var p := s.add_pack("lobo", Vector3(140, 0, 100))
	for i in 4:
		s.add_creature(_genome("lobo", i), Vector3(140 + i, 0, 100), p.id)
	var sim := PackSim.new()
	add_child(sim)
	sim.setup(s, null)
	var gone := []
	sim.building_destroyed.connect(func(rec: Dictionary) -> void: gone.append(rec.type))
	sim.resolve_offscreen_raid(p, k)
	assert_eq(gone, [GameConstants.Building.FENCE])


func test_raid_skipped_when_pack_cannot_reach() -> void:
	var s := WorldState.new()
	var cabin := s.add_building(GameConstants.Building.CABIN, Vector3(100, 0, 100), 0)
	s.add_kingdom("Valdemar", Color.RED, cabin.pos, cabin.id)
	var p := s.add_pack("lobo", Vector3(160, 0, 100))
	for i in 3:
		s.add_creature(_genome("lobo", i), Vector3(160 + i, 0, 100), p.id)
	p.hunger = 1.0
	var sim := PackSim.new()
	add_child(sim)
	sim.setup(s, null)
	sim.is_night_override = true
	sim.raid_mode = func(_p: Dictionary, _k: Dictionary) -> String: return "none"
	var raids := []
	sim.raid_started.connect(func(_a: Dictionary, _b: Dictionary, m: String) -> void: raids.append(m))
	sim.tick_hours(1.0)
	assert_eq(raids, [], "phantom raid announced")
	assert_eq(p.raid_kingdom, -1)


func test_plot_stakes_are_no_building_for_packs() -> void:
	var s := WorldState.new()
	var k := s.add_kingdom("Valdemar", Color.RED, Vector3(100, 0, 100), -1)
	var p := s.add_pack("lobo", Vector3(110, 0, 100))
	s.add_creature(_genome("lobo", 1), Vector3(110, 0, 100), p.id)
	var stake := s.add_building(GameConstants.Building.STAKE, Vector3(104, 0, 100), 0)
	var sim := PackSim.new()
	add_child(sim)
	sim.setup(s, null)
	assert_eq(sim._context(p, s.pack_members(p.id)).buildings_in_territory, 0, "stakes mark land, they do not anger a pack")
	assert_true(not PackSim.is_raid_target(stake, k), "nor are they raided")
	var fence := s.add_building(GameConstants.Building.FENCE, Vector3(104, 0, 104), 0)
	assert_true(PackSim.is_raid_target(fence, k))
	sim.queue_free()
