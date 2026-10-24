class_name KingdomNames
extends RefCounted
## Invented, Portuguese-flavored medieval names ("Valdemar", "Torvela", "Aurímia"...),
## deterministic for a (seed, index) pair.

const _STARTS := ["Val", "Tor", "Aur", "Bel", "Cas", "Dor", "Mar", "Ser", "Al", "Vel", "Gal", "Lor",
		"Fer", "Rav", "Ond", "Brag", "Mon", "Cal", "Ter", "Sol"]
const _MIDDLES := ["de", "ve", "ri", "a", "or", "an", "e", "ín", "u", "el"]
const _ENDS := ["mar", "la", "mia", "nha", "ra", "dor", "lis", "ria", "vel", "gar", "do", "sa", "nor", "via"]
const _MIDDLE_CHANCE := 0.55


static func generate(seed: int, index: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("kingdom_%d_%d" % [seed, index])
	var name: String = _STARTS[rng.randi() % _STARTS.size()]
	if rng.randf() < _MIDDLE_CHANCE:
		name += _MIDDLES[rng.randi() % _MIDDLES.size()]
	name += _ENDS[rng.randi() % _ENDS.size()]
	return name
