class_name Crest
extends RefCounted
## A family's coat of arms as a plain Dictionary {pattern, field, second, charge, charge_tincture}
## (enums CrestPattern / CrestCharge, tinctures are indexes into TINCTURES). It is drawn pixel by
## pixel into a small Image (a shield with a pointed base, transparent outside), which becomes the
## texture of the HUD icons and of the banner beside a family's house. No external assets.

const CP := GameConstants.CrestPattern
const CC := GameConstants.CrestCharge
const _SPLIT_Y := 22.0 ## Pixel row where the shield's straight sides start curving to the point.
const _CHARGE_AT := Vector2(16.0, 18.0)
const _CHARGE_R := 6.0

static var _textures: Dictionary = {} # key -> ImageTexture
static var _materials: Dictionary = {} # key -> StandardMaterial3D


## A new crest not equal to any in `avoid` (gives up after CREST_TRIES and returns the last one).
static func generate(rng: RandomNumberGenerator, avoid: Array) -> Dictionary:
	var c := {}
	for i in GameConstants.CREST_TRIES:
		c = _random(rng)
		if not _taken(c, avoid):
			return c
	return c


## A cadet branch: same shield, a different charge or charge tincture.
static func derive(parent: Dictionary, rng: RandomNumberGenerator, avoid: Array) -> Dictionary:
	var c := parent.duplicate()
	for i in GameConstants.CREST_TRIES:
		c = parent.duplicate()
		if rng.randf() < 0.5 or parent.charge == CC.NONE:
			c.charge = 1 + rng.randi() % (CC.size() - 1)
		c.charge_tincture = _contrast(c.field, c.second, rng)
		if not same(c, parent) and not _taken(c, avoid):
			return c
	return c


## Someone who broke away in anger keeps only one tincture of the old arms.
static func rival(parent: Dictionary, rng: RandomNumberGenerator, avoid: Array) -> Dictionary:
	var c := {}
	for i in GameConstants.CREST_TRIES * 2:
		c = _random(rng)
		var keeps := [c.field, c.second].has(parent.field) or [c.field, c.second].has(parent.second)
		if keeps and c.pattern != parent.pattern and not same(c, parent) and not _taken(c, avoid):
			return c
	return c


static func key(c: Dictionary) -> String:
	return "%d-%d-%d-%d-%d" % [c.pattern, c.field, c.second, c.charge, c.charge_tincture]


static func same(a: Dictionary, b: Dictionary) -> bool:
	return key(a) == key(b)


## Color of the arms at (u, v) in 0..1 (v down); transparent outside the shield. No border.
static func color_at(c: Dictionary, u: float, v: float) -> Color:
	var size := Vector2(GameConstants.CREST_SIZE)
	var px := u * size.x
	var py := v * size.y
	if not _inside(px, py, size):
		return Color(0, 0, 0, 0)
	var t: int = c.second if _second_area(c.pattern, u, v) else c.field
	if c.charge != CC.NONE and _in_charge(c.charge, px - _CHARGE_AT.x, py - _CHARGE_AT.y):
		t = c.charge_tincture
	return GameConstants.TINCTURES[t][1]


static func image(c: Dictionary) -> Image:
	var size := GameConstants.CREST_SIZE
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var fsize := Vector2(size)
	for y in size.y:
		for x in size.x:
			var col := color_at(c, (x + 0.5) / fsize.x, (y + 0.5) / fsize.y)
			if col.a > 0.0 and _on_edge(x, y, fsize):
				col = GameConstants.CREST_BORDER
			img.set_pixel(x, y, col)
	return img


static func texture(c: Dictionary) -> ImageTexture:
	var k := key(c)
	if not _textures.has(k):
		_textures[k] = ImageTexture.create_from_image(image(c))
	return _textures[k]


## Material for the banner cloth: pixel-crisp, cut out at the shield edge, seen from both sides.
static func material(c: Dictionary) -> StandardMaterial3D:
	var k := key(c)
	if not _materials.has(k):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture(c)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.9
		_materials[k] = mat
	return _materials[k]


## "azul e ouro, partido, com uma estrela de prata".
static func describe(c: Dictionary) -> String:
	var tname := func(t: int) -> String: return GameConstants.TINCTURES[t][0]
	var text: String
	if c.pattern == CP.PLAIN:
		text = "%s pleno" % tname.call(c.field)
	else:
		text = "%s e %s, %s" % [tname.call(c.field), tname.call(c.second), GameConstants.CREST_PATTERN_NAMES[c.pattern]]
	if c.charge != CC.NONE:
		text += ", com %s de %s" % [GameConstants.CREST_CHARGE_NAMES[c.charge], tname.call(c.charge_tincture)]
	return text


static func _random(rng: RandomNumberGenerator) -> Dictionary:
	var pattern := rng.randi() % CP.size()
	var metal := _pick(rng, true)
	var colour := _pick(rng, false)
	var field := metal if rng.randf() < 0.5 else colour
	var second := colour if field == metal else metal
	if pattern == CP.PLAIN:
		second = field
	var charge := rng.randi() % CC.size()
	if pattern == CP.PLAIN and charge == CC.NONE:
		charge = 1 + rng.randi() % (CC.size() - 1)
	var c := {pattern = pattern, field = field, second = second, charge = charge, charge_tincture = field}
	c.charge_tincture = _contrast(field, second, rng) if charge != CC.NONE else field
	return c


## A tincture of the other class than the field (metal on colour), different from `second` when it can.
static func _contrast(field: int, second: int, rng: RandomNumberGenerator) -> int:
	var want_metal: bool = not GameConstants.TINCTURES[field][2]
	var options: Array[int] = []
	for i in GameConstants.TINCTURES.size():
		if GameConstants.TINCTURES[i][2] == want_metal and i != second:
			options.append(i)
	if options.is_empty():
		return _pick(rng, want_metal)
	return options[rng.randi() % options.size()]


static func _pick(rng: RandomNumberGenerator, metal: bool) -> int:
	var options: Array[int] = []
	for i in GameConstants.TINCTURES.size():
		if GameConstants.TINCTURES[i][2] == metal:
			options.append(i)
	return options[rng.randi() % options.size()]


static func _taken(c: Dictionary, avoid: Array) -> bool:
	return avoid.any(func(o: Dictionary) -> bool: return same(c, o))


## Straight sides down to _SPLIT_Y, then a curve closing into a point at the bottom.
static func _inside(px: float, py: float, size: Vector2) -> bool:
	if px < 0.0 or py < 0.0 or px >= size.x or py >= size.y:
		return false
	var half := size.x * 0.5
	if py <= _SPLIT_Y:
		return true
	var t := (py - _SPLIT_Y) / (size.y - _SPLIT_Y)
	return absf(px - half) <= half * (1.0 - t * t)


static func _on_edge(x: int, y: int, size: Vector2) -> bool:
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not _inside(x + d.x + 0.5, y + d.y + 0.5, size):
			return true
	return false


static func _second_area(pattern: int, u: float, v: float) -> bool:
	match pattern:
		CP.PALE:
			return u >= 0.5
		CP.FESS:
			return v >= 0.5
		CP.BEND:
			return v > u
		CP.QUARTERLY:
			return (u >= 0.5) != (v >= 0.5)
		CP.CHEVRON:
			return v > 0.45 + absf(u - 0.5) * 0.9
	return false


## Charge shapes around the centre point (pixel offsets).
static func _in_charge(charge: int, dx: float, dy: float) -> bool:
	var r := Vector2(dx, dy).length()
	match charge:
		CC.ROUNDEL:
			return r <= _CHARGE_R
		CC.CROSS:
			return (absf(dx) <= 1.6 and absf(dy) <= _CHARGE_R + 1.0) or (absf(dy) <= 1.6 and absf(dx) <= _CHARGE_R + 1.0)
		CC.LOZENGE:
			return absf(dx) / (_CHARGE_R - 1.0) + absf(dy) / (_CHARGE_R + 2.0) <= 1.0
		CC.STAR:
			var a := fposmod(atan2(dx, -dy), TAU / 5.0) - TAU / 10.0
			var limit := lerpf(_CHARGE_R + 1.5, _CHARGE_R * 0.45, absf(a) / (TAU / 10.0))
			return r <= limit
		CC.CRESCENT:
			return r <= _CHARGE_R and Vector2(dx, dy + 2.5).length() > _CHARGE_R - 1.0
	return false
