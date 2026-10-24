extends GameTest

const CP := GameConstants.CrestPattern
const CC := GameConstants.CrestCharge


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _metal(t: int) -> bool:
	return GameConstants.TINCTURES[t][2]


func _color(t: int) -> Color:
	return GameConstants.TINCTURES[t][1]


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02 and absf(a.a - b.a) < 0.02


func test_generate_deterministic() -> void:
	var a := Crest.generate(_rng(5), [])
	var b := Crest.generate(_rng(5), [])
	assert_true(Crest.same(a, b), "same seed, same crest")
	for key in ["pattern", "field", "second", "charge", "charge_tincture"]:
		assert_true(a.has(key), "has %s" % key)


func test_metal_on_colour() -> void:
	for s in 60:
		var c := Crest.generate(_rng(s), [])
		if c.pattern == CP.PLAIN:
			assert_eq(c.second, c.field, "plain has one tincture")
			assert_true(c.charge != CC.NONE, "a plain shield always has a charge")
		else:
			assert_true(_metal(c.field) != _metal(c.second), "one metal, one colour (seed %d)" % s)
		if c.charge != CC.NONE:
			assert_true(_metal(c.charge_tincture) != _metal(c.field), "charge contrasts with the field (seed %d)" % s)


func test_avoids_existing() -> void:
	var r := _rng(1)
	var made: Array = []
	for i in 20:
		var c := Crest.generate(r, made)
		for other in made:
			assert_true(not Crest.same(c, other), "crest %d repeats" % i)
		made.append(c)


func test_derive_changes_only_charge() -> void:
	var r := _rng(3)
	var parent := Crest.generate(r, [])
	var child := Crest.derive(parent, r, [parent])
	assert_true(not Crest.same(child, parent), "differs")
	assert_eq(child.pattern, parent.pattern)
	assert_eq(child.field, parent.field)
	assert_eq(child.second, parent.second)


func test_rival_keeps_one_tincture() -> void:
	var r := _rng(9)
	for i in 10:
		var parent := Crest.generate(r, [])
		var c := Crest.rival(parent, r, [parent])
		assert_true(not Crest.same(c, parent), "differs")
		var mine := [c.field, c.second]
		assert_true(mine.has(parent.field) or mine.has(parent.second), "keeps a tincture")


func test_image_colours_and_mask() -> void:
	var c := {pattern = CP.PALE, field = 0, second = 2, charge = CC.NONE, charge_tincture = 0}
	var img := Crest.image(c)
	assert_eq(img.get_size(), GameConstants.CREST_SIZE)
	assert_true(_close(img.get_pixel(8, 15), _color(0)), "left half is the field")
	assert_true(_close(img.get_pixel(24, 15), _color(2)), "right half is the second")
	assert_true(img.get_pixel(1, 39).a < 0.01, "outside the point is transparent")
	assert_true(img.get_pixel(16, 38).a > 0.99, "the point itself is drawn")


func test_charge_drawn_at_centre() -> void:
	var c := {pattern = CP.FESS, field = 3, second = 1, charge = CC.ROUNDEL, charge_tincture = 0}
	var img := Crest.image(c)
	assert_true(_close(img.get_pixel(16, 18), _color(0)), "roundel in the middle")
	assert_true(_close(img.get_pixel(4, 6), _color(3)), "field around it")


func test_describe_portuguese() -> void:
	var c := {pattern = CP.PALE, field = 3, second = 0, charge = CC.STAR, charge_tincture = 1}
	var text := Crest.describe(c)
	assert_true(text.contains("azul") and text.contains("ouro"), text)
	assert_true(text.contains("partido"), text)
	assert_true(text.contains("estrela") and text.contains("prata"), text)


func test_texture_cached() -> void:
	var c := Crest.generate(_rng(2), [])
	assert_true(Crest.texture(c) == Crest.texture(c.duplicate()), "one texture per crest")
	assert_true(Crest.material(c) == Crest.material(c), "one material per crest")
	assert_eq(Crest.material(c).albedo_texture, Crest.texture(c))
