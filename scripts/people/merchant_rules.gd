class_name MerchantRules
extends RefCounted
## Pure trade rules of the wandering merchants (stage 10), no scene: what a merchant does with a
## kingdom's stock on arrival and what the player can buy and sell.

const R := GameConstants.Res


## Trade with kingdom `k` on arrival: a hungry kingdom buys food (paying with its most plentiful
## wood or stone), and any big surplus of wood or stone is sold for coins. Returns what happened, in
## words ("" when nothing was traded).
static func kingdom_trade(state: WorldState, m: Dictionary, k: Dictionary) -> String:
	var parts: PackedStringArray = []
	var goods: Dictionary = m.goods
	var snap := VillageRules.snapshot(state, k, 0.0)
	if float(snap.food_days) < GameConstants.MERCHANT_HUNGRY_DAYS and int(goods.get(R.FOOD, 0)) > 0:
		var n := mini(GameConstants.MERCHANT_FOOD_LOT, int(goods[R.FOOD]))
		var pay := SocietySim._most([R.WOOD, R.STONE], func(r: int) -> int: return state.stock_of(k, r))
		var paid := mini(n, state.stock_of(k, pay))
		goods[R.FOOD] = int(goods[R.FOOD]) - n
		state.add_stock(k, R.FOOD, n)
		state.add_stock(k, pay, -paid)
		goods[pay] = int(goods.get(pay, 0)) + paid
		parts.append(GameConstants.MERCHANT_SOLD_FOOD % [n, paid, SocietySim._res_name(pay)])
	for res in [R.WOOD, R.STONE]:
		var extra := state.stock_of(k, res) - GameConstants.MERCHANT_SURPLUS
		if extra <= 0:
			continue
		var n := mini(GameConstants.MERCHANT_BUY_LOT, extra)
		var coins := mini(int(m.coins), n / GameConstants.MERCHANT_SURPLUS_RATE)
		if coins <= 0:
			continue
		state.add_stock(k, res, -n)
		state.add_stock(k, R.COINS, coins)
		goods[res] = int(goods.get(res, 0)) + n
		m.coins = int(m.coins) - coins
		parts.append(GameConstants.MERCHANT_BOUGHT % [n, SocietySim._res_name(res), coins])
	return "; ".join(parts)


## The player trades with merchant `m`: "bread", "arrows" (buy) or "sell_wood". Returns the message
## shown to the player (it is the player's own act).
static func trade(state: WorldState, m: Dictionary, what: String) -> String:
	var goods: Dictionary = m.goods
	match what:
		"bread":
			if int(goods.get(R.BREAD, 0)) <= 0:
				return GameConstants.MERCHANT_OUT % "pão"
			if not state.spend({R.COINS: GameConstants.MERCHANT_BREAD_PRICE}):
				return GameConstants.MERCHANT_NO_COINS % GameConstants.MERCHANT_BREAD_PRICE
			goods[R.BREAD] = int(goods[R.BREAD]) - 1
			m.coins = int(m.coins) + GameConstants.MERCHANT_BREAD_PRICE
			state.add_resource(R.BREAD, 1)
			return GameConstants.MERCHANT_BOUGHT_MSG % ["1 pão", GameConstants.MERCHANT_BREAD_PRICE]
		"arrows":
			if int(goods.get(R.ARROWS, 0)) < GameConstants.MERCHANT_ARROW_LOT:
				return GameConstants.MERCHANT_OUT % "flechas"
			if not state.spend({R.COINS: GameConstants.MERCHANT_ARROW_PRICE}):
				return GameConstants.MERCHANT_NO_COINS % GameConstants.MERCHANT_ARROW_PRICE
			goods[R.ARROWS] = int(goods[R.ARROWS]) - GameConstants.MERCHANT_ARROW_LOT
			m.coins = int(m.coins) + GameConstants.MERCHANT_ARROW_PRICE
			state.add_resource(R.ARROWS, GameConstants.MERCHANT_ARROW_LOT)
			return GameConstants.MERCHANT_BOUGHT_MSG % ["%d flechas" % GameConstants.MERCHANT_ARROW_LOT,
					GameConstants.MERCHANT_ARROW_PRICE]
		"sell_wood":
			if int(m.coins) < GameConstants.MERCHANT_WOOD_PRICE:
				return GameConstants.MERCHANT_BROKE
			if not state.spend({R.WOOD: GameConstants.MERCHANT_SELL_LOT}):
				return GameConstants.MERCHANT_NO_WOOD % GameConstants.MERCHANT_SELL_LOT
			goods[R.WOOD] = int(goods.get(R.WOOD, 0)) + GameConstants.MERCHANT_SELL_LOT
			m.coins = int(m.coins) - GameConstants.MERCHANT_WOOD_PRICE
			state.add_resource(R.COINS, GameConstants.MERCHANT_WOOD_PRICE)
			return GameConstants.MERCHANT_SOLD_MSG % [GameConstants.MERCHANT_SELL_LOT, GameConstants.MERCHANT_WOOD_PRICE]
	return ""
