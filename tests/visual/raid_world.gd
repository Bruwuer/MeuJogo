extends SceneTree
## Headless balance check (not a test): a player kingdom founded next to a wolf den, left alone for
## DAYS game days (packs and villages summarized). Prints raids by motive, what fell and who left.
## Usage: powershell -ExecutionPolicy Bypass -File tools/godot.ps1 --headless -s res://tests/visual/raid_world.gd

const DAYS := 15


func _initialize() -> void:
	for world_seed in [GameConstants.WORLD_SEED, 7]:
		_run(world_seed)
	quit(0)


func _run(world_seed: int) -> void:
	var s := WorldState.new()
	s.seed = world_seed
	var gen := TerrainGenerator.new(world_seed)
	var scatter := PropScatter.new(gen, world_seed)
	var size := ChunkMath.playable_size()
	var center := TestSpots.flat_clear(gen, scatter, GameConstants.Building.CABIN, 8.0, Vector2(size * 0.5, size * 0.5))
	var seat := s.add_building(GameConstants.Building.CABIN, center, 0)
	var k := s.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	var den := center + Vector3(35, 0, 0)
	var pack := s.add_pack("lobo", den)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	for i in 4:
		s.add_creature(Genome.random("lobo", rng), den + Vector3(i, 0, 0), pack.id)
	var packs := PackSim.new()
	root.add_child(packs)
	packs.setup(s, null)
	var raids := {}
	packs.raid_started.connect(func(_p: Dictionary, _k: Dictionary, motive: String) -> void:
		raids[motive] = int(raids.get(motive, 0)) + 1)
	var sim := VillageSim.new()
	root.add_child(sim)
	sim.setup(s, gen, scatter, null)
	for h in DAYS * 24:
		sim.tick_hours(1.0)
		packs.is_night_override = fmod(sim.now_hours(), 24.0) >= GameConstants.SLEEP_START_HOUR \
				or fmod(sim.now_hours(), 24.0) < GameConstants.SLEEP_END_HOUR
		packs.tick_hours(1.0)
		if h % 24 == 23:
			var snap := sim.snapshot(k)
			var farmers := s.residents(k.id).filter(func(p: Dictionary) -> bool: return int(p.profession) == GameConstants.Profession.FARMER and SocietyRules.is_adult(p)).size()
			print("    food=%d berries=%d wood=%d stone=%d farms=%d farmers=%d site=%s next=%d food_days=%.1f left=%s" % [s.stock_of(k, GameConstants.Res.FOOD), s.stock_of(k, GameConstants.Res.BERRIES), s.stock_of(k, GameConstants.Res.WOOD), s.stock_of(k, GameConstants.Res.STONE), int(snap.farms), farmers, str(s.building(int(k.site_id)).get("type", -1)), VillageRules.next_project(snap), float(snap.food_days), str(snap.get("props_left", {}))])
			print("  day %d: residents=%d buildings=%d hunger=%.2f territory=%.2f raids=%s" % [(h + 1) / 24,
					s.residents(k.id).size(), VillageRules.kingdom_buildings(s, k).size(), float(pack.hunger),
					float(pack.territory), raids])
	var fell := 0
	var left := 0
	for e in s.chronicle_all(k.id, 100000):
		var t := String(e.text)
		if t.contains("destruíram"):
			fell += t.count(",") + t.count(" e ") + 1
		if t.contains("deixou o Reino") or t.contains("seguiu viagem") or t.contains("começaram a construir") or t.contains("terminaram") or t.contains("abandonaram"):
			print("    ", AdminLog.line(s, e))
		if t.contains("deixou o Reino"):
			left += 1
	print("SEED %d: raids=%s fell=%d left=%d residents=%d" % [world_seed, raids, fell, left, s.residents(k.id).size()])
	sim.free()
	packs.free()
