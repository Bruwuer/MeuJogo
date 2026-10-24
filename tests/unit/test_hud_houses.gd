extends GameTest

const P := GameConstants.Profession
const TR := GameConstants.Tradition
const G := GameConstants.Goal
const B := GameConstants.Building

var s := WorldState.new()
var k: Dictionary


func _init() -> void:
	k = s.add_kingdom("Ravmia", Color.RED, Vector3(100, 0, 100), -1)


func _p(name: String, female: bool, age: float, parents := []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.female = female
	p.age = age
	var rec := s.add_person(p, k.center, k.id)
	rec.status = "resident"
	rec.parents = parents
	return rec


func _house(head: Dictionary, tradition: int) -> Dictionary:
	var f := s.add_family(head.surname, Crest.generate(RandomNumberGenerator.new(), []), k.id, head.id, 0.0)
	f.house_init = true
	f.tradition = tradition
	head.family_id = f.id
	return f


func test_family_rows_show_the_house() -> void:
	var a := _p("Ana", true, 40.0)
	var f := _house(a, TR.FARMERS)
	f.wealth = 123.0
	f.plots = [Rect2(0, 0, 8, 8), Rect2(8, 0, 8, 8)]
	f.skill = {P.FARMER: 150.0}
	f.goal = {kind = G.LAND, target_id = -1}
	var home := s.add_building(B.HOUSE, k.center, 0, Color.WHITE, a.id)
	home.house_level = 1
	a.home_id = home.id
	var text: String = PeopleManager.family_rows(s, k)[0].text
	assert_true(text.count("\n") <= 1, "two lines per House at most: %s" % text)
	for part in ["Lavradores", "riqueza 123", "2 lotes", "casa de pedra", "referência em agricultor", "quer conseguir mais terra"]:
		assert_true(text.contains(part), "row lacks '%s': %s" % [part, text])


func test_rows_sorted_by_prestige() -> void:
	var a := _p("Ana", true, 40.0)
	var poor := _house(a, TR.FARMERS)
	var b := _p("Bento", false, 40.0)
	var rich := _house(b, TR.MERCHANTS)
	poor.prestige = 0.5
	rich.prestige = 4.0
	var rows := PeopleManager.family_rows(s, k)
	assert_true((rows[0].text as String).contains(rich.surname), "the most prestigious House first")


func test_card_shows_kin_vocation_and_house_goal() -> void:
	var g := _p("Avô", false, 70.0)
	var dad := _p("Duarte", false, 45.0, [g.id])
	var aunt := _p("Leonor", true, 44.0, [g.id])
	var martim := _p("Martim", false, 20.0, [dad.id])
	_p("Joana", true, 19.0, [aunt.id])
	var f := _house(dad, TR.WARRIORS)
	martim.family_id = f.id
	martim.profession = P.GUARD
	martim.vocation = P.FARMER
	martim.conflict = true
	f.goal = {kind = G.HEIR, target_id = -1}
	var card := PeopleManager.card_text(martim, s)
	assert_true(card.contains("primo de Joana"), card)
	assert_true(card.contains("sobrinho de Leonor"), card)
	assert_true(card.contains("Sonha ser agricultor"), card)
	assert_true(card.contains("contra a vontade da Casa"), card)
	assert_true(card.contains("A Casa quer: formar um herdeiro no ofício"), card)


func test_chronicle_lines() -> void:
	s.chronicle_add(24.0 * 2 + 14.0, "A Casa Vale tomou posse de um lote", k.id)
	s.chronicle_add(24.0 * 3 + 9.0, "Martim fugiu da Casa Ferreira durante a noite", k.id)
	s.chronicle_add(10.0, "segredo", k.id, false)
	var lines := Hud.chronicle_lines(s, k, 10)
	assert_eq(lines.size(), 2)
	assert_eq(lines[0], "Dia 3, 9h — Martim fugiu da Casa Ferreira durante a noite", "newest first (game hours already count from day 1)")
	assert_eq(lines[1], "Dia 2, 14h — A Casa Vale tomou posse de um lote")
