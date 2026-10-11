extends RefCounted
## Отрисовка мира поверх земли каждый кадр: постройки, котики, машины, сценки,
## светофоры, переходы, частицы и призрак постройки под курсором.

const D = preload("res://scripts/defs.gd")
const W := D.W
const H := D.H
const T := D.T
const WATER := D.WATER
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const INK := Color("3b2a3a")
const FLAT := ["pawtile", "boatdock", "parking", "tennis", "volleyball", "skatepark", "helipad"]
const CHUNK := 16
const CW := (W + CHUNK - 1) / CHUNK
const CH := (H + CHUNK - 1) / CHUNK
const WINDY := ["palm", "wildpalm"]               # котик, на которого показывает обучение
const LANE := {"r": Vector2(0, 3), "l": Vector2(0, -3), "d": Vector2(-3, 0), "u": Vector2(3, 0)}
const LIGHT_COLS := [Color("e0483a"), Color("ffd23f"), Color("5fd38f")]
const SCENES := ["tennis", "volleyball", "skatepark", "playground", "umbrella", "fountain", "icecream", "cafe", "boba", "juicebar", "pier", "surf"]
const SIT_OUTSIDE := ["cafe", "boba", "juicebar"]

var world: KotoWorld
# кэш отрисовки: видимые постройки и блики на воде
var _scan_key := []
var _scan: Array = []
var _scan_scenes: Array = []
var _spark_key := []
var _spark: Array = []
var lights: Array = []
var tut_cat = null


func _init(w) -> void:
	world = w


# =====================================================================
#  Отрисовка мира
# =====================================================================

func draw_world() -> void:
	if world.terrain_tex.is_empty():
		return
	var v := world.visible_range()
	for cy in range(v[1] / CHUNK, v[3] / CHUNK + 1):
		for cx in range(v[0] / CHUNK, v[2] / CHUNK + 1):
			if cx < CW and cy < CH:
				world.draw_texture(world.terrain_tex[cy * CW + cx], Vector2(cx * CHUNK * T, cy * CHUNK * T))
	var sparkle := Color("d6f2fa")
	if world.zoom >= 2:
		for r in _sparkles(v):
			world.draw_rect(r, sparkle)

	var foam := Color(1, 1, 1, 0.75)
	for sh in world.shore:
		var x: int = sh[0]
		var y: int = sh[1]
		if x < v[0] or x > v[2] or y < v[1] or y > v[3] or world.objs[y * W + x] != null:
			continue
		var dv: Vector2i = sh[2]
		var off := 2 + roundi((sin(world.anim_time * 1.6 + x * 0.7 + y * 0.5) + 1.0) * 1.5)
		match dv:
			Vector2i(0, -1):
				world.draw_rect(Rect2(x * T, y * T + off, T, 1), foam)
			Vector2i(0, 1):
				world.draw_rect(Rect2(x * T, y * T + T - 1 - off, T, 1), foam)
			Vector2i(-1, 0):
				world.draw_rect(Rect2(x * T + off, y * T, 1, T), foam)
			Vector2i(1, 0):
				world.draw_rect(Rect2(x * T + T - 1 - off, y * T, 1, T), foam)

	var h := world.hour()
	lights = []
	_scan_buildings(v)
	var list := _scan.duplicate()
	for o in _scan_scenes:
		if _scene_on(o, h):
			list.append([float((o.i / W + o.w) * T) + 2.0, 5, o])
	for c in world.cats:
		if c.state == "in" or c.state == "drive" or c.state == "ride":
			continue
		if c.x < v[0] - 1 or c.x > v[2] + 1 or c.y < v[1] - 1 or c.y > v[3] + 1:
			continue
		list.append([c.y * T + 14.0, 1, c])
	for car in world.cars:
		list.append([car.py + 4.0, 2, car])
	for vis in world.events.visitors:
		list.append([vis.y * T + 14.0, 3, vis])
	world.transit.draw_items(list)
	world.boats.draw_items(list)
	for c in world.street_parked:
		var tx: int = c.car_tile % W
		var ty: int = c.car_tile / W
		if tx < v[0] or tx > v[2] or ty < v[1] or ty > v[3]:
			continue
		var off: Vector2 = LANE.get(c.car_dir, Vector2.ZERO)
		var pc := {"kind": world.car_model(c), "color": c.car, "px": tx * T + 8.0 + off.x, "py": ty * T + 8.0 + off.y, "dir": c.car_dir, "cat": null, "parked": true}
		list.append([pc.py + 4.0, 2, pc])
	list.sort_custom(func(a, b): return a[0] < b[0])
	_draw_driveways(v)

	for it in list:
		match it[1]:
			0:
				_draw_obj(it[2], it[3], it[4], h)
			1:
				_draw_cat(it[2])
			2:
				_draw_car(it[2])
			3:
				_draw_visitor(it[2])
			4:
				world.transit.draw_segment(it[2])
			5:
				_draw_scene(it[2])
			6:
				world.boats.draw_boat(it[2])
			7:
				world.transit.draw_heli(it[2])

	_draw_bunting()
	_draw_traffic_lights(v)
	_draw_crossings(v)
	_draw_ramp_signs(v)
	_draw_ghost()
	_draw_tut_arrow()
	_draw_particles()
	world.transit.draw_planes()


## Блики на воде меняются полтора раза в секунду — считаем их только при смене такта,
## сдвиге камеры или стройке, а не каждый кадр для каждой клетки воды.
func _sparkles(v: Array) -> Array:
	var tick := int(world.anim_time * 1.5)
	var key := [v, tick, world.objs_version]
	if key == _spark_key:
		return _spark
	_spark_key = key
	_spark = []
	for y in range(v[1], v[3] + 1):
		for x in range(v[0], v[2] + 1):
			if world.terrain[y * W + x] != WATER or world.objs[y * W + x] != null:
				continue
			if world.hashf(x, y, tick) < 0.18:
				_spark.append(Rect2(x * T + int(world.hashf(x, y, tick + 3) * 12) + 2, y * T + int(world.hashf(x, y, tick + 7) * 12) + 2, 2, 1))
	return _spark


## Видимые постройки (без дорог и тротуаров — они нарисованы в земле) с ключом сортировки.
## Пересобираются, только когда сдвинулась камера или что-то построили и снесли.
func _scan_buildings(v: Array) -> void:
	var key := [v, world.objs_version]
	if key == _scan_key:
		return
	_scan_key = key
	_scan = []
	_scan_scenes = []
	for y in range(v[1], v[3] + 1):
		for x in range(v[0], v[2] + 1):
			var i := y * W + x
			var o = world.objs[i]
			if o != null and o.i == i and o.t != "path" and o.t != "blvd" and o.t != "road" and world.pairs.get(i, "") != "R":
				# плоские постройки (парковки, корты) — часть земли: котики и машины поверх них
				_scan.append([(y * T - 8.0) if FLAT.has(o.t) else float((y + o.w) * T), 0, o, x, y])
				if SCENES.has(o.t):
					_scan_scenes.append(o)


## Шлагбаумы на переездах: закрыты, пока рядом поезд.
func _draw_crossings(v: Array) -> void:
	for i in world.crossings:
		var x: int = i % W
		var y: int = i / W
		if x < v[0] or x > v[2] or y < v[1] or y > v[3]:
			continue
		var shut: bool = world.transit.closed.has(i)
		var rail_h := world.is_rail(x - 1, y) or world.is_rail(x + 1, y)
		var px := x * T
		var py := y * T
		var blink := int(world.anim_time * 4.0) % 2 == 0
		for k in 2:
			var post: Vector2
			if rail_h:
				post = Vector2(px + (1 if k == 0 else 14), py + (1 if k == 0 else 14))
			else:
				post = Vector2(px + (14 if k == 0 else 1), py + (1 if k == 0 else 14))
			world.draw_rect(Rect2(post.x, post.y - 6, 1, 7), Color("4a4458"))
			world.draw_rect(Rect2(post.x - 1, post.y - 7, 3, 2), Color("e0483a") if shut and (blink == (k == 0)) else Color("5a3a3a"))
			if shut and blink == (k == 0) and world.dark > 0.1:
				lights.append(Vector3(post.x + 0.5, post.y - 6, 6))
			if shut:
				# опущенная стрела поперёк дороги, красно-белая
				for s in 7:
					var col := Color("e0483a") if s % 2 == 0 else Color("f4f4f8")
					if rail_h:
						world.draw_rect(Rect2(post.x + (1 + s if k == 0 else -1 - s), post.y - 4, 1, 1), col)
					else:
						world.draw_rect(Rect2(post.x - 4, post.y + (1 + s if k == 0 else -1 - s) - 4, 1, 1), col)
			else:
				for s in 5:
					world.draw_rect(Rect2(post.x + 1, post.y - 7 - s, 1, 1), Color("e0483a") if s % 2 == 0 else Color("f4f4f8"))


func _draw_obj(o: Dictionary, x: int, y: int, h: float) -> void:
	if o.build > 0.0:
		_draw_construction(o, x, y)
		return
	var paired: bool = world.pairs.get(o.i, "") == "L"
	var tx: Texture2D
	var wins: Array
	if paired:
		var pv: Array = world.spr.pair_variant(o)
		tx = pv[0]
		wins = pv[1]
	else:
		tx = world.spr.obj_texture(o)
		if tx != null:
			wins = world.spr.windows_for(o)
	if tx == null:
		return
	var span: int = 2 if paired else o.w
	var sx: int = x * T + (span * T - tx.get_width()) / 2
	var sy: int = (y + o.w) * T - tx.get_height()
	if WINDY.has(o.t) and absf(world.wind) > 0.02:
		# пальма чуть покачивается на ветру: верхушка смещается, корни на месте
		var ph := world.hashf(x, y, 31) * TAU
		var sway := world.wind * (0.035 + 0.02 * sin(world.anim_time * 1.7 + ph))
		var base := float(sy + tx.get_height())
		world.draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(-sway, 1), Vector2(0, base)))
		world.draw_texture(tx, Vector2(sx, -tx.get_height()))
		world.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	world.draw_texture(tx, Vector2(sx, sy))
	var mk = D.MAKES.get(o.t)
	if mk != null and float(o.get("out", 0.0)) >= 4.0:
		# готовые ящики с товаром у здания
		var gc := Color(D.GOODS[mk[0]].col)
		var by: int = (y + o.w) * T - 4
		for k in mini(4, int(o.out / 4.0)):
			var bx: int = x * T + o.w * T - 7 - (k % 2) * 5
			var yy: int = by - (k / 2) * 3
			world.draw_rect(Rect2(bx, yy, 5, 4), Color("5a3c30"))
			world.draw_rect(Rect2(bx + 1, yy + 1, 3, 2), gc)
	if o.t == "parking" or o.t == "garage":
		var slots: Array = world.spr.PARKING_SLOTS if o.t == "parking" else world.spr.GARAGE_SLOTS
		var cols: Array = world.lot_colors.get(o.i, [])
		for k in mini(cols.size(), slots.size()):
			var sl: Vector2i = slots[k]
			var big: bool = o.t == "parking"
			world.draw_rect(Rect2(sx + sl.x, sy + sl.y, 5 if big else 4, 3 if big else 2), Color(cols[k]))
			world.draw_rect(Rect2(sx + sl.x + 1, sy + sl.y, 2, 1), Color("bfe6f7"))
	if wins.size() > 0 and world.dark > 0.08:
		var d := D.def(o.t)
		var lit: bool
		if o.t == "lantern":
			lit = true
		elif d.get("leisure", false) or d.get("wonder", false):
			lit = (h >= 17.0 and h < 23.5) or world.inside_count.get(o.i, 0) > 0
		else:
			lit = world.inside_count.get(o.i, 0) > 0 or (paired and world.inside_count.get(o.i + 1, 0) > 0)
		if lit:
			# горят не все окна — у каждого здания свой рисунок света
			var few: bool = wins.size() <= 2 or o.t == "lantern"
			for k in wins.size():
				if not few and world.hashf(o.i, k, 77) > 0.6:
					continue
				var wr: Rect2i = wins[k]
				var glow := Color("ffd36e") if world.hashf(o.i, k, 78) < 0.7 else Color("ffe9a8")
				world.draw_rect(Rect2(sx + wr.position.x, sy + wr.position.y, wr.size.x, wr.size.y), glow)
			var r := 48.0 if o.t == "lantern" else (34.0 if o.w == 2 or paired else 18.0)
			var mid: Rect2i = wins[wins.size() / 2]
			lights.append(Vector3(sx + mid.position.x + 2, sy + mid.position.y + 2, r))


## Обучение: розовая стрелочка над первым котиком.
func _draw_tut_arrow() -> void:
	if tut_cat == null or not world.cats.has(tut_cat) or tut_cat.state == "in" or tut_cat.state == "drive" or tut_cat.state == "ride":
		return
	var p := world.cats_ai.cat_pos(tut_cat) + Vector2(0, -24 + roundf(sin(world.anim_time * 5.0) * 2.0))
	var tri := PackedVector2Array([p + Vector2(-5, -6), p + Vector2(5, -6), p])
	world.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, -7), p + Vector2(7, -7), p + Vector2(0, 2)]), INK)
	world.draw_colored_polygon(tri, Color("ff8fb1"))


func _draw_construction(o: Dictionary, x: int, y: int) -> void:
	var tx: Texture2D = world.spr.scaffold[o.w]
	var sx: int = x * T + (o.w * T - tx.get_width()) / 2
	var sy: int = (y + o.w) * T - tx.get_height()
	world.draw_texture(tx, Vector2(sx, sy))
	var total: float = D.def(o.t).get("build", 1.0)
	var k := clampf(1.0 - o.build / total, 0.0, 1.0)
	world.draw_rect(Rect2(sx + 2, sy - 4, tx.get_width() - 4, 3), INK)
	world.draw_rect(Rect2(sx + 3, sy - 3, roundi((tx.get_width() - 6) * k), 1), Color("7fd38f"))
	# строитель в каске стучит молотком
	var fs: Dictionary = world.spr.cat_set(["ginger", "gray", "tabby", "cream"][int(o.v) % 4], "builder")
	var up := int(world.anim_time * 4.0) % 2 == 1
	var frame: Texture2D = fs.walkA[1] if up else fs.stand[1]
	var bx := sx + tx.get_width() - 7
	var by: int = (y + o.w) * T - 15
	world.draw_texture(frame, Vector2(bx, by))
	world.draw_rect(Rect2(bx - 1, by + (8 if up else 10), 2, 1), Color("6a6478"))
	world.draw_rect(Rect2(bx, by + (9 if up else 11), 1, 2), Color("8a5a3b"))


func _cat_texture(c: Dictionary) -> Texture2D:
	var fs: Dictionary = world.spr.cat_set(c.color, world.cats_ai.outfit_key(c))
	var f := 1 if c.dir < 0 else 0
	match c.state:
		"sleep":
			return fs.sleep[f]
		"walk":
			return fs.walkB[f] if int(c.anim * 6.0) % 2 == 1 else fs.walkA[f]
	return fs.stand[f]


func _draw_cat(c: Dictionary) -> void:
	var tx := _cat_texture(c)
	var sx := roundi(c.x * T + 3)
	var sy := roundi(c.y * T - 1) - (int(c.anim * 8.0) % 2 if c.pet > 0.0 else 0)
	world.draw_rect(Rect2(sx + 1, sy + 15, 8, 1), Color(0.157, 0.118, 0.196, 0.2))
	world.draw_texture(tx, Vector2(sx, sy))
	if world.info_target != null and world.info_target.has("cat") and world.info_target.cat == c:
		var bob := roundi(sin(world.anim_time * 5.0) * 1.5)
		world.draw_texture(world.spr.small.heart, Vector2(sx + 3, sy - 4 + bob))


## Гость события: котик в праздничной одежде, появляется и исчезает плавно.
func _draw_visitor(v: Dictionary) -> void:
	var fs: Dictionary = world.spr.cat_set(v.color, v.outfit)
	var f := 1 if v.dir < 0 else 0
	var tx: Texture2D = fs.stand[f]
	if v.walking:
		tx = fs.walkB[f] if int(v.anim * 6.0) % 2 == 1 else fs.walkA[f]
	var sx := roundi(v.x * T + 3)
	var sy := roundi(v.y * T - 1)
	if not v.walking and world.events.active != null and (world.events.active.kind == "game" or world.events.active.kind == "beach"):
		sy -= int(v.anim * 3.0) % 2  # пританцовывают
	var m := Color(1, 1, 1, clampf(v.fade, 0.0, 1.0))
	world.draw_rect(Rect2(sx + 1, sy + 15, 8, 1), Color(0.157, 0.118, 0.196, 0.2 * m.a))
	world.draw_texture(tx, Vector2(sx, sy), m)


## Флажки-гирлянда над местом праздника.
func _draw_bunting() -> void:
	var ev = world.events.active
	if ev == null or not (ev.kind == "beach" or ev.kind == "market" or ev.kind == "tourists"):
		return
	var c: Vector2 = ev.pos * T + Vector2(8, -6)
	var cols := ["ff6b8b", "ffd75e", "7fc4e8", "9ed8c8", "c8a8ff"]
	var a := c + Vector2(-34, 0)
	var b := c + Vector2(34, 0)
	world.draw_line(a + Vector2(0, -6), a + Vector2(0, 14), INK, 1.0)
	world.draw_line(b + Vector2(0, -6), b + Vector2(0, 14), INK, 1.0)
	for k in 17:
		var t := k / 16.0
		var p := a.lerp(b, t) + Vector2(0, -6 + sin(t * PI) * 6.0)
		if k < 16:
			var q := a.lerp(b, (k + 1) / 16.0) + Vector2(0, -6 + sin((k + 1) / 16.0 * PI) * 6.0)
			world.draw_line(p, q, Color(INK, 0.7), 1.0)
		if k % 2 == 1:
			world.draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 0), p + Vector2(2, 0), p + Vector2(0, 4)]), Color(cols[(k / 2) % cols.size()]))


## Светофоры на углах перекрёстков: слева сверху — для едущих по горизонтали, справа снизу — по вертикали.
func _draw_traffic_lights(v: Array) -> void:
	for i in world.junctions:
		var x: int = i % W
		var y: int = i / W
		if x < v[0] or x > v[2] or y < v[1] or y > v[3]:
			continue
		for k in 2:
			var horiz := k == 0
			var bx := x * T + (0 if horiz else 15)
			var by := y * T + (2 if horiz else 13)
			var stt := world.light_state(i, horiz)
			world.draw_rect(Rect2(bx, by - 6, 1, 7), Color("4a4458"))
			world.draw_rect(Rect2(bx - 1, by - 10, 3, 5), INK)
			var lc: Color = LIGHT_COLS[stt]
			world.draw_rect(Rect2(bx, by - 9 + (2 - stt) * 1, 1, 1), lc)
			if world.dark > 0.15:
				lights.append(Vector3(bx + 0.5, by - 8.5, 5))


## Зелёные указатели фривея у въездов на магистраль.
func _draw_ramp_signs(v: Array) -> void:
	for r in world.ramps:
		var i: int = r[0]
		var dv: Vector2i = r[1]
		var x := i % W
		var y := i / W
		if x < v[0] or x > v[2] or y < v[1] or y > v[3]:
			continue
		var bx := x * T + (14 if dv.x <= 0 else 1)
		var by := y * T + 13
		world.draw_rect(Rect2(bx, by - 8, 1, 9), Color("4a4458"))
		var sx := bx - 5
		var sy := by - 15
		world.draw_rect(Rect2(sx, sy, 11, 7), Color("f4f4f8"))
		world.draw_rect(Rect2(sx + 1, sy + 1, 9, 5), Color("2f8a4f"))
		# щит шоссе «101» и стрелка
		world.draw_rect(Rect2(sx + 2, sy + 2, 3, 3), Color("f4f4f8"))
		world.draw_rect(Rect2(sx + 3, sy + 3, 1, 1), Color("3d5a98"))
		# стрелка к магистрали
		var ac := Vector2(sx + 7, sy + 3)
		var f := Vector2(dv)
		var side := Vector2(-f.y, f.x)
		# галочка-шеврон «туда»
		for q in [ac + f, ac + side, ac - side, ac - f + side * 2, ac - f - side * 2]:
			world.draw_rect(Rect2(q, Vector2.ONE), Color("f4f4f8"))


## Въезды на парковки: опущенный бордюр, светлая полоса, стоп-линия и стрелка внутрь.
func _draw_driveways(v: Array) -> void:
	var apron := Color("a9a6b8")
	var edge := Color("d8d4e4")
	var arrow := Color("ffd23f")
	for l in world.stats.lots:
		var o = world.objs[l]
		if o == null:
			continue
		var lx: int = l % W
		var ly: int = l / W
		if lx + o.w < v[0] or lx > v[2] or ly + o.w < v[1] or ly > v[3]:
			continue
		var made := 0
		for p in world.around(l):
			if made >= (2 if o.w > 1 else 1) or not world.is_road(p.x, p.y):
				continue
			# направление от парковки к дороге
			var d := Vector2i(0, 0)
			if p.y >= ly + o.w:
				d = Vector2i(0, 1)
			elif p.y < ly:
				d = Vector2i(0, -1)
			elif p.x < lx:
				d = Vector2i(-1, 0)
			else:
				d = Vector2i(1, 0)
			made += 1
			# c — точка на границе парковки и дороги; съезд в основном лежит на дороге
			var c := Vector2(p.x * T + 8, p.y * T + 8) - Vector2(d) * 8.0
			var fd := Vector2(d)
			var side := Vector2(absf(d.y), absf(d.x))
			var a0 := c - fd * 2.0 - side * 6.0
			var a1 := c + fd * 6.0 + side * 6.0
			var r := Rect2(a0, a1 - a0).abs()
			world.draw_rect(r, apron)
			# бортики по краям съезда
			world.draw_rect(Rect2(c - fd * 2.0 - side * 7.0, fd * 8.0 + side).abs(), edge)
			world.draw_rect(Rect2(c - fd * 2.0 + side * 6.0, fd * 8.0 + side).abs(), edge)
			# пунктирная стоп-линия на выезде
			var sl := c + fd * 5.0
			for k in range(-5, 6, 2):
				world.draw_rect(Rect2(sl + side * k, Vector2.ONE), Color(1, 1, 1, 0.9))
			# стрелка внутрь парковки
			var tip := c - fd * 1.0
			for q in [tip, tip + fd + side, tip + fd - side, tip + fd * 2.0 + side * 2.0, tip + fd * 2.0 - side * 2.0, tip + fd * 2.0, tip + fd * 3.0]:
				world.draw_rect(Rect2(q, Vector2.ONE), arrow)


func _scene_on(o: Dictionary, h: float) -> bool:
	if o.build > 0.0 or h < 8.0 or h > (21.5 if SIT_OUTSIDE.has(o.t) else 19.5):
		return false
	var d := D.def(o.t)
	return not d.has("jobs") or not world.workers.get(o.i, []).is_empty()


func _free_tile(x: int, y: int) -> bool:
	return world.in_map(x, y) and world.objs[y * W + x] == null and world.terrain[y * W + x] != WATER


func _scene_cat(k: int, i: int, outfit: String, feet: Vector2, face: int, frame := "stand", bob := 0) -> void:
	var keys: Array = D.CAT_COLORS.keys()
	var fs: Dictionary = world.spr.cat_set(keys[(i * 7 + k * 13) % keys.size()], outfit)
	var tx: Texture2D = fs[frame][1 if face < 0 else 0]
	var pos := Vector2(roundi(feet.x - tx.get_width() / 2.0), roundi(feet.y - tx.get_height() + bob))
	world.draw_rect(Rect2(pos.x + 1, feet.y - 1, tx.get_width() - 2, 1), Color(0.157, 0.118, 0.196, 0.2))
	world.draw_texture(tx, pos)


func _draw_scene(o: Dictionary) -> void:
	var bx := float(o.i % W * T)
	var by := float(o.i / W * T)
	var t := world.anim_time + world.hashf(o.i, 3) * 10.0
	var i: int = o.i
	match o.t:
		"tennis":
			# двое перекидывают мячик через сетку
			var cyc := fposmod(t * 0.9, 2.0)
			var k := fposmod(cyc, 1.0)
			var lr := int(cyc) == 0
			var bxp := lerpf(bx + 10.0, bx + 22.0, k if lr else 1.0 - k)
			var byp := by + 22.0 - sin(k * PI) * 8.0
			_scene_cat(0, i, "trainer", Vector2(bx + 7, by + 27), 1, "walkA" if lr and k < 0.2 else "stand")
			_scene_cat(1, i, "trainer", Vector2(bx + 25, by + 27), -1, "walkA" if not lr and k < 0.2 else "stand")
			world.draw_rect(Rect2(bx + 11, by + 19, 1, 3), Color("8a5a3b"))
			world.draw_rect(Rect2(bx + 20, by + 19, 1, 3), Color("8a5a3b"))
			world.draw_rect(Rect2(roundi(bxp), by + 26, 2, 1), Color(0.157, 0.118, 0.196, 0.25))
			world.draw_rect(Rect2(roundi(bxp), roundi(byp), 2, 2), Color("f2e060"))
		"volleyball":
			# по бокам сетки игроки, мяч летает через сетку, бьющий подпрыгивает
			var cyc := fposmod(t * 0.7, 2.0)
			var k := fposmod(cyc, 1.0)
			var lr := int(cyc) == 0
			var xl := bx - 3.0
			var xr := bx + 19.0
			var bxp := lerpf(xl + 3.0, xr - 3.0, k if lr else 1.0 - k)
			var byp := by + 6.0 - sin(k * PI) * 12.0
			_scene_cat(0, i, "surfer", Vector2(xl, by + 15), 1, "stand", -2 if lr and k < 0.15 else 0)
			_scene_cat(1, i, "casual2", Vector2(xr, by + 15), -1, "stand", -2 if not lr and k < 0.15 else 0)
			world.draw_rect(Rect2(roundi(bxp), roundi(byp), 2, 2), Color("fff6e0"))
			world.draw_rect(Rect2(roundi(bxp), roundi(byp), 1, 1), Color("ff9f43"))
		"skatepark":
			# скейтер катается по рампе туда-сюда
			var k := sin(t * 1.4)
			var px := bx + 16.0 + k * 10.0
			var py := by + 27.0 - k * k * 9.0
			var face := 1 if cos(t * 1.4) > 0.0 else -1
			_scene_cat(0, i, "casual4", Vector2(px, py - 1), face)
			world.draw_rect(Rect2(roundi(px) - 4, roundi(py) - 1, 8, 1), Color("3b3b4a"))
			world.draw_rect(Rect2(roundi(px) - 3, roundi(py), 1, 1), Color("ffd23f"))
			world.draw_rect(Rect2(roundi(px) + 2, roundi(py), 1, 1), Color("ffd23f"))
		"playground":
			# котёнок качается на качелях
			var pv := Vector2(bx + 9, by + 12)
			var ang := sin(t * 2.2) * 0.7
			var seat := pv + Vector2(sin(ang), cos(ang)) * 9.0
			world.draw_rect(Rect2(pv.x - 6, pv.y - 1, 13, 1), Color("8a5a3b"))
			world.draw_line(pv + Vector2(-2, 0), seat + Vector2(-2, 0), Color("6a6478"), 1.0)
			world.draw_line(pv + Vector2(2, 0), seat + Vector2(2, 0), Color("6a6478"), 1.0)
			_scene_cat(0, i, "casual1", seat + Vector2(0, 2), 1 if cos(t * 2.2) > 0.0 else -1)
			world.draw_rect(Rect2(seat.x - 3, seat.y, 6, 1), Color("e45b6b"))
		"umbrella":
			# котик загорает на полотенце
			if world.hour() < 9.0 or world.hour() > 18.0:
				return
			world.draw_rect(Rect2(bx + 1, by + 11, 13, 4), Color("ff8fab"))
			world.draw_rect(Rect2(bx + 1, by + 12, 13, 1), Color("ffffff"))
			_scene_cat(0, i, "surfer", Vector2(bx + 8, by + 15), 1, "sleep")
		"fountain":
			_scene_cat(0, i, "casual3", Vector2(bx - 3, by + 15), 1)
		"icecream":
			# покупатели едят рожки
			if not _free_tile(o.i % W, o.i / W + 1):
				return
			for k in 2:
				var fx := bx + 4.0 + k * 9.0
				var fy := by + 30.0 + k
				_scene_cat(k, i, "casual%d" % ((i + k) % 6), Vector2(fx, fy), 1 if k == 0 else -1)
				var lick := int(t * 3.0 + k) % 2
				var cx := fx + (3.0 if k == 0 else -4.0)
				world.draw_rect(Rect2(cx, fy - 9 - lick, 2, 3), Color("d8a060"))
				world.draw_rect(Rect2(cx, fy - 11 - lick, 2, 2), Color("ff9fc0") if k == 0 else Color("9ed8c8"))
		"cafe", "boba", "juicebar":
			# столик на улице: двое болтают, над чашками пар
			if not _free_tile(o.i % W, o.i / W + 1):
				return
			world.draw_rect(Rect2(bx + 5, by + 22, 7, 2), Color("f4ead8"))
			world.draw_rect(Rect2(bx + 8, by + 24, 1, 5), Color("8a5a3b"))
			world.draw_rect(Rect2(bx + 6, by + 20, 1, 2), Color("ffffff"))
			world.draw_rect(Rect2(bx + 10, by + 20, 1, 2), Color("ffffff") if o.t == "cafe" else Color("c8a8ff"))
			if o.t == "cafe":
				for k in 2:
					var st := fposmod(t * 0.8 + k * 0.5, 1.0)
					world.draw_rect(Rect2(bx + 6 + k * 4 + roundi(sin(st * 6.0)), by + 19 - st * 6.0, 1, 1), Color(1, 1, 1, 0.8 * (1.0 - st)))
			_scene_cat(0, i, "casual%d" % (i % 6), Vector2(bx + 1, by + 30), 1)
			_scene_cat(1, i, "casual%d" % ((i + 3) % 6), Vector2(bx + 16, by + 30), -1)
		"pier":
			# рыбак с удочкой, поплавок качается на воде
			var wd := Vector2i(0, 0)
			for dv in DIRS:
				var nx: int = o.i % W + dv.x
				var ny: int = o.i / W + dv.y
				if world.in_map(nx, ny) and world.terrain[ny * W + nx] == WATER:
					wd = dv
					break
			if wd == Vector2i(0, 0):
				return
			var feet := Vector2(bx + 8, by + 14) + Vector2(wd) * 5.0
			_scene_cat(0, i, "fisher", feet, 1 if wd.x >= 0 else -1)
			var tip := feet + Vector2(wd.x * 6 + (3 if wd.x == 0 else 0), -12)
			world.draw_line(feet + Vector2(0, -8), tip, Color("8a5a3b"), 1.0)
			var bob := feet + Vector2(wd) * 12.0 + Vector2(0, 2 + roundi(sin(t * 3.0)))
			world.draw_line(tip, bob, Color(1, 1, 1, 0.6), 1.0)
			world.draw_rect(Rect2(bob.x, bob.y, 2, 2), Color("e0483a"))
		"surf":
			# серфер качается на волне у берега
			var wd := Vector2i(0, 0)
			for dv in DIRS:
				var nx: int = o.i % W + dv.x
				var ny: int = o.i / W + dv.y
				if world.in_map(nx, ny) and world.terrain[ny * W + nx] == WATER:
					wd = dv
					break
			if wd == Vector2i(0, 0):
				return
			var c := Vector2(bx + 8, by + 13) + Vector2(wd) * 16.0 + Vector2(sin(t * 0.5) * 4.0, sin(t * 2.0) * 1.5)
			world.draw_rect(Rect2(roundi(c.x) - 5, roundi(c.y), 10, 2), Color("ffd23f"))
			world.draw_rect(Rect2(roundi(c.x) - 6, roundi(c.y) + 2, 12, 1), Color(1, 1, 1, 0.7))
			_scene_cat(0, i, "surfer", c, 1 if wd.x >= 0 else -1)


func _draw_car(car: Dictionary) -> void:
	var v: Dictionary = world.spr.vehicle(car.kind, car.color)
	var tx: Texture2D
	var dpos = null
	var flip: bool = car.dir == "l"
	if car.dir == "r" or car.dir == "l":
		tx = v.side[1 if flip else 0]
		var ds: Vector2i = v.driver.side
		dpos = Vector2i(tx.get_width() - ds.x - 2 if flip else ds.x, ds.y)
	else:
		tx = v.front if car.dir == "d" else v.back
		if car.dir == "d":
			dpos = v.driver.front
	var sx := roundi(car.px - tx.get_width() / 2.0)
	var sy := roundi(car.py + 4 - tx.get_height())
	world.draw_rect(Rect2(sx + 2, sy + tx.get_height() - 1, tx.get_width() - 4, 1), Color(0.157, 0.118, 0.196, 0.2))
	world.draw_texture(tx, Vector2(sx, sy))
	var fur: Dictionary = D.CAT_COLORS[car.cat.color] if car.cat != null else D.CAT_COLORS[["ginger", "gray", "white", "tabby"][car.kind.length() % 4]]
	if car.get("parked", false):
		dpos = null
	if dpos != null:
		var fc := Color(fur.a)
		world.draw_rect(Rect2(sx + dpos.x, sy + dpos.y, 2, 2), fc)
		world.draw_rect(Rect2(sx + dpos.x, sy + dpos.y - 1, 1, 1), fc)
		world.draw_rect(Rect2(sx + dpos.x + 1, sy + dpos.y - 1, 1, 1), fc)
		world.draw_rect(Rect2(sx + dpos.x + (0 if flip else 1), sy + dpos.y, 1, 1), Color(fur.get("e", "2b2233")))
	if v.lights != null:
		var on := int(world.anim_time * 4.0) % 2
		var pts: Array = v.lights.side if car.dir == "r" or car.dir == "l" else v.lights.fb
		for k in pts.size():
			var lx: int = pts[k][0]
			var x: int = tx.get_width() - lx - 2 if flip else lx
			world.draw_rect(Rect2(sx + x, sy + pts[k][1], 2, 1), Color("ff4d5e") if (k + on) % 2 == 1 else Color("4d8dff"))
	if world.dark > 0.1 and not car.get("parked", false):
		var f: Vector2 = {"r": Vector2(8, 0), "l": Vector2(-8, 0), "d": Vector2(0, 6), "u": Vector2(0, -6)}[car.dir]
		lights.append(Vector3(car.px + f.x, car.py + f.y, 14))
	if car.cat != null and world.info_target != null and world.info_target.has("cat") and world.info_target.cat == car.cat:
		var bob := roundi(sin(world.anim_time * 5.0) * 1.5)
		world.draw_texture(world.spr.small.heart, Vector2(roundi(car.px) - 2, roundi(car.py) - 16 + bob))


func _draw_ghost() -> void:
	if not world.mouse_in or world.tool == "hand" or world._pan_active:
		return
	var tx := world.mouse_tile.x
	var ty := world.mouse_tile.y
	if not world.in_map(tx, ty):
		return
	if world.tool == "bulldoze":
		var o = world.obj_at(tx, ty)
		if o != null:
			world.draw_rect(Rect2(o.i % W * T, o.i / W * T, o.w * T, o.w * T), Color(1, 0.35, 0.43, 0.4))
		else:
			world.draw_rect(Rect2(tx * T, ty * T, T, T), Color(1, 1, 1, 0.2))
		return
	var d := D.def(world.tool)
	var w := D.size_of(world.tool)
	var r := world.can_place(world.tool, tx, ty)
	var rad: float = d.get("radius", d.get("sradius", 0))
	if rad > 0.0:
		var cx := tx + (w - 1) / 2.0
		var cy := ty + (w - 1) / 2.0
		var col := Color(0.7, 0.78, 1, 0.18) if d.has("sradius") else Color(1, 0.75, 0.86, 0.22)
		for y in range(int(floor(cy - rad)), int(cy + rad) + 1):
			for x in range(int(floor(cx - rad)), int(cx + rad) + 1):
				if world.in_map(x, y) and Vector2(x - cx, y - cy).length() <= rad:
					world.draw_rect(Rect2(x * T, y * T, T, T), col)
	world.draw_rect(Rect2(tx * T, ty * T, w * T, w * T), Color(0.5, 1, 0.63, 0.35) if r.ok else Color(1, 0.35, 0.43, 0.35))
	if world.tool != "path" and world.tool != "blvd" and world.tool != "road" and not d.has("terra"):
		var img: Texture2D = world.spr.tool_texture(world.tool)
		world.draw_texture(img, Vector2(tx * T + (w * T - img.get_width()) / 2, (ty + w) * T - img.get_height()), Color(1, 1, 1, 0.7))


func _draw_particles() -> void:
	for p in world.parts:
		if p.type == "firefly" or p.type == "rocket" or p.type == "spark":
			continue
		var a: float = minf(1.0, p.life / p.mx * 2.0)
		var pos := Vector2(roundi(p.x), roundi(p.y))
		var m := Color(1, 1, 1, a)
		match p.type:
			"heart":
				world.draw_texture(world.spr.small.heart, pos - Vector2(2, 2), m)
			"z":
				world.draw_texture(world.spr.small.z, pos, m)
			"sparkle":
				world.draw_texture(world.spr.small.sparkle, pos - Vector2(1, 1), m)
			"coin":
				world.draw_texture(world.spr.icons.coin, pos - Vector2(4, 4), m)
			"petal":
				world.draw_rect(Rect2(pos, Vector2(2, 1)), Color(0.8, 0.7, 0.96, a))
			"drop":
				world.draw_rect(Rect2(pos, Vector2(1, 2)), Color(0.75, 0.91, 0.96, a))
			"dust":
				world.draw_rect(Rect2(pos, Vector2(2, 2)), Color(0.94, 0.89, 0.81, a))
			"note":
				var nc := Color(p.col)
				nc.a = a
				world.draw_rect(Rect2(pos.x, pos.y + 3, 2, 2), nc)
				world.draw_rect(Rect2(pos.x + 1, pos.y, 1, 4), nc)
				world.draw_rect(Rect2(pos.x + 2, pos.y, 1, 1), nc)
			"balloon":
				var bc := Color(p.col)
				bc.a = a
				world.draw_rect(Rect2(pos.x - 1, pos.y - 4, 3, 4), bc)
				world.draw_rect(Rect2(pos.x, pos.y - 5, 1, 1), bc)
				world.draw_rect(Rect2(pos.x, pos.y, 1, 4), Color(INK, a * 0.6))
			"confetti":
				var cc := Color(p.col)
				cc.a = a
				world.draw_rect(Rect2(pos, Vector2(2 if int(p.life * 8.0) % 2 == 0 else 1, 1)), cc)
			"flash":
				world.draw_rect(Rect2(pos.x - 1, pos.y - 1, 3, 3), Color(1, 1, 1, a))
				world.draw_rect(Rect2(pos.x - 3, pos.y, 7, 1), Color(1, 1, 1, a * 0.6))
				world.draw_rect(Rect2(pos.x, pos.y - 3, 1, 7), Color(1, 1, 1, a * 0.6))
			"smoke":
				var r: float = 2.0 + (1.0 - p.life / p.mx) * 3.0
				world.draw_rect(Rect2(roundi(pos.x - r), roundi(pos.y - r), roundi(r * 2), roundi(r * 2)), Color(0.91, 0.9, 0.94, a * 0.7))
			"gull":
				var up := int(p.life * 5.0 + p.ph) % 2 == 1
				var gc := Color(1, 1, 1, a)
				world.draw_rect(Rect2(pos.x, pos.y, 1, 1), gc)
				world.draw_rect(Rect2(pos.x - 1, pos.y - (1 if up else 0), 1, 1), gc)
				world.draw_rect(Rect2(pos.x + 1, pos.y - (1 if up else 0), 1, 1), gc)
				world.draw_rect(Rect2(pos.x - 2, pos.y - (2 if up else 0), 1, 1), gc)
				world.draw_rect(Rect2(pos.x + 2, pos.y - (2 if up else 0), 1, 1), gc)
			"bfly":
				var col := Color(p.col)
				col.a = a
				var open := int(p.life * 8.0) % 2 == 1
				world.draw_rect(Rect2(pos.x - (2 if open else 1), pos.y, 2 if open else 1, 2), col)
				world.draw_rect(Rect2(pos.x + 1, pos.y, 2 if open else 1, 2), col)
				world.draw_rect(Rect2(pos.x, pos.y, 1, 2), INK)
