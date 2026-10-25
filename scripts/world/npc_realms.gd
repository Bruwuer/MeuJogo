class_name NpcRealms
extends RefCounted
## The NPC kingdoms a world starts with (stage 9): placed once, far from where the player starts and
## from each other, each with its seat, flag, campfire, farm, two houses and two families. Nobody
## decided this: it is the world that was already there. The first ruler is crowned by GovSim.

const B := GameConstants.Building
const P := GameConstants.Profession


## Places the NPC kingdoms unless the world already has them. `avoid`: points to keep away from
## (the player's spawn, the player's kingdoms). Returns the new kingdoms.
static func seed(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, avoid: Array) -> Array[Dictionary]:
	var made: Array[Dictionary] = []
	if state.realms_seeded:
		return made
	state.realms_seeded = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.seed, "realms"])
	for i in GameConstants.REALM_NPC_START:
		var center := _place(state, gen, scatter, avoid, rng)
		if center.x < 0.0:
			break
		made.append(_found(state, gen, scatter, center, rng))
	return made


## A seat spot on the map, away from the edge, from `avoid` and from every kingdom; (-1, -1, -1)
## when none is found.
static func _place(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, avoid: Array,
		rng: RandomNumberGenerator, clear_bushes := true) -> Vector3:
	var margin := GameConstants.KINGDOM_RADIUS + GameConstants.REALM_EDGE_MARGIN
	var size := ChunkMath.playable_size()
	var others: Array = avoid.duplicate()
	for k in state.kingdoms():
		others.append(k.center)
	for t in GameConstants.REALM_SEED_TRIES:
		var pos := BuildRules.snap(Vector3(rng.randf_range(margin, size - margin), 0.0, rng.randf_range(margin, size - margin)))
		if others.any(func(o: Vector3) -> bool: return Vector2(o.x - pos.x, o.z - pos.z).length() < GameConstants.REALM_MIN_GAP):
			continue
		var check := BuildRules.check_site(B.CABIN, pos, 0, gen, scatter, state, [])
		if check.ok:
			if clear_bushes:
				for bush: Dictionary in check.bushes:
					state.mark_removed(bush.chunk, bush.id)
			return Vector3(pos.x, check.y, pos.z)
	return Vector3(-1, -1, -1)


static func _found(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, center: Vector3,
		rng: RandomNumberGenerator) -> Dictionary:
	var index := state.kingdoms().size()
	var color := KingdomNames.color(state.seed, index)
	var seat := state.add_building(B.CABIN, center, 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	var flag_pos := center + GameConstants.FLAG_OFFSET # the seat faces +Z (rot 0)
	state.add_building(B.FLAG, Vector3(flag_pos.x, gen.height_at(flag_pos.x, flag_pos.z), flag_pos.z), 0, color,
			GameConstants.OWNER_KINGDOM)
	var k := state.add_kingdom(KingdomNames.generate(state.seed, index), color, center, seat.id, "npc")
	k.ruler_id = GameConstants.GOV_NOBODY
	k.decrees.guards = GameConstants.REALM_NPC_GUARDS
	for type in [B.CAMPFIRE, B.FARM]:
		_build(state, gen, scatter, k, type, GameConstants.OWNER_KINGDOM, rng)
	var surnames: Array = GameConstants.SURNAMES.duplicate()
	for fam in GameConstants.REALM_NPC_FAMILIES:
		var home := _build(state, gen, scatter, k, B.HOUSE, GameConstants.OWNER_KINGDOM, rng)
		var surname: String = surnames.pop_at(rng.randi() % surnames.size())
		_family(state, k, home, surname, GameConstants.REALM_NPC_TRADES[fam], rng)
	k.people_ever = state.residents(k.id).size()
	return k


static func _build(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, k: Dictionary, type: int,
		owner: int, rng: RandomNumberGenerator) -> Dictionary:
	var spot := VillageRules.pick_site(type, k, state, gen, scatter, [], rng)
	if not spot.ok:
		return {}
	for bush: Dictionary in spot.bushes:
		state.mark_removed(bush.chunk, bush.id)
	var rec := state.add_building(type, spot.pos, spot.rot, Color.WHITE, owner)
	rec.kingdom_id = k.id
	return rec


## A couple and their grown child (`trades`: the father's, the mother's and the child's), at home.
static func _family(state: WorldState, k: Dictionary, home: Dictionary, surname: String, trades: Array,
		rng: RandomNumberGenerator) -> void:
	var members: Array[Dictionary] = []
	for i in 3:
		var p := PersonGen.generate(rng, 0.0, int(trades[i]))
		p.surname = surname
		if bool(p.female) != (i == 1): # the mother is a woman, the father and the son are men
			p.female = i == 1
			p.name = PersonGen.name_for(p.female, rng)
		var ages: Vector2 = GameConstants.REALM_NPC_AGES[i]
		p.age = rng.randf_range(ages.x, ages.y)
		var rec := state.add_person(p, home.get("pos", k.center), k.id)
		rec.status = "resident"
		rec.opinion = 0.0
		rec.home_id = int(home.get("id", -1))
		members.append(rec)
	members[0].spouse_id = members[1].id
	members[1].spouse_id = members[0].id
	members[2].parents = [members[0].id, members[1].id]
	if not home.is_empty():
		home.owner = members[0].id
