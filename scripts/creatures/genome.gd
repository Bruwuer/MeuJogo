class_name Genome
extends RefCounted
## A creature's genes as a plain Dictionary (easy to save). Body-part genes pick the Blender parts
## the creature is assembled from, so cubs visibly inherit from both parents.

const PART_GENES := ["body", "head", "legs", "tail", "extra"]
const NUMERIC_GENES := ["size", "aggression", "speed", "max_hp", "damage", "perception"]
const PICKED_GENES := ["color_a", "color_b", "diet", "nocturnal", "territorial", "pack"]
const HYBRID := "hibrido"


static func random(species: String, rng: RandomNumberGenerator) -> Dictionary:
	var sp: Dictionary = GameConstants.SPECIES[species]
	return {
		species = species,
		lineage = PackedStringArray([species]),
		body = sp.body, head = sp.head, legs = sp.legs, tail = sp.tail, extra = sp.extra,
		size = rng.randf_range(sp.size.x, sp.size.y),
		color_a = _jitter(sp.color_a, sp.color_jitter, rng),
		color_b = _jitter(sp.color_b, sp.color_jitter, rng),
		diet = sp.diet,
		aggression = rng.randf_range(sp.aggression.x, sp.aggression.y),
		pack = rng.randi_range(sp.pack.x, sp.pack.y),
		speed = rng.randf_range(sp.speed.x, sp.speed.y),
		max_hp = rng.randf_range(sp.hp.x, sp.hp.y),
		damage = rng.randf_range(sp.damage.x, sp.damage.y),
		perception = sp.perception,
		nocturnal = sp.nocturnal,
		territorial = sp.territorial,
		generation = 0,
	}


## Each gene comes from one parent; any gene may mutate with MUTATION_CHANCE.
static func cross(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var c := {}
	for gene in PART_GENES:
		c[gene] = a[gene] if rng.randf() < 0.5 else b[gene]
		if rng.randf() < GameConstants.MUTATION_CHANCE:
			c[gene] = rng.randi() % part_options(gene)
	for gene in NUMERIC_GENES:
		var v: float = a[gene] if rng.randf() < 0.5 else b[gene]
		if rng.randf() < GameConstants.MUTATION_CHANCE:
			v *= 1.0 + rng.randf_range(-GameConstants.MUTATION_SPREAD, GameConstants.MUTATION_SPREAD)
		c[gene] = v
	for gene in PICKED_GENES:
		c[gene] = a[gene] if rng.randf() < 0.5 else b[gene]
	var lineage := PackedStringArray(a.lineage)
	for s in b.lineage:
		if not lineage.has(s):
			lineage.append(s)
	c.lineage = lineage
	c.species = a.species if a.species == b.species else HYBRID
	c.generation = maxi(a.generation, b.generation) + 1
	return c


## Number of Blender parts available for a part gene (a mutation may pick any of them).
static func part_options(gene: String) -> int:
	match gene:
		"body": return GameConstants.Body.size()
		"head": return GameConstants.Head.size()
		"legs": return GameConstants.Legs.size()
		"tail": return GameConstants.Tail.size()
		_: return GameConstants.Extra.size()


## 1 for the same species, HYBRID_COMPATIBILITY for close kin (same diet and same body or shared
## lineage), 0 otherwise.
static func compatibility(a: Dictionary, b: Dictionary) -> float:
	if a.species == b.species and a.species != HYBRID:
		return 1.0
	if a.diet != b.diet:
		return 0.0
	var shared := Array(a.lineage).any(func(s: String) -> bool: return Array(b.lineage).has(s))
	if a.body == b.body or shared:
		return GameConstants.HYBRID_COMPATIBILITY
	return 0.0


## "Lobo" for a pure species, "Lobo-javali" for a hybrid (first two lineages).
static func display_name(g: Dictionary) -> String:
	var first: String = GameConstants.SPECIES[g.lineage[0]].name
	if g.lineage.size() == 1:
		return first
	return "%s-%s" % [first, (GameConstants.SPECIES[g.lineage[1]].name as String).to_lower()]


static func _jitter(c: Color, amount: float, rng: RandomNumberGenerator) -> Color:
	return Color(clampf(c.r + rng.randf_range(-amount, amount), 0.0, 1.0),
			clampf(c.g + rng.randf_range(-amount, amount), 0.0, 1.0),
			clampf(c.b + rng.randf_range(-amount, amount), 0.0, 1.0))
