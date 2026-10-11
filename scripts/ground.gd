extends RefCounted
## Земля, вода, дороги, рельсы и тротуары рисуются один раз в большую картинку
## и обновляются только там, где что-то построили (кусками по 16×16 клеток).

const D = preload("res://scripts/defs.gd")
const W := D.W
const H := D.H
const T := D.T
const WATER := D.WATER
const SAND := D.SAND
const HILL := D.HILL
const MOUNTAIN := D.MOUNTAIN
const DRY := D.DRY
const MEADOW := D.MEADOW
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const CHUNK := 16
const CW := (W + CHUNK - 1) / CHUNK
const CH := (H + CHUNK - 1) / CHUNK

var world: KotoWorld


func _init(w) -> void:
	world = w


# =====================================================================
#  Отрисовка земли
# =====================================================================

func mark_dirty(x0: int, y0: int, w: int) -> void:
	for y in range(y0 - 2, y0 + w + 2):
		for x in range(x0 - 2, x0 + w + 2):
			if world.in_map(x, y):
				world.dirty_tiles[y * W + x] = true


func _render_terrain_full() -> void:
	for y in H:
		for x in W:
			_draw_tile(x, y)
	world.dirty_tiles.clear()
	compute_shore()


func compute_shore() -> void:
	world.shore = []
	for y in H:
		for x in W:
			if world.terrain[y * W + x] != WATER:
				continue
			for dv in DIRS:
				var nx: int = x + dv.x
				var ny: int = y + dv.y
				if world.in_map(nx, ny) and world.terrain[ny * W + nx] != WATER:
					world.shore.append([x, y, dv])


func _is_land(x: int, y: int) -> bool:
	return world.in_map(x, y) and world.terrain[y * W + x] != WATER


## Загрузить нарисованную землю в текстуры: все куски или только перечисленные.
func refresh_terrain(only = null) -> void:
	if world.terrain_tex.size() != CW * CH:
		world.terrain_tex = []
		for k in CW * CH:
			world.terrain_tex.append(ImageTexture.create_from_image(world.terrain_img.get_region(_chunk_rect(k))))
		return
	var list: Array = only if only != null else range(CW * CH)
	for k in list:
		(world.terrain_tex[k] as ImageTexture).update(world.terrain_img.get_region(_chunk_rect(k)))


func _chunk_rect(k: int) -> Rect2i:
	var cx := k % CW * CHUNK * T
	var cy := k / CW * CHUNK * T
	return Rect2i(cx, cy, mini(CHUNK * T, W * T - cx), mini(CHUNK * T, H * T - cy))


func _r(px: int, py: int, a: int, b: int, w: int, h: int, col: String) -> void:
	world.terrain_img.fill_rect(Rect2i(px + a, py + b, w, h), Color(col))


func _draw_tile(x: int, y: int) -> void:
	var px := x * T
	var py := y * T
	var i := y * W + x
	var t := world.terrain[i]
	var hs := func(k: int) -> float: return world.hashf(x, y, k)
	if t == WATER:
		_r(px, py, 0, 0, 16, 16, "6cc1e0")
		for k in 2:
			if hs.call(k) < 0.5:
				_r(px, py, int(hs.call(k + 5) * 12), int(hs.call(k + 9) * 14), 3, 1, "86cfe9")
		if _is_land(x, y - 1):
			_r(px, py, 0, 0, 16, 1, "e3f7fc"); _r(px, py, 0, 1, 16, 1, "a3dcef")
		if _is_land(x, y + 1):
			_r(px, py, 0, 15, 16, 1, "e3f7fc"); _r(px, py, 0, 14, 16, 1, "a3dcef")
		if _is_land(x - 1, y):
			_r(px, py, 0, 0, 1, 16, "e3f7fc"); _r(px, py, 1, 0, 1, 16, "a3dcef")
		if _is_land(x + 1, y):
			_r(px, py, 15, 0, 1, 16, "e3f7fc"); _r(px, py, 14, 0, 1, 16, "a3dcef")
	elif t == SAND:
		_r(px, py, 0, 0, 16, 16, "f1dfa6")
		for k in 6:
			_r(px, py, int(hs.call(k) * 16), int(hs.call(k + 20) * 16), 1, 1, "e4cc8c" if k % 2 else "f8ecc4")
	elif t == HILL:
		_r(px, py, 0, 0, 16, 16, "b0de8c")
		for k in 6:
			_r(px, py, int(hs.call(k) * 16), int(hs.call(k + 20) * 16), 1, 1, "c4eaa4" if k % 2 else "98cc78")
		# склоны: тень снизу и справа, свет сверху
		if not _is_high_at(x, y + 1):
			_r(px, py, 0, 13, 16, 3, "88c070"); _r(px, py, 0, 15, 16, 1, "70a85c")
		if not _is_high_at(x + 1, y):
			_r(px, py, 14, 0, 2, 16, "98cc78")
		if not _is_high_at(x, y - 1):
			_r(px, py, 0, 0, 16, 1, "d0f0b4")
	elif t == MOUNTAIN:
		# горная цепь: на каждой клетке пик со светлым и тёмным склоном
		_r(px, py, 0, 0, 16, 16, "a89a80")
		for k in 5:
			_r(px, py, int(hs.call(k) * 15), int(hs.call(k + 20) * 15), 1, 1, "968870")
		var n_m := int(terrain_at(x, y - 1) == MOUNTAIN) + int(terrain_at(x - 1, y) == MOUNTAIN) + int(terrain_at(x + 1, y) == MOUNTAIN) + int(terrain_at(x, y + 1) == MOUNTAIN)
		var apex := 1 + int(hs.call(93) * 3)
		var ax := 6 + int(hs.call(94) * 4)
		for r in range(0, 15 - apex):
			var yy := apex + r
			var hw := int(r * 0.75) + 1
			_r(px, py, ax - hw, yy, hw, 1, "cbbfa6")
			_r(px, py, ax, yy, hw, 1, "8f816a")
		# снег на вершинах в глубине массива
		if n_m >= 3:
			var sh := 3 if n_m == 4 else 2
			for r in sh:
				var hw2 := int(r * 0.75) + 1
				_r(px, py, ax - hw2, apex + r, hw2 * 2, 1, "ffffff" if r < sh - 1 else "e8eef6")
		if terrain_at(x, y + 1) != MOUNTAIN:
			_r(px, py, 0, 13, 16, 3, "7a6c56")
			for k in range(1, 16, 4):
				_r(px, py, k, 13, 1, 3, "65584a")
	elif t == DRY:
		_r(px, py, 0, 0, 16, 16, "d4c88a")
		for k in 7:
			_r(px, py, int(hs.call(k) * 16), int(hs.call(k + 20) * 16), 1, 1, "c0b070" if k % 2 else "e4dca4")
		if hs.call(60) < 0.4:
			var bx := 3 + int(hs.call(61) * 9)
			var by := 4 + int(hs.call(62) * 8)
			_r(px, py, bx, by, 3, 2, "8a9a58"); _r(px, py, bx + 1, by - 1, 1, 1, "8a9a58")
	elif t == MEADOW:
		_r(px, py, 0, 0, 16, 16, "9bd67f")
		for k in 5:
			_r(px, py, int(hs.call(k) * 16), int(hs.call(k + 20) * 16), 1, 1, "8bc871")
		for k in 4:
			var fx := 1 + int(hs.call(k + 40) * 14)
			var fy := 1 + int(hs.call(k + 50) * 14)
			_r(px, py, fx, fy, 1, 1, ["ff6b3a", "ff9f43", "ffffff", "c8a8ff"][k])
	else:
		_r(px, py, 0, 0, 16, 16, "9bd67f")
		for k in 7:
			_r(px, py, int(hs.call(k) * 16), int(hs.call(k + 20) * 16), 1, 1, "8bc871" if k % 3 else "b0e294")
		for k in 2:
			_r(px, py, int(hs.call(k + 40) * 15), int(hs.call(k + 50) * 14), 1, 2, "7fbf68")
		if hs.call(77) < 0.13:
			var fx := 2 + int(hs.call(78) * 11)
			var fy := 2 + int(hs.call(79) * 11)
			var col: String = ["ffffff", "ffd1e0", "fff3a0", "c8b6ff"][int(hs.call(80) * 4)]
			_r(px, py, fx - 1, fy, 3, 1, col); _r(px, py, fx, fy - 1, 1, 3, col); _r(px, py, fx, fy, 1, 1, "ffd75e")
	var o = world.objs[i]
	if o == null:
		return
	if o.t == "road":
		_draw_road(px, py, x, y, t == WATER)
	elif o.t == "highway":
		_draw_highway(px, py, x, y, t == WATER)
	elif o.t == "path":
		_draw_path(px, py, x, y, t == WATER, hs)
	elif o.t == "blvd":
		if t == WATER:
			_draw_path(px, py, x, y, true, hs)
		else:
			_draw_blvd(px, py, x, y)
	elif o.t == "rail":
		_draw_rail(px, py, x, y, t == WATER, false)
	elif o.t == "crossing":
		_draw_road(px, py, x, y, t == WATER)
		_draw_rail(px, py, x, y, t == WATER, true)
	elif o.w == 2 and (D.def(o.t).has("cap") or D.def(o.t).has("jobs")) and not D.def(o.t).get("nopad", false):
		_r(px, py, 0, 0, 16, 16, "d8d0c4")
		if hs.call(3) < 0.5:
			_r(px, py, int(hs.call(4) * 14), int(hs.call(5) * 14), 2, 1, "cbc2b4")


func terrain_at(x: int, y: int) -> int:
	return world.terrain[y * W + x] if world.in_map(x, y) else WATER


func _is_high_at(x: int, y: int) -> bool:
	return world.in_map(x, y) and world.is_high(y * W + x)


## Магистраль: 2 полосы в каждую сторону, двойная жёлтая посередине.
func _draw_highway(px: int, py: int, x: int, y: int, water: bool) -> void:
	var up := world.is_highway(x, y - 1)
	var dn := world.is_highway(x, y + 1)
	var lf := world.is_highway(x - 1, y)
	var rt := world.is_highway(x + 1, y)
	var asph := "5d5b6a"
	_r(px, py, 0, 0, 16, 16, asph)
	var horiz := (lf or rt) and not (up or dn)
	var vert := (up or dn) and not (lf or rt)
	if not horiz and not vert and (lf or rt) and (up or dn):
		# развязка
		for k in range(2, 14, 3):
			_r(px, py, k, 0, 1, 1, "e6e6ee"); _r(px, py, k, 15, 1, 1, "e6e6ee")
		return
	var edge := "c9c4d6" if not water else "c08f5f"
	if horiz or not vert:
		_r(px, py, 0, 7, 16, 1, "ffd23f"); _r(px, py, 0, 8, 16, 1, "ffd23f")
		_r(px, py, 1, 4, 5, 1, "ffffff"); _r(px, py, 9, 4, 5, 1, "ffffff")
		_r(px, py, 1, 11, 5, 1, "ffffff"); _r(px, py, 9, 11, 5, 1, "ffffff")
		# там, где подходит обычная дорога, — съезд: разрыв обочины и пунктир слияния
		_hw_edge(px, py, world.is_road(x, y - 1), 0, true, edge)
		_hw_edge(px, py, world.is_road(x, y + 1), 15, true, edge)
	else:
		_r(px, py, 7, 0, 1, 16, "ffd23f"); _r(px, py, 8, 0, 1, 16, "ffd23f")
		_r(px, py, 4, 1, 1, 5, "ffffff"); _r(px, py, 4, 9, 1, 5, "ffffff")
		_r(px, py, 11, 1, 1, 5, "ffffff"); _r(px, py, 11, 9, 1, 5, "ffffff")
		_hw_edge(px, py, world.is_road(x - 1, y), 0, false, edge)
		_hw_edge(px, py, world.is_road(x + 1, y), 15, false, edge)


func _hw_edge(px: int, py: int, ramp: bool, at: int, horiz: bool, edge: String) -> void:
	if not ramp:
		if horiz:
			_r(px, py, 0, at, 16, 1, edge)
		else:
			_r(px, py, at, 0, 1, 16, edge)
		return
	var inner := 1 if at == 0 else 14
	for k in range(0, 16, 4):
		if horiz:
			_r(px, py, k, inner, 2, 1, "ffffff")
		else:
			_r(px, py, inner, k, 1, 2, "ffffff")


func _draw_road(px: int, py: int, x: int, y: int, water: bool) -> void:
	# разметка — по соседним обычным дорогам; съезд на магистраль — по направлению движения
	var up := world.is_road(x, y - 1) or (world.is_highway(x, y - 1) and not world.is_road(x - 1, y) and not world.is_road(x + 1, y))
	var dn := world.is_road(x, y + 1) or (world.is_highway(x, y + 1) and not world.is_road(x - 1, y) and not world.is_road(x + 1, y))
	var lf := world.is_road(x - 1, y) or (world.is_highway(x - 1, y) and not world.is_road(x, y - 1) and not world.is_road(x, y + 1))
	var rt := world.is_road(x + 1, y) or (world.is_highway(x + 1, y) and not world.is_road(x, y - 1) and not world.is_road(x, y + 1))
	var asph := "7a7888"
	var curb := "b8b6c4"
	var line := "f4ecd0"
	if water:
		_r(px, py, 0, 0, 16, 16, "6cc1e0")
	_r(px, py, 1, 1, 14, 14, asph)
	if up: _r(px, py, 1, 0, 14, 1, asph)
	if dn: _r(px, py, 1, 15, 14, 1, asph)
	if lf: _r(px, py, 0, 1, 1, 14, asph)
	if rt: _r(px, py, 15, 1, 1, 14, asph)
	if water:
		if not up: _r(px, py, 0, 0, 16, 2, "c08f5f")
		if not dn: _r(px, py, 0, 14, 16, 2, "c08f5f")
		if not lf: _r(px, py, 0, 0, 2, 16, "c08f5f")
		if not rt: _r(px, py, 14, 0, 2, 16, "c08f5f")
	else:
		if up and lf: _r(px, py, 0, 0, 1, 1, asph)
		if up and rt: _r(px, py, 15, 0, 1, 1, asph)
		if dn and lf: _r(px, py, 0, 15, 1, 1, asph)
		if dn and rt: _r(px, py, 15, 15, 1, 1, asph)
		if not up: _r(px, py, 1, 1, 14, 1, curb)
		if not dn: _r(px, py, 1, 14, 14, 1, curb)
		if not lf: _r(px, py, 1, 1, 1, 14, curb)
		if not rt: _r(px, py, 14, 1, 1, 14, curb)
	var n := int(up) + int(dn) + int(lf) + int(rt)
	if not water and world.is_crosswalk(x, y):
		# «зебра» поперёк дороги
		if (lf or rt) and not (up or dn):
			for k in range(3, 14, 2):
				_r(px, py, 6, k, 4, 1, "f4f4f8")
			return
		if (up or dn) and not (lf or rt):
			for k in range(3, 14, 2):
				_r(px, py, k, 6, 1, 4, "f4f4f8")
			return
	if n >= 3:
		for k in range(3, 13, 2):
			if up: _r(px, py, k, 1, 1, 2, "e6e6ee")
			if dn: _r(px, py, k, 13, 1, 2, "e6e6ee")
			if lf: _r(px, py, 1, k, 2, 1, "e6e6ee")
			if rt: _r(px, py, 13, k, 2, 1, "e6e6ee")
	elif (lf or rt) and not (up or dn):
		_r(px, py, 2, 7, 4, 1, line); _r(px, py, 10, 7, 4, 1, line)
	elif (up or dn) and not (lf or rt):
		_r(px, py, 7, 2, 1, 4, line); _r(px, py, 7, 10, 1, 4, line)
	else:
		if up: _r(px, py, 7, 1, 1, 4, line)
		if dn: _r(px, py, 7, 11, 1, 4, line)
		if lf: _r(px, py, 1, 7, 4, 1, line)
		if rt: _r(px, py, 11, 7, 4, 1, line)


func _draw_rail(px: int, py: int, x: int, y: int, water: bool, on_road: bool) -> void:
	var lf := world.is_rail(x - 1, y)
	var rt := world.is_rail(x + 1, y)
	var up := world.is_rail(x, y - 1)
	var dn := world.is_rail(x, y + 1)
	var horiz := lf or rt or not (up or dn)
	var vert := up or dn
	var steel := "8a8fa0"
	var shine := "c8ccd8"
	if water and not on_road:
		_r(px, py, 0, 0, 16, 16, "6cc1e0")
		if horiz:
			_r(px, py, 0, 2, 16, 12, "a07850"); _r(px, py, 0, 2, 16, 1, "7a5a3b"); _r(px, py, 0, 13, 16, 1, "7a5a3b")
		if vert:
			_r(px, py, 2, 0, 12, 16, "a07850"); _r(px, py, 2, 0, 1, 16, "7a5a3b"); _r(px, py, 13, 0, 1, 16, "7a5a3b")
	if horiz:
		if not on_road and not water:
			_r(px, py, 0, 3, 16, 10, "b8ad9a")
		if not on_road:
			for k in range(1, 16, 4):
				_r(px, py, k, 3, 2, 10, "7a5a3b")
		_r(px, py, 0, 5, 16, 1, steel); _r(px, py, 0, 4, 16, 1, shine)
		_r(px, py, 0, 10, 16, 1, steel); _r(px, py, 0, 9, 16, 1, shine)
	if vert:
		if not on_road and not water:
			_r(px, py, 3, 0, 10, 16, "b8ad9a")
		if not on_road:
			for k in range(1, 16, 4):
				_r(px, py, 3, k, 10, 2, "7a5a3b")
		_r(px, py, 5, 0, 1, 16, steel); _r(px, py, 4, 0, 1, 16, shine)
		_r(px, py, 10, 0, 1, 16, steel); _r(px, py, 9, 0, 1, 16, shine)


func _path_conn(x: int, y: int) -> bool:
	var n = world.obj_at(x, y)
	if n == null:
		return false
	if n.t == "path" or n.t == "blvd" or n.t == "road":
		return true
	var d := D.def(n.t)
	return not d.get("natural", false) and not d.get("walk", false)


func _draw_path(px: int, py: int, x: int, y: int, water: bool, hs: Callable) -> void:
	var up := _path_conn(x, y - 1)
	var dn := _path_conn(x, y + 1)
	var lf := _path_conn(x - 1, y)
	var rt := _path_conn(x + 1, y)
	if water:
		if (lf or rt) and not (up or dn):
			_r(px, py, 0, 2, 16, 12, "c08f5f")
			for k in range(0, 16, 3):
				_r(px, py, k, 2, 1, 12, "9a6c45")
			_r(px, py, 0, 2, 16, 1, "7a5236"); _r(px, py, 0, 13, 16, 1, "7a5236")
		else:
			_r(px, py, 2, 0, 12, 16, "c08f5f")
			for k in range(0, 16, 3):
				_r(px, py, 2, k, 12, 1, "9a6c45")
			_r(px, py, 2, 0, 1, 16, "7a5236"); _r(px, py, 13, 0, 1, 16, "7a5236")
		return
	# плитка во всю клетку
	var fill := "e9dccd"
	var seam := "d6c4b0"
	_r(px, py, 0, 0, 16, 16, fill)
	for row in 4:
		_r(px, py, 0, row * 4, 16, 1, seam)
		var shift := 4 if row % 2 == 1 else 0
		for sx in range(shift, 16, 8):
			_r(px, py, sx, row * 4, 1, 4, seam)
	for k in 3:
		_r(px, py, 1 + int(hs.call(k + 60) * 14), 1 + int(hs.call(k + 70) * 14), 2, 1, "f4ebe0")
	var curb := "b8a48e"
	if not up: _r(px, py, 0, 0, 16, 1, curb)
	if not dn: _r(px, py, 0, 15, 16, 1, curb)
	if not lf: _r(px, py, 0, 0, 1, 16, curb)
	if not rt: _r(px, py, 15, 0, 1, 16, curb)


## Голливудский бульвар: тёмная плитка аллеи славы с розовой звездой в каждой клетке.
func _draw_blvd(px: int, py: int, x: int, y: int) -> void:
	var up := _path_conn(x, y - 1)
	var dn := _path_conn(x, y + 1)
	var lf := _path_conn(x - 1, y)
	var rt := _path_conn(x + 1, y)
	_r(px, py, 0, 0, 16, 16, "5a4c5e")
	_r(px, py, 0, 0, 16, 1, "4a3e4e"); _r(px, py, 0, 0, 1, 16, "4a3e4e")
	for k in 6:
		_r(px, py, (k * 7 + x * 3) % 15 + 1, (k * 5 + y * 7) % 15 + 1, 1, 1, "6e5e72")
	# звёзды через клетку, как на настоящей аллее славы
	var curb := "c9b8a0"
	if (x + y) % 2 == 1:
		_r(px, py, 3, 3, 10, 10, "625468"); _r(px, py, 7, 7, 2, 2, "e8c870")
		if not up: _r(px, py, 0, 0, 16, 1, curb)
		if not dn: _r(px, py, 0, 15, 16, 1, curb)
		if not lf: _r(px, py, 0, 0, 1, 16, curb)
		if not rt: _r(px, py, 15, 0, 1, 16, curb)
		return
	var star := ["...x...", "..xxx..", "xxxxxxx", ".xxxxx.", "..xxx..", ".xx.xx.", "x.....x"]
	for r in 7:
		for c in 7:
			if star[r][c] == "x":
				_r(px, py, 4 + c, 2 + r, 1, 1, "f59ab2")
	_r(px, py, 7, 5, 1, 1, "e8c870")
	_r(px, py, 5, 11, 6, 1, "e8c870"); _r(px, py, 6, 12, 4, 1, "c8a850")
	if not up: _r(px, py, 0, 0, 16, 1, curb)
	if not dn: _r(px, py, 0, 15, 16, 1, curb)
	if not lf: _r(px, py, 0, 0, 1, 16, curb)
	if not rt: _r(px, py, 15, 0, 1, 16, curb)
