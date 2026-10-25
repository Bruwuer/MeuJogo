class_name MerchantSim
extends RefCounted
## Wandering merchants (stage 10), run by VillageSim once per hour after every kingdom: now and
## then a merchant with a pack appears at the map edge and walks from seat to seat (the nearest
## first), trades with each kingdom's stock when there (a deed: walking, then talking business),
## and walks off the map after the last stop. Offscreen the walk is summarized like any deed.

const R := GameConstants.Res

var _state: WorldState
var _houses: HouseSim
var _gen: TerrainGenerator
var _hour := 0.0


func setup(state: WorldState, houses: HouseSim) -> void:
	_state = state
	_houses = houses
	houses.deed_handlers.append(complete_deed)


func set_terrain(gen: TerrainGenerator) -> void:
	_gen = gen


func tick_hour(hour: float) -> void:
	_hour = hour
	if _state.next_merchant_hour < 0.0:
		_state.next_merchant_hour = hour + GameConstants.MERCHANT_FIRST_HOURS
	if hour >= _state.next_merchant_hour and not _state.kingdoms().is_empty():
		_state.next_merchant_hour = hour + GameConstants.MERCHANT_EVERY_HOURS
		if _merchants().size() < GameConstants.MERCHANT_MAX:
			spawn(hour)
	for m in _merchants():
		var deed: Dictionary = m.get("deed", {})
		if deed.is_empty():
			_next_stop(m)
		elif Deeds.expired(deed, hour) and _houses.has_node.call(m.id):
			_next_stop(m) # never got there on screen: on to the next seat
		elif Deeds.is_due(deed, hour) and not _houses.has_node.call(m.id):
			_houses.complete_deed(_state.kingdom(int(m.kingdom_id)), m, [], hour)


func _merchants() -> Array[Dictionary]:
	return _state.all_people().filter(func(p: Dictionary) -> bool: return p.status == "merchant")


## A merchant appears at the map edge with goods and coins, bound for the nearest seats.
func spawn(hour: float) -> Dictionary:
	_hour = hour
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "merchant", int(hour)])
	var size := ChunkMath.playable_size()
	var e := GameConstants.MERCHANT_EDGE
	var along := rng.randf_range(e, size - e)
	var pos: Vector3 = [Vector3(along, 0, e), Vector3(along, 0, size - e), Vector3(e, 0, along),
			Vector3(size - e, 0, along)][rng.randi() % 4]
	if _gen:
		pos.y = _gen.height_at(pos.x, pos.z)
	var stops := _state.kingdoms().duplicate()
	stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return pos.distance_squared_to(a.center) < pos.distance_squared_to(b.center))
	var p := PersonGen.generate(rng, 0.0, GameConstants.Profession.MERCHANT)
	p.age = rng.randf_range(28.0, 50.0)
	var m := _state.add_person(p, pos, int(stops[0].id), hour)
	m.status = "merchant"
	m.route = stops.slice(0, GameConstants.MERCHANT_STOPS).map(func(k: Dictionary) -> int: return k.id)
	m.goods = GameConstants.MERCHANT_GOODS.duplicate()
	m.coins = GameConstants.MERCHANT_COINS
	_next_stop(m)
	return m


## Bound for the next seat on the route, or off the map when the route is done.
func _next_stop(m: Dictionary) -> void:
	var route: Array = m.route
	if route.is_empty():
		m.status = "leaving"
		m.deed = {}
		return
	var k := _state.kingdom(int(route.pop_front()))
	if k.is_empty():
		return
	m.kingdom_id = k.id
	var seat := _state.building(int(k.seat_id))
	var at: Vector3 = PeopleManager.door_of(seat) if not seat.is_empty() else k.center
	# The business starts when the walk there would be over (offscreen it is settled then); on screen
	# the merchant heads for that seat meanwhile.
	var walk := Vector2(at.x - m.pos.x, at.z - m.pos.z).length() / GameConstants.REALM_WALK_M_PER_HOUR
	var start := _hour + walk
	var deed := Deeds.make("trade", at, GameConstants.PERSON_ARRIVE * GameConstants.GOV_REACH_MULT, start,
			start + GameConstants.MERCHANT_WAIT_HOURS, GameConstants.MERCHANT_TRADE_SEC, {kingdom_id = k.id})
	deed.anim = GameConstants.ANIM_TALK
	m.deed = deed


func complete_deed(_k: Dictionary, p: Dictionary, deed: Dictionary, _seen: Array, hour: float) -> bool:
	if String(deed.kind) != "trade":
		return false
	_hour = hour
	var k := _state.kingdom(int((deed.data as Dictionary).get("kingdom_id", -1)))
	if not k.is_empty():
		var done := MerchantRules.kingdom_trade(_state, p, k)
		_state.chronicle_add(hour, GameConstants.MERCHANT_MSG_ARRIVED % [PersonGen.full_name(p), k.name] +
				(": " + done if done != "" else ""), k.id)
	_next_stop(p)
	return true
