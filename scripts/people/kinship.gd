class_name Kinship
extends RefCounted
## Family tree queries over WorldState: parents (biological or adoptive), children, siblings,
## grandparents, uncles/aunts, nephews/nieces and cousins. Works through people who died or left
## (WorldState.ancestry keeps their parents).

const _WORDS := {
	"parent": ["pai", "mãe"], "child": ["filho", "filha"], "sibling": ["irmão", "irmã"],
	"grandparent": ["avô", "avó"], "grandchild": ["neto", "neta"], "uncle": ["tio", "tia"],
	"nephew": ["sobrinho", "sobrinha"], "cousin": ["primo", "prima"], "spouse": ["marido", "esposa"],
}


## Parents of `id`: biological ones plus adoptive ones (no duplicates).
static func parents_of(state: WorldState, id: int) -> Array[int]:
	var rec := state.ancestry(id)
	var out: Array[int] = []
	for key in ["parents", "adopted_by"]:
		for pid in rec.get(key, []):
			if not out.has(int(pid)):
				out.append(int(pid))
	return out


static func children_of(state: WorldState, id: int) -> Array[int]:
	var out: Array[int] = []
	for p in state.all_people():
		if parents_of(state, p.id).has(id):
			out.append(p.id)
	return out


static func siblings_of(state: WorldState, id: int) -> Array[int]:
	var out: Array[int] = []
	var mine := parents_of(state, id)
	if mine.is_empty():
		return out
	for p in state.all_people():
		if p.id != id and parents_of(state, p.id).any(func(x: int) -> bool: return mine.has(x)):
			out.append(p.id)
	return out


static func grandparents_of(state: WorldState, id: int) -> Array[int]:
	var out: Array[int] = []
	for par in parents_of(state, id):
		for g in parents_of(state, par):
			if not out.has(g):
				out.append(g)
	return out


## What `a` is to `b` ("pai", "prima", "esposa"...) or "" when not close kin.
static func relation_word(state: WorldState, a: Dictionary, b: Dictionary) -> String:
	var kind := relation_kind(state, a.id, b.id)
	if kind == "":
		return ""
	return _WORDS[kind][1 if a.get("female", false) else 0]


## "parent", "child", "sibling", "grandparent", "grandchild", "uncle", "nephew", "cousin", "spouse"
## or "".
static func relation_kind(state: WorldState, a: int, b: int) -> String:
	if a == b:
		return ""
	var pa := state.person(a)
	if not pa.is_empty() and int(pa.get("spouse_id", -1)) == b:
		return "spouse"
	var a_parents := parents_of(state, a)
	var b_parents := parents_of(state, b)
	if b_parents.has(a):
		return "parent"
	if a_parents.has(b):
		return "child"
	if _share(a_parents, b_parents):
		return "sibling"
	var a_grand := _grand(state, a_parents)
	var b_grand := _grand(state, b_parents)
	if b_grand.has(a):
		return "grandparent"
	if a_grand.has(b):
		return "grandchild"
	if b_parents.any(func(x: int) -> bool: return _share(parents_of(state, x), a_parents)):
		return "uncle"
	if a_parents.any(func(x: int) -> bool: return _share(parents_of(state, x), b_parents)):
		return "nephew"
	if _share(a_grand, b_grand):
		return "cousin"
	return ""


## Parents, children, siblings, grandparents, uncles/nephews and first cousins (marriage taboo).
static func is_close_kin(state: WorldState, a: Dictionary, b: Dictionary) -> bool:
	var kind := relation_kind(state, a.id, b.id)
	return kind != "" and kind != "spouse"


static func _grand(state: WorldState, parents: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for par in parents:
		for g in parents_of(state, par):
			if not out.has(g):
				out.append(g)
	return out


static func _share(a: Array[int], b: Array[int]) -> bool:
	return a.any(func(x: int) -> bool: return b.has(x))
