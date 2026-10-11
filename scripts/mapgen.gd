extends RefCounted
## Генерация островов: Сан-Андреас, бухта Мурлибу и острова Каталины.

const D = preload("res://scripts/defs.gd")
const W := D.W
const H := D.H
const GRASS := D.GRASS
const WATER := D.WATER
const SAND := D.SAND
const HILL := D.HILL
const MOUNTAIN := D.MOUNTAIN
const DRY := D.DRY
const MEADOW := D.MEADOW
## Контур острова — как карта Сан-Андреаса из GTA V (x, y в долях рамки; север сверху).
const SA_SHAPE := [
	Vector2(0.40, 0.00), Vector2(0.52, 0.03), Vector2(0.64, 0.08), Vector2(0.77, 0.12), Vector2(0.89, 0.20),
	Vector2(0.96, 0.30), Vector2(0.98, 0.40), Vector2(0.93, 0.48), Vector2(0.86, 0.55), Vector2(0.81, 0.62),
	Vector2(0.84, 0.70), Vector2(0.80, 0.80), Vector2(0.73, 0.90), Vector2(0.63, 0.97), Vector2(0.50, 1.00),
	Vector2(0.38, 0.98), Vector2(0.27, 0.93), Vector2(0.18, 0.88), Vector2(0.10, 0.84), Vector2(0.07, 0.77),
	Vector2(0.15, 0.70), Vector2(0.22, 0.62), Vector2(0.19, 0.55), Vector2(0.11, 0.48), Vector2(0.04, 0.40),
	Vector2(0.02, 0.30), Vector2(0.08, 0.20), Vector2(0.18, 0.12), Vector2(0.28, 0.05),
]
const SA_X0 := 37
const SA_Y0 := 6
const SA_W := 52
const SA_H := 78

var world: KotoWorld
var island := "sa"               # форма острова: sa — Сан-Андреас, bay — бухта Мурлибу, isles — острова Каталины


func _init(w) -> void:
	world = w


# =====================================================================
#  Генерация карты
# =====================================================================

## Клетка-центр Лос-Сантоса — отсюда начинается город.
func start_spot() -> Vector2:
	match island:
		"bay":
			return Vector2(60, 33)
		"isles":
			return Vector2(57, 50)
	return Vector2(SA_X0 + SA_W * 0.5, SA_Y0 + SA_H * 0.84)


static func _in_poly(p: Vector2, poly: Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside


## Рельеф острова без построек — для карты и для картинки-превью при выборе.
func gen_terrain(kind: String, s: int) -> PackedByteArray:
	match kind:
		"bay":
			return _gen_bay(s)
		"isles":
			return _gen_isles(s)
	return _gen_sa(s)


## Неровный берег: радиус «дышит» в зависимости от угла.
static func _blob(p: Vector2, c: Vector2, r: Vector2, s: int, wob := 0.12) -> float:
	var d := (p - c) / r
	var a := atan2(d.y, d.x)
	var k := 1.0 + wob * sin(a * 3.0 + s % 7) + wob * 0.6 * sin(a * 7.0 + s % 11) + wob * 0.4 * sin(a * 13.0 + s % 5)
	return d.length() / k


## Песок по краю суши (шире там, где берег смотрит на юг — как пляжи Калифорнии).
static func _beaches(t: PackedByteArray) -> void:
	var out := t.duplicate()
	for y in H:
		for x in W:
			var i := y * W + x
			if t[i] == WATER:
				continue
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H or t[ny * W + nx] == WATER:
						near = true
			if not near and y + 2 < H and t[(y + 2) * W + x] == WATER:
				near = true
			if near:
				out[i] = SAND
	for i in W * H:
		t[i] = out[i]


func _gen_bay(s: int) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(W * H)
	t.fill(WATER)
	var sm := s % 100000
	for y in H:
		for x in W:
			var p := Vector2(x + 0.5, y + 0.5)
			var land := _blob(p, Vector2(68, 34), Vector2(52, 30), sm, 0.08) < 1.0
			# сама бухта открыта на юг и юго-запад
			if land and _blob(p, Vector2(56, 64), Vector2(34, 27), sm + 3, 0.06) < 1.0:
				land = false
			# мыс Палос-Вердес на юго-востоке
			if not land and _blob(p, Vector2(98, 60), Vector2(14, 10), sm + 5, 0.15) < 1.0:
				land = true
			# островок вдали
			if not land and _blob(p, Vector2(24, 74), Vector2(9, 5), sm + 9, 0.2) < 1.0:
				land = true
			if not land:
				continue
			var i := y * W + x
			var n := world.hashf(x / 3, y / 3, sm + 3)
			t[i] = GRASS
			# горы Санта-Моники вдоль севера
			var ridge := (y - 10.0 - 4.0 * sin(x * 0.12 + sm)) / 7.0
			if absf(ridge) < 0.45 and x > 24 and x < 108:
				t[i] = MOUNTAIN if n < 0.55 else HILL
			elif absf(ridge) < 1.2 and x > 18:
				t[i] = HILL
			elif x > 92 and n < 0.6:
				t[i] = DRY
			elif n > 0.78:
				t[i] = MEADOW
			# холмы на мысе
			if _blob(p, Vector2(100, 58), Vector2(6, 4), sm, 0.1) < 1.0:
				t[i] = HILL
	_beaches(t)
	return t


func _gen_isles(s: int) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(W * H)
	t.fill(WATER)
	var sm := s % 100000
	var isles := [[Vector2(58, 44), Vector2(30, 19), 0.14], [Vector2(101, 24), Vector2(11, 7), 0.2],
		[Vector2(99, 66), Vector2(13, 8), 0.18], [Vector2(22, 22), Vector2(9, 6), 0.22]]
	for y in H:
		for x in W:
			var p := Vector2(x + 0.5, y + 0.5)
			var best := 9.0
			var which := -1
			for k in isles.size():
				var b := _blob(p, isles[k][0], isles[k][1], sm + k * 13, isles[k][2])
				if b < best:
					best = b
					which = k
			if best >= 1.0:
				continue
			var i := y * W + x
			var n := world.hashf(x / 3, y / 3, sm + 3)
			t[i] = GRASS
			# холм с вершиной посередине каждого острова
			if best < 0.28 and which == 0:
				t[i] = MOUNTAIN
			elif best < 0.55:
				t[i] = HILL if n < 0.75 else MEADOW
			elif n > 0.72:
				t[i] = MEADOW
			elif which == 2 and n < 0.4:
				t[i] = DRY
	# бухточки на главном острове
	for c in [Vector2(46, 61), Vector2(76, 28), Vector2(32, 40)]:
		for y in range(int(c.y) - 4, int(c.y) + 5):
			for x in range(int(c.x) - 5, int(c.x) + 6):
				if world.in_map(x, y) and Vector2((x - c.x) / 5.0, (y - c.y) / 3.5).length() < 1.0:
					t[y * W + x] = WATER
	_beaches(t)
	return t


func _gen_sa(s: int) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(W * H)
	t.fill(WATER)
	var sm := s % 100000
	for y in H:
		for x in W:
			var u := (x + 0.5 - SA_X0) / SA_W
			var v := (y + 0.5 - SA_Y0) / SA_H
			if u < -0.05 or u > 1.05 or v < -0.05 or v > 1.05:
				continue
			var jit := Vector2(world.hashf(x, y, sm) - 0.5, world.hashf(x, y, sm + 7) - 0.5) * 0.025
			var p := Vector2(u, v) + jit
			if not _in_poly(p, SA_SHAPE):
				continue
			var i := y * W + x
			t[i] = GRASS
			var edge := false
			for d in [Vector2(0.03, 0), Vector2(-0.03, 0), Vector2(0, 0.02), Vector2(0, -0.02)]:
				if not _in_poly(p + d, SA_SHAPE):
					edge = true
			if edge:
				t[i] = SAND
				continue
			var n := world.hashf(x / 3, y / 3, sm + 3)
			var chil := Vector2((u - 0.28) / 0.13, (v - 0.17) / 0.09).length()
			if chil < 0.6:
				t[i] = MOUNTAIN
			elif chil < 1.0:
				t[i] = HILL
			elif v < 0.22 and n < 0.55:
				t[i] = MEADOW
			elif Vector2((u - 0.83) / 0.11, (v - 0.57) / 0.15).length() + (n - 0.5) * 0.4 < 1.0:
				t[i] = MOUNTAIN if Vector2((u - 0.84) / 0.07, (v - 0.57) / 0.1).length() < 1.0 else HILL
			elif Vector2((u - 0.86) / 0.08, (v - 0.27) / 0.07).length() < 1.0:
				t[i] = HILL
			elif Vector2((u - 0.57) / 0.25, (v - 0.45) / 0.16).length() + (n - 0.5) * 0.45 < 1.0:
				t[i] = DRY
			elif Vector2((u - 0.52) / 0.2, (v - 0.665) / 0.04).length() + (n - 0.5) * 0.5 < 1.0:
				t[i] = HILL
			if Vector2((u - 0.56) / 0.13, (v - 0.40) / 0.045).length() < 1.0:
				t[i] = WATER
	return t


func _gen_map(s: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	world.terrain = gen_terrain(island, s)
	world.objs = []
	world.objs.resize(W * H)
	# вокруг места, где начинается город, — ровная трава без гор
	var c0 := start_spot()
	for y in range(int(c0.y) - 3, int(c0.y) + 4):
		for x in range(int(c0.x) - 4, int(c0.x) + 5):
			if world.in_map(x, y) and world.terrain[y * W + x] != WATER and world.terrain[y * W + x] != SAND:
				world.terrain[y * W + x] = GRASS
	# природа: пальмы у Лос-Сантоса и на пляжах, агавы в пустыне, камни в горах
	var spots := []
	var center := start_spot()
	for y in H:
		for x in W:
			var t: int = world.terrain[y * W + x]
			if t != WATER and Vector2(x, y).distance_to(center) > 7.0:
				spots.append(Vector2i(x, y))
	spots.shuffle()
	var placed := 0
	for p in spots:
		if placed >= 120:
			break
		var t: int = world.terrain[p.y * W + p.x]
		var kind := ""
		match t:
			DRY:
				kind = "agave" if rng.randf() < 0.7 else "rock"
			MOUNTAIN, HILL:
				kind = "rock" if rng.randf() < 0.5 else "wildpalm"
			SAND:
				kind = "wildpalm" if rng.randf() < 0.6 else "rock"
			_:
				kind = "wildpalm"
		if rng.randf() < 0.6:
			world.place_obj(p.y * W + p.x, kind, rng.randi() % 3, 0.0)
			placed += 1
