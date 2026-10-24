class_name Health
extends RefCounted
## Hit points shared by the player and creatures.

signal damaged(amount: float, source: Object)
signal died(source: Object)

var max_hp: float
var hp: float


func _init(max_value := 100.0, current := -1.0) -> void:
	max_hp = max_value
	hp = max_value if current < 0.0 else minf(current, max_value)


## Returns true when this hit killed it.
func damage(amount: float, source: Object = null) -> bool:
	if is_dead() or amount <= 0.0:
		return false
	hp = maxf(0.0, hp - amount)
	damaged.emit(amount, source)
	if hp == 0.0:
		died.emit(source)
		return true
	return false


func heal(amount: float) -> void:
	if not is_dead():
		hp = minf(max_hp, hp + amount)


func is_dead() -> bool:
	return hp <= 0.0


func ratio() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0
