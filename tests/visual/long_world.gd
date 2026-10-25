extends SceneTree
## Headless balance check (not a test): 60 game days of the NPC kingdoms alone in three worlds,
## printing the relations every 10 days, each kingdom's guard and the events between kingdoms.
## Usage: powershell -ExecutionPolicy Bypass -File tools/godot.ps1 --headless -s res://tests/visual/long_world.gd

const DAYS := 60


func _initialize() -> void:
	for world_seed in [GameConstants.WORLD_SEED, 7, 1234]:
		_run(world_seed)
	quit(0)


func _run(world_seed: int) -> void:
	var s := WorldState.new()
	s.seed = world_seed
	var gen := TerrainGenerator.new(world_seed)
	var scatter := PropScatter.new(gen, world_seed)
	var size := ChunkMath.playable_size()
	NpcRealms.seed(s, gen, scatter, [Vector3(size * 0.5, 0, size * 0.5)])
	var sim := VillageSim.new()
	sim.setup(s, gen, scatter, null)
	var ks := s.kingdoms()
	var dists := []
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			dists.append("%s-%s %.0f m" % [ks[i].name, ks[j].name, Vector2(ks[i].center.x - ks[j].center.x, ks[i].center.z - ks[j].center.z).length()])
	print("SEED %d: %s" % [world_seed, ", ".join(dists)])
	for day in DAYS:
		sim.tick_hours(24.0)
		if day % 10 == 9:
			var rels := []
			var all := s.kingdoms()
			for i in all.size():
				for j in range(i + 1, all.size()):
					var r := s.realm(all[i].id, all[j].id)
					rels.append("%s-%s %+.2f%s" % [all[i].name, all[j].name, float(r.rel), " GUERRA" if r.war else ""])
			print("  day %d: %d kingdoms · %s" % [day + 1, all.size(), ", ".join(rels)])
	for k in s.kingdoms():
		print("  %s: ruler=%d guards=%d strength=%.2f adults=%d decree=%d" % [k.name, int(k.ruler_id),
				RealmRules.guards(s, k).size(), RealmRules.strength(s, k),
				s.residents(k.id).filter(func(p: Dictionary) -> bool: return SocietyRules.is_adult(p)).size(), int(k.decrees.guards)])
	var bodies := s.all_people().filter(func(p: Dictionary) -> bool: return p.status == "dead")
	var stale := bodies.filter(func(p: Dictionary) -> bool: return float(DAYS * 24) - float(p.get("died_hour", 0.0)) > 48.0)
	var graves := s.all_buildings().filter(func(b: Dictionary) -> bool: return int(b.type) == GameConstants.Building.GRAVE)
	var merchants := s.all_people().filter(func(p: Dictionary) -> bool: return p.status == "merchant")
	print("  LIFE: graves=%d bodies_lying=%d (over 2 days: %d) merchants=%d" % [graves.size(), bodies.size(), stale.size(), merchants.size()])
	var seen := {}
	for e in s.chronicle_all(-2, 100000):
		var t := String(e.text)
		if (t.contains("guerra") or t.contains("batalha") or t.contains("paz") and t.contains("Reino de") or t.contains("fundou o Reino")) and not seen.has(t):
			seen[t] = true
			print("  Dia %d: %s" % [floori(float(e.hour) / 24.0), t])
	sim.free()
