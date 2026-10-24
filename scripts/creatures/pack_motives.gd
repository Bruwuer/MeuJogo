class_name PackMotives
extends RefCounted
## Why a pack would threaten a kingdom. Each pack carries four motives (0..1): hunger, territory,
## grudge and cubs_alarm. Night only changes WHEN a pack acts; without a motive above the
## threshold there is no raid.

const MOTIVES := ["hunger", "territory", "grudge", "cubs"]


## ctx: {prey_count, buildings_in_territory, player_near_den, cubs}
static func update(pack: Dictionary, ctx: Dictionary, hours: float) -> void:
	var prey_share := clampf(float(ctx.get("prey_count", 0)) / GameConstants.PREY_ENOUGH, 0.0, 1.0)
	pack.hunger = clampf(pack.hunger + (GameConstants.HUNGER_RATE - GameConstants.PACK_FEED_RATE * prey_share) * hours, 0.0, 1.0)
	pack.territory = clampf(ctx.get("buildings_in_territory", 0) * GameConstants.TERRITORY_PER_BUILDING, 0.0, 1.0)
	pack.grudge = maxf(0.0, pack.grudge - GameConstants.GRUDGE_DECAY_PER_DAY / 24.0 * hours)
	if ctx.get("player_near_den", false) and ctx.get("cubs", 0) > 0:
		pack.cubs_alarm = 1.0
	else:
		pack.cubs_alarm = maxf(0.0, pack.cubs_alarm - GameConstants.CUBS_ALARM_DECAY * hours)


## A member was killed (or, with `hurt_only`, wounded) by the player.
static func add_grudge(pack: Dictionary, was_cub: bool, hurt_only := false) -> void:
	var amount := GameConstants.GRUDGE_PER_HURT if hurt_only else (GameConstants.GRUDGE_PER_CUB if was_cub else GameConstants.GRUDGE_PER_KILL)
	pack.grudge = minf(1.0, pack.grudge + amount)


## Only carnivores and territorial species raid; herbivores never raid out of hunger.
static func can_raid(pack: Dictionary) -> bool:
	var sp: Dictionary = GameConstants.SPECIES[pack.species]
	return sp.diet == GameConstants.Diet.CARNIVORE or sp.territorial


static func weighted(pack: Dictionary, motive: String) -> float:
	var sp: Dictionary = GameConstants.SPECIES[pack.species]
	if motive == "hunger" and sp.diet != GameConstants.Diet.CARNIVORE:
		return 0.0
	var value: float = pack.cubs_alarm if motive == "cubs" else pack[motive]
	return value * GameConstants.MOTIVE_WEIGHTS[motive]


static func dominant(pack: Dictionary) -> String:
	var best := "hunger"
	var best_v := -1.0
	for m: String in MOTIVES:
		var v := weighted(pack, m)
		if v > best_v:
			best = m
			best_v = v
	return best


static func raid_score(pack: Dictionary, aggression: float) -> float:
	if not can_raid(pack):
		return 0.0
	return weighted(pack, dominant(pack)) * (0.5 + aggression)


static func wants_raid(pack: Dictionary, aggression: float) -> bool:
	return raid_score(pack, aggression) >= GameConstants.RAID_THRESHOLD


static func species_plural(species: String) -> String:
	return (GameConstants.SPECIES[species].name as String).to_lower() + "s"


static func message(pack: Dictionary, kingdom_name: String) -> String:
	return GameConstants.RAID_MESSAGES[dominant(pack)] % [species_plural(pack.species), kingdom_name]


## Motives calm down after a raid; the pack goes home.
static func after_raid(pack: Dictionary, now_hours: float) -> void:
	pack.hunger = maxf(0.0, pack.hunger - GameConstants.RAID_SATED_HUNGER)
	pack.grudge *= GameConstants.RAID_GRUDGE_KEEP
	pack.cubs_alarm = 0.0
	pack.raid_kingdom = -1
	pack.next_raid_hour = now_hours + GameConstants.RAID_COOLDOWN_HOURS
