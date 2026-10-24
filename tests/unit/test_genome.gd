extends GameTest

const PART_GENES := ["body", "head", "legs", "tail", "extra"]


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_all_species_valid() -> void:
	assert_eq(GameConstants.SPECIES.size(), 8)
	for id in GameConstants.SPECIES:
		var sp: Dictionary = GameConstants.SPECIES[id]
		for key in ["name", "invented", "body", "head", "legs", "tail", "extra", "size", "color_a", "color_b",
				"color_jitter", "diet", "aggression", "pack", "speed", "hp", "damage", "perception",
				"nocturnal", "territorial", "biomes"]:
			assert_true(sp.has(key), "%s lacks %s" % [id, key])
		for key in ["size", "aggression", "speed", "hp", "damage"]:
			assert_true(sp[key].x <= sp[key].y, "%s.%s range reversed" % [id, key])
		assert_true(sp.pack.x <= sp.pack.y, "%s.pack range reversed" % id)
	assert_true(not GameConstants.SPECIES.lobo.invented)
	assert_true(GameConstants.SPECIES.espinhudo.invented)


func test_random_within_ranges() -> void:
	var sp: Dictionary = GameConstants.SPECIES.lobo
	for s in 30:
		var g := Genome.random("lobo", _rng(s))
		assert_eq(g.species, "lobo")
		assert_eq(g.lineage, PackedStringArray(["lobo"]))
		assert_true(g.size >= sp.size.x and g.size <= sp.size.y, "size %f" % g.size)
		assert_true(g.max_hp >= sp.hp.x and g.max_hp <= sp.hp.y)
		assert_eq(g.diet, GameConstants.Diet.CARNIVORE)
		assert_eq(g.body, sp.body)
		assert_eq(g.generation, 0)


func test_two_wolves_differ() -> void:
	var a := Genome.random("lobo", _rng(1))
	var b := Genome.random("lobo", _rng(2))
	assert_true(a.size != b.size or a.color_a != b.color_a, "identical wolves")


func test_cross_takes_parts_from_parents() -> void:
	var wolf := Genome.random("lobo", _rng(3))
	var boar := Genome.random("javali", _rng(4))
	var from_a := 0
	var from_b := 0
	for s in 50:
		var c := Genome.cross(wolf, boar, _rng(100 + s))
		assert_eq(c.generation, 1)
		assert_true(Array(c.lineage).has("lobo") and Array(c.lineage).has("javali"))
		for gene in PART_GENES:
			if c[gene] == wolf[gene] and wolf[gene] != boar[gene]:
				from_a += 1
			elif c[gene] == boar[gene] and wolf[gene] != boar[gene]:
				from_b += 1
	assert_true(from_a > 30 and from_b > 30, "parts from wolf %d, boar %d" % [from_a, from_b])


func test_mutation_rate_reasonable() -> void:
	var a := Genome.random("cervo", _rng(5))
	var b := Genome.random("cervo", _rng(6))
	var mutated := 0
	var total := 0
	for s in 200:
		var c := Genome.cross(a, b, _rng(500 + s))
		for gene in PART_GENES:
			total += 1
			if c[gene] != a[gene] and c[gene] != b[gene]:
				mutated += 1
	var rate := float(mutated) / total
	assert_true(rate > 0.0 and rate < 0.15, "part mutation rate %.3f" % rate)


func test_compatibility() -> void:
	var wolf := Genome.random("lobo", _rng(7))
	var wolf2 := Genome.random("lobo", _rng(8))
	var howler := Genome.random("uivante", _rng(9))
	var deer := Genome.random("cervo", _rng(10))
	assert_eq(Genome.compatibility(wolf, wolf2), 1.0)
	assert_eq(Genome.compatibility(wolf, howler), GameConstants.HYBRID_COMPATIBILITY)
	assert_eq(Genome.compatibility(wolf, deer), 0.0)


func test_display_names() -> void:
	var wolf := Genome.random("lobo", _rng(11))
	assert_eq(Genome.display_name(wolf), "Lobo")
	var boar := Genome.random("javali", _rng(12))
	var child := Genome.cross(wolf, boar, _rng(13))
	assert_eq(Genome.display_name(child), "Lobo-javali")
