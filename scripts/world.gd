extends Node2D
## Мир Котограда: карта, постройки, котики, машины, экономика и отрисовка.

const D = preload("res://scripts/defs.gd")
const Goals = preload("res://scripts/goals.gd")
const Events = preload("res://scripts/events.gd")
const Transit = preload("res://scripts/transit.gd")
const Boats = preload("res://scripts/boats.gd")
const I18n = preload("res://scripts/i18n.gd")
const W := D.W
const H := D.H
const T := D.T
const GRASS := 0
const WATER := 1
const SAND := 2
const HILL := 3
const MOUNTAIN := 4
const DRY := 5
const MEADOW := 6
const DAY_LEN := 360.0
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const ZOOM_MIN := 1
const ZOOM_MAX := 6
const INK := Color("3b2a3a")

## Файл сохранения. Переменная окружения KOTO_SAVE позволяет тестам не трогать город игрока.
var SAVE_PATH: String = OS.get_environment("KOTO_SAVE") if OS.has_environment("KOTO_SAVE") else "user://kotograd_save.json"
var spr
var sound
var ui
var cam: Camera2D

# --- сохраняемое состояние ---
var map_seed := 0
var terrain := PackedByteArray()
var objs: Array = []
var coins := 2000.0
## Настройка «Неограниченные ресурсы»: стройка и улучшения бесплатны и без ограничений.
var unlimited := false
var food := 10.0
var time := 0.04
var day := 1
var cats: Array = []
var max_cats := 0
var next_id := 1
var speed := 1
var spawn_t := 0.0
var pet_bonus := 0.0
var used_names: Array = []
var city_name := "Котоград"
var pets_total := 0
var events_seen := 0
var deliveries := 0              # сколько раз грузовики привезли товар
var exported := 0                # сколько товара продано через грузовой порт
var goals
var events
var transit
var boats
var _goal_t := 0.0
var _amb_t := 0.0
# сенсорное управление: два пальца — двигать и масштабировать карту
var _touches := {}
var _pinch_d := 0.0
var _pinch_mid := Vector2.ZERO
var _touch_pending := false
# перекрёстки со светофорами, пешеходные переходы и въезды на магистраль
var junctions := {}
var crosswalks := {}
var crossings := {}
var pairs := {}              # объединённые соседние здания: клетка -> "L" или "R"
var ramps: Array = []
var _light_clock := 0.0
const LIGHT_CYCLE := 9.0
const FLAT := ["pawtile", "boatdock", "parking", "tennis", "volleyball", "skatepark", "helipad"]

# --- производное / временное ---
var stats := {}
var residents := {}
var workers := {}
var inside_count := {}
var lot_count := {}
var lot_colors := {}
var street_parked: Array = []
var jammed := 0
var happy := 50.0
var hungry := false
var income := 0.0
var tourism := 0.0
var eat_rate := 0.0
var tool := "hand"
var terrain_img: Image
var terrain_tex: ImageTexture
var dirty_tiles := {}
var cars: Array = []
var parts: Array = []
var floats: Array = []
var info_target = null
var anim_time := 0.0
var lights: Array = []
var dark := 0.0
var zoom := 3

var _job_t := 0.0
var _service_t := 0.0
var _freight_t := 0.0
var _ambient_t := 0.0
var _save_t := 0.0
var _had_goals := false
var _pan_active := false
var _pan_moved := false
var _pan_button := 0
var _pan_start := Vector2.ZERO
var _pan_cam := Vector2.ZERO
var _painting := false
var _last_paint := -1
var _cong := {}                  # клетка -> сколько машин там стоит (для объезда пробок)
var _last_reason_ms := 0
var mouse_tile := Vector2i(-1, -1)
var mouse_in := false


# =====================================================================
#  Запуск, сохранение
# =====================================================================

func setup(sprites, snd, user_interface, camera: Camera2D) -> bool:
	spr = sprites
	sound = snd
	ui = user_interface
	cam = camera
	terrain_img = Image.create_empty(W * T, H * T, false, Image.FORMAT_RGBA8)
	goals = Goals.new(self)
	events = Events.new(self)
	transit = Transit.new(self)
	boats = Boats.new(self)
	var loaded := load_game()
	if not loaded:
		new_game()
	_render_terrain_full()
	terrain_tex = ImageTexture.create_from_image(terrain_img)
	rebuild_maps()
	if loaded and not _had_goals:
		goals.sync_silently()
	return loaded


func new_game() -> void:
	map_seed = randi()
	coins = 2000.0
	food = 10.0
	time = 0.04
	day = 1
	cats = []
	max_cats = 0
	next_id = 1
	speed = 1
	spawn_t = 0.0
	pet_bonus = 0.0
	used_names = []
	cars = []
	info_target = null
	pets_total = 0
	events_seen = 0
	deliveries = 0
	exported = 0
	goals.done = {}
	events.active = null
	events.visitors = []
	events.cool = 4.0
	transit.trains = []
	transit.planes = []
	transit.helis = []
	transit.rides = 0
	_gen_map(map_seed)
	zoom = 3
	_apply_zoom()
	var st := start_spot()
	center_cam(st.x, st.y)
	recalc()
	rebuild_maps()
	if terrain_tex:
		_render_terrain_full()
		terrain_tex.update(terrain_img)


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(serialize())


func serialize() -> String:
	var mains := []
	for i in W * H:
		var o = objs[i]
		if o != null and o.i == i:
			var m := [i, o.t, o.v, snappedf(o.build, 0.1), int(o.get("lvl", 1)), -1]
			if o.has("stock") or o.has("out"):
				var st := {}
				for g in o.get("stock", {}):
					st[g] = snappedf(o.stock[g], 0.1)
				m.append({"s": st, "o": snappedf(o.get("out", 0.0), 0.1)})
			mains.append(m)
	var cat_list := []
	for c in cats:
		var k: Dictionary = c.duplicate()
		k["path"] = []
		k["dest"] = null
		k["plan"] = null
		if c.state == "drive":
			k["state"] = "in"
			k["at"] = c.dest.b if c.dest != null and c.dest.has("b") and objs[c.dest.b] != null else c.home
			k["car_lot"] = -1
			k["car_tile"] = -1
		k["trip"] = null
		if c.state == "ride":
			var tp = c.get("trip")
			var to: int = tp.to if tp != null and objs[tp.to] != null else c.home
			k["state"] = "in" if to >= 0 and objs[to] != null else "idle"
			k["at"] = to
		if c.state == "walk":
			k["state"] = "idle"
			k["x"] = roundf(c.x)
			k["y"] = roundf(c.y)
		cat_list.append(k)
	var data := {
		"v": 5, "seed": map_seed, "terrain": Array(terrain), "objs": mains, "coins": coins, "food": food,
		"time": time, "day": day, "cats": cat_list, "max_cats": max_cats, "next_id": next_id, "speed": speed,
		"used_names": used_names, "cam": [cam.position.x, cam.position.y, zoom],
		"name": city_name, "goals": goals.done.keys(), "pets": pets_total, "events": events_seen, "rides": transit.rides,
		"deliveries": deliveries, "exported": exported,
	}
	return JSON.stringify(data)


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	return deserialize(f.get_as_text())


## Импорт сохранения из файла (меню настроек).
func import_save(text: String) -> bool:
	if not deserialize(text):
		return false
	cars = []
	info_target = null
	_render_terrain_full()
	terrain_tex.update(terrain_img)
	rebuild_maps()
	if not _had_goals:
		goals.sync_silently()
	save_game()
	return true


## Сохранение с прежней маленькой карты: город переезжает в центр большой.
func _migrate_small(d: Dictionary) -> void:
	var ox: int = (W - D.OLD_W) / 2
	var oy: int = (H - D.OLD_H) / 2
	var remap := func(i) -> int:
		var ii := int(i)
		if ii < 0:
			return ii
		return (ii / D.OLD_W + oy) * W + (ii % D.OLD_W + ox)
	var t: Array = []
	t.resize(W * H)
	t.fill(WATER)
	for y in D.OLD_H:
		for x in D.OLD_W:
			t[(y + oy) * W + x + ox] = d.terrain[y * D.OLD_W + x]
	d.terrain = t
	for m in d.objs:
		m[0] = remap.call(m[0])
	for c in d.cats:
		for k in ["home", "job", "at", "car_lot", "car_tile"]:
			if c.has(k):
				c[k] = remap.call(c[k])
		for k in ["x", "ax", "lx"]:
			if c.has(k):
				c[k] = float(c[k]) + ox
		for k in ["y", "ay", "ly"]:
			if c.has(k):
				c[k] = float(c[k]) + oy
	if d.has("cam"):
		d.cam = [float(d.cam[0]) + ox * T, float(d.cam[1]) + oy * T, d.cam[2]]


func deserialize(text: String) -> bool:
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY or int(d.get("v", 0)) != 5:
		return false
	if not d.has("terrain"):
		return false
	if d.terrain.size() == D.OLD_W * D.OLD_H:
		_migrate_small(d)
	if d.terrain.size() != W * H:
		return false
	map_seed = int(d.seed)
	terrain = PackedByteArray(d.terrain)
	objs = []
	objs.resize(W * H)
	for m in d.objs:
		if not D.DEFS.has(str(m[1])):
			continue
		var o := place_obj(int(m[0]), str(m[1]), int(m[2]), float(m[3]))
		if m.size() > 4:
			o["lvl"] = int(m[4])
		if m.size() > 6 and typeof(m[6]) == TYPE_DICTIONARY:
			var st := {}
			for g in m[6].get("s", {}):
				# товары, которых больше нет в игре, просто забываем
				if D.GOODS.has(g):
					st[g] = float(m[6].s[g])
			o["stock"] = st
			o["out"] = float(m[6].get("o", 0.0))
	coins = float(d.coins)
	food = float(d.food)
	time = float(d.time)
	day = int(d.day)
	max_cats = int(d.max_cats)
	next_id = int(d.next_id)
	speed = int(d.speed)
	used_names = d.used_names
	city_name = str(d.get("name", "Котоград"))
	pets_total = int(d.get("pets", 0))
	events_seen = int(d.get("events", 0))
	deliveries = int(d.get("deliveries", 0))
	exported = int(d.get("exported", 0))
	transit.rides = int(d.get("rides", 0))
	transit.trains = []
	transit.planes = []
	transit.helis = []
	_had_goals = d.has("goals")
	goals.done = {}
	for g in d.get("goals", []):
		goals.done[str(g)] = true
	events.active = null
	events.visitors = []
	cats = []
	for c in d.cats:
		for k in ["id", "home", "job", "at", "casual", "dir", "lx", "ly", "pi", "car_lot", "car_tile"]:
			c[k] = int(c.get(k, -1))
		c["near_car"] = false
		c["path"] = []
		c["dest"] = null
		c["plan"] = null
		c["fail_until"] = 0.0
		c["trip"] = null
		cats.append(c)
	var cm: Array = d.get("cam", [W * T / 2.0, H * T / 2.0, 3])
	zoom = int(cm[2])
	_apply_zoom()
	cam.position = Vector2(cm[0], cm[1])
	recalc()
	return true


# =====================================================================
#  Генерация карты
# =====================================================================

static func hashf(x: int, y: int, s: int = 0) -> float:
	var h: int = (x * 374761393 + y * 668265263 + s * 982451653) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h) / 4294967296.0


## Контур острова — как карта Сан-Андреаса из GTA V (x, y в долях рамки; север сверху).
const SA_SHAPE := [
	Vector2(0.40, 0.00), Vector2(0.52, 0.03), Vector2(0.64, 0.08), Vector2(0.77, 0.12), Vector2(0.89, 0.20),
	Vector2(0.96, 0.30), Vector2(0.98, 0.40), Vector2(0.93, 0.48), Vector2(0.86, 0.55), Vector2(0.81, 0.62),
	Vector2(0.84, 0.70), Vector2(0.80, 0.80), Vector2(0.73, 0.90), Vector2(0.63, 0.97), Vector2(0.50, 1.00),
	Vector2(0.38, 0.98), Vector2(0.27, 0.93), Vector2(0.18, 0.88), Vector2(0.10, 0.84), Vector2(0.07, 0.77),
	Vector2(0.15, 0.70), Vector2(0.22, 0.62), Vector2(0.19, 0.55), Vector2(0.11, 0.48), Vector2(0.04, 0.40),
	Vector2(0.02, 0.30), Vector2(0.08, 0.20), Vector2(0.18, 0.12), Vector2(0.28, 0.05),
]
# рамка острова на карте (в клетках)
const SA_X0 := 37
const SA_Y0 := 6
const SA_W := 52
const SA_H := 78


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


## Клетка-центр Лос-Сантоса — отсюда начинается город.
func start_spot() -> Vector2:
	return Vector2(SA_X0 + SA_W * 0.5, SA_Y0 + SA_H * 0.84)


func _gen_map(s: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	terrain = PackedByteArray()
	terrain.resize(W * H)
	terrain.fill(WATER)
	objs = []
	objs.resize(W * H)
	var sm := s % 100000
	# остров в форме Сан-Андреаса: север — Палето-Бей и гора Чилиад, середина — пустыня и озеро Аламо,
	# восток — горы, юг — Лос-Сантос с холмами Вайнвуда и пляжами Веспуччи
	for y in H:
		for x in W:
			var u := (x + 0.5 - SA_X0) / SA_W
			var v := (y + 0.5 - SA_Y0) / SA_H
			if u < -0.05 or u > 1.05 or v < -0.05 or v > 1.05:
				continue
			var jit := Vector2(hashf(x, y, sm) - 0.5, hashf(x, y, sm + 7) - 0.5) * 0.025
			var p := Vector2(u, v) + jit
			if not _in_poly(p, SA_SHAPE):
				continue
			var i := y * W + x
			terrain[i] = GRASS
			# пляж по краю
			var edge := false
			for d in [Vector2(0.03, 0), Vector2(-0.03, 0), Vector2(0, 0.02), Vector2(0, -0.02)]:
				if not _in_poly(p + d, SA_SHAPE):
					edge = true
			if edge:
				terrain[i] = SAND
				continue
			var n := hashf(x / 3, y / 3, sm + 3)
			# гора Чилиад на северо-западе
			var chil := Vector2((u - 0.28) / 0.13, (v - 0.17) / 0.09).length()
			if chil < 0.6:
				terrain[i] = MOUNTAIN
			elif chil < 1.0:
				terrain[i] = HILL
			# леса Палето на севере
			elif v < 0.22 and n < 0.55:
				terrain[i] = MEADOW
			# горы Татавиам на востоке
			elif Vector2((u - 0.83) / 0.11, (v - 0.57) / 0.15).length() + (n - 0.5) * 0.4 < 1.0:
				terrain[i] = MOUNTAIN if Vector2((u - 0.84) / 0.07, (v - 0.57) / 0.1).length() < 1.0 else HILL
			# гора Гордо на северо-востоке
			elif Vector2((u - 0.86) / 0.08, (v - 0.27) / 0.07).length() < 1.0:
				terrain[i] = HILL
			# пустыня Гранд-Сенора в середине
			elif Vector2((u - 0.57) / 0.25, (v - 0.45) / 0.16).length() + (n - 0.5) * 0.45 < 1.0:
				terrain[i] = DRY
			# холмы Вайнвуда над городом
			elif Vector2((u - 0.52) / 0.2, (v - 0.665) / 0.04).length() + (n - 0.5) * 0.5 < 1.0:
				terrain[i] = HILL
			# озеро Аламо-Си
			if Vector2((u - 0.56) / 0.13, (v - 0.40) / 0.045).length() < 1.0:
				terrain[i] = WATER
	# природа: пальмы у Лос-Сантоса и на пляжах, агавы в пустыне, камни в горах
	var spots := []
	var center := start_spot()
	for y in H:
		for x in W:
			var t: int = terrain[y * W + x]
			if t != WATER and Vector2(x, y).distance_to(center) > 7.0:
				spots.append(Vector2i(x, y))
	spots.shuffle()
	var placed := 0
	for p in spots:
		if placed >= 120:
			break
		var t: int = terrain[p.y * W + p.x]
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
			place_obj(p.y * W + p.x, kind, rng.randi() % 3, 0.0)
			placed += 1


# =====================================================================
#  Объекты на карте
# =====================================================================

static func in_map(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func obj_at(x: int, y: int):
	return objs[y * W + x] if in_map(x, y) else null


func place_obj(i: int, t: String, v: int, build: float) -> Dictionary:
	var w := D.size_of(t)
	var o := {"t": t, "v": v, "i": i, "w": w, "build": build, "lvl": 1}
	var x0 := i % W
	var y0 := i / W
	for y in range(y0, y0 + w):
		for x in range(x0, x0 + w):
			objs[y * W + x] = o
	mark_dirty(x0, y0, w)
	return o


func remove_obj(o: Dictionary) -> void:
	var x0: int = o.i % W
	var y0: int = o.i / W
	for y in range(y0, y0 + o.w):
		for x in range(x0, x0 + o.w):
			objs[y * W + x] = null
	mark_dirty(x0, y0, o.w)


## Клетки вокруг постройки (сначала снизу — там «дверь»).
func around(b: int) -> Array:
	var o = objs[b]
	var w: int = o.w if o != null else 1
	var x0 := b % W
	var y0 := b / W
	var out := []
	for x in range(x0, x0 + w):
		out.append(Vector2i(x, y0 + w))
	for y in range(y0, y0 + w):
		out.append(Vector2i(x0 - 1, y))
		out.append(Vector2i(x0 + w, y))
	for x in range(x0, x0 + w):
		out.append(Vector2i(x, y0 - 1))
	return out.filter(func(p): return in_map(p.x, p.y))


func is_ready(b: int) -> bool:
	if b < 0 or b >= W * H:
		return false
	var o = objs[b]
	return o != null and o.i == b and o.build <= 0.0


func center_of(b: int) -> Vector2:
	var o = objs[b]
	var w: int = o.w if o != null else 1
	return Vector2(b % W + (w - 1) / 2.0, b / W + (w - 1) / 2.0)


## Обычная дорога (к ней подключаются здания, на ней можно оставить машину).
func is_road(x: int, y: int) -> bool:
	var o = obj_at(x, y)
	return o != null and (o.t == "road" or o.t == "crossing")


## Любая проезжая часть: дорога, переезд или магистраль.
func is_drivable(x: int, y: int) -> bool:
	var o = obj_at(x, y)
	return o != null and (o.t == "road" or o.t == "highway" or o.t == "crossing")


func is_rail(x: int, y: int) -> bool:
	var o = obj_at(x, y)
	return o != null and (o.t == "rail" or o.t == "crossing")


func is_highway(x: int, y: int) -> bool:
	var o = obj_at(x, y)
	return o != null and o.t == "highway"


func is_high(i: int) -> bool:
	return terrain[i] == HILL or terrain[i] == MOUNTAIN


# ---------- уровни зданий ----------
const LVL_CAP := ["cap", "jobs", "parking", "store_coins", "store_food"]


## Характеристика здания с учётом уровня улучшения.
func stat(o, key: String, default = 0):
	var d := D.def(o.t)
	if not d.has(key):
		return default
	var v = d[key]
	var lvl := int(o.get("lvl", 1))
	if lvl <= 1 or typeof(v) == TYPE_BOOL:
		return v
	var k := 0.5 if key in LVL_CAP else 0.35
	var r := float(v) * (1.0 + k * (lvl - 1))
	if key == "cap" or key == "jobs" or key == "parking":
		return roundi(r)
	return r


func upgrade_cost(b: int) -> int:
	var o = objs[b]
	if o == null:
		return -1
	var ups: Array = D.ups(o.t)
	var lvl := int(o.get("lvl", 1))
	if lvl - 1 >= ups.size():
		return -1
	# объединённая пара улучшается целиком — платим за обе половинки
	return int(ups[lvl - 1]) * (2 if pair_mate(b) >= 0 else 1)


## Вторая половинка объединённого здания (или -1).
func pair_mate(b: int) -> int:
	match pairs.get(b, ""):
		"L":
			return b + 1
		"R":
			return b - 1
	return -1


func upgrade(b: int) -> bool:
	var cost := upgrade_cost(b)
	if cost < 0 or not is_ready(b):
		return false
	if unlimited:
		cost = 0
	if coins < cost:
		return false
	coins -= cost
	var o = objs[b]
	var mate := pair_mate(b)
	o["lvl"] = int(o.get("lvl", 1)) + 1
	if mate >= 0 and objs[mate] != null:
		objs[mate]["lvl"] = o.lvl
		mark_dirty(mate % W, mate / W, 1)
	var cp := center_of(b) * T + Vector2(8, 0)
	for k in 16:
		add_p({"type": "sparkle", "x": cp.x + randf_range(-12, 12), "y": cp.y + randf_range(-16, 8), "vx": randf_range(-25, 25), "vy": randf_range(-40, -10), "life": randf_range(0.7, 1.4)})
	float_text(cp + Vector2(0, -14), tr("%s — уровень %d!") % [tr(D.def(o.t).name), o.lvl], Color("c08a1a"))
	sound.play("chime")
	recalc()
	return true


func walkable_idx(i: int) -> bool:
	var o = objs[i]
	if o != null:
		return D.def(o.t).get("walk", false)
	return terrain[i] != WATER


## Пешеходу можно стоять/идти здесь, не выходя на проезжую часть.
func foot_ok(i: int) -> bool:
	var o = objs[i]
	if o != null and (o.t == "road" or o.t == "rail" or o.t == "crossing"):
		return false
	return walkable_idx(i)


func bname(b: int) -> String:
	if b >= 0 and b < W * H and objs[b] != null:
		return tr(D.def(objs[b].t).get("name", "—"))
	return "—"


# =====================================================================
#  Экономика
# =====================================================================

func recalc() -> void:
	var st := {
		"cap": 0, "jobs": 0, "houses": [], "workplaces": [], "leisure": [], "strolls": [], "vehicle_bases": [],
		"constructing": [], "builder_yards": [], "house_happy": {}, "food_prod": stats.get("food_prod", 0.0), "wonders": [], "lots": [], "tourists": [], "hubs": [],
		"coin_cap": 3000.0, "food_cap": 150.0, "sinks": {}, "depots": [], "ports": [],
	}
	var decor := []
	var services := []
	for i in W * H:
		var o = objs[i]
		if o == null or o.i != i:
			continue
		if o.build > 0.0:
			st.constructing.append(i)
			continue
		var d := D.def(o.t)
		if d.has("cap"):
			st.cap += stat(o, "cap")
			st.houses.append(i)
		if d.has("jobs"):
			st.jobs += stat(o, "jobs")
			st.workplaces.append(i)
		if d.has("tourism"):
			st.tourists.append(i)
		st.coin_cap += float(stat(o, "store_coins", 0))
		st.food_cap += float(stat(o, "store_food", 0))
		if d.get("leisure", false):
			st.leisure.append(i)
		if d.get("stroll", false):
			st.strolls.append(i)
		if d.has("vehicle"):
			st.vehicle_bases.append(i)
		if d.get("builders", false):
			st.builder_yards.append(i)
		if d.get("wonder", false):
			st.wonders.append(i)
		if d.has("parking"):
			st.lots.append(i)
		if d.has("happy"):
			decor.append(i)
		if d.has("service"):
			services.append(i)
		if d.has("hub"):
			st.hubs.append(i)
		for g in needs_of(o.t):
			if not st.sinks.has(g):
				st.sinks[g] = []
			st.sinks[g].append(i)
		if d.get("depot", false):
			st.depots.append(i)
		if d.get("export", false):
			st.ports.append(i)
	for h in st.houses:
		var c := center_of(h)
		var v := 30.0
		for di in decor:
			var d := D.def(objs[di].t)
			if center_of(di).distance_to(c) <= d.radius + 0.5:
				v += float(stat(objs[di], "happy"))
		for si in services:
			var d := D.def(objs[si].t)
			if center_of(si).distance_to(c) <= d.sradius:
				v += float(stat(objs[si], "service"))
		# дом на холме или в горах — красивый вид
		if terrain[h] == MOUNTAIN:
			v += 12.0
		elif terrain[h] == HILL:
			v += 6.0
		if _next_to(h, "road"):
			v += 5.0
		if _next_to(h, "blvd"):
			v += 8.0
		elif _next_to(h, "path"):
			v += 5.0
		st.house_happy[h] = minf(100.0, v)
	stats = st
	_compute_roads()


func _drivable_n(x: int, y: int) -> int:
	var n := 0
	for dv in DIRS:
		if is_drivable(x + dv.x, y + dv.y):
			n += 1
	return n


## Перекрёсток — обычная дорога, где сходятся 3–4 проезжие части (там ставим светофор).
func is_junction(x: int, y: int) -> bool:
	return is_road(x, y) and _drivable_n(x, y) >= 3


## Пешеходный переход — клетка дороги прямо у перекрёстка.
func is_crosswalk(x: int, y: int) -> bool:
	if not is_road(x, y) or is_junction(x, y):
		return false
	for dv in DIRS:
		if is_junction(x + dv.x, y + dv.y):
			return true
	return false


func _compute_roads() -> void:
	junctions = {}
	crosswalks = {}
	crossings = {}
	ramps = []
	for i in W * H:
		var o = objs[i]
		if o != null and o.t == "crossing":
			crossings[i] = true
			continue
		if o == null or o.t != "road":
			continue
		var x := i % W
		var y := i / W
		if is_junction(x, y):
			junctions[i] = true
		elif is_crosswalk(x, y):
			crosswalks[i] = true
		for dv in DIRS:
			if is_highway(x + dv.x, y + dv.y):
				ramps.append([i, dv])
				break
	if transit != null:
		transit.rebuild()
	_compute_pairs()


func _pairable(o) -> bool:
	if o == null or o.w != 1 or o.build > 0.0:
		return false
	var d := D.def(o.t)
	return (d.has("cap") or d.has("jobs")) and spr.has_pair(o.t)


## Два одинаковых маленьких здания одного уровня рядом по горизонтали рисуются как одно.
func _compute_pairs() -> void:
	pairs = {}
	for y in H:
		var x := 0
		while x < W - 1:
			var i := y * W + x
			var a = objs[i]
			var b = objs[i + 1]
			if _pairable(a) and _pairable(b) and a.t == b.t and int(a.get("lvl", 1)) == int(b.get("lvl", 1)):
				pairs[i] = "L"
				pairs[i + 1] = "R"
				x += 2
			else:
				x += 1


## Сигнал светофора для машины: 2 — зелёный, 1 — жёлтый, 0 — красный.
func light_state(i: int, horizontal: bool) -> int:
	var ph := fposmod(_light_clock + hashf(i % W, i / W, 5) * LIGHT_CYCLE, LIGHT_CYCLE)
	var half := LIGHT_CYCLE / 2.0
	if not horizontal:
		ph = fposmod(ph + half, LIGHT_CYCLE)
	if ph < half - 0.8:
		return 2
	if ph < half:
		return 1
	return 0


## Машина перед перекрёстком на красный, перед въездом на магистраль, где едут другие,
## или перед перекрёстком/переездом, за которым нет места («не запирай перекрёсток»).
func _must_stop(car: Dictionary) -> bool:
	car["blk"] = null
	var route: Array = car.route
	if car.k + 1 >= route.size() or car.prog < 0.4:
		return false
	var a: Vector2i = route[car.k]
	var b: Vector2i = route[car.k + 1]
	var ai := a.y * W + a.x
	var bi := b.y * W + b.x
	var box := (junctions.has(bi) and not junctions.has(ai)) or (crossings.has(bi) and not crossings.has(ai))
	# правила перекрёстка — только перед въездом; кто уже внутри, тот освобождает его
	if box and car.prog >= 0.5:
		box = false
	if box and crossings.has(bi) and not crossings.has(ai) and transit.closed.has(bi):
		return true
	if box and junctions.has(bi):
		var stt := light_state(bi, car.dir == "r" or car.dir == "l")
		if stt == 0 or (stt == 1 and car.prog < 0.7):
			return true
		# поперёк перекрёстка ещё кто-то едет — пропускаем
		var fwd_v: Vector2 = DIR_VEC[car.dir]
		for o in cars:
			if not is_same(o, car) and _tile_of(o) == bi and absf((DIR_VEC[o.dir] as Vector2).dot(fwd_v)) < 0.5:
				car["blk"] = o
				return true
	if box and car.k + 2 < route.size():
		var c2: Vector2i = route[car.k + 2]
		var blocker = _exit_blocked(car, c2, c2 - b)
		if blocker != null:
			car["blk"] = blocker
			return true
	if is_road(a.x, a.y) and is_highway(b.x, b.y):
		# въезд на магистраль: уступаем тем, кто уже едет
		var bc := Vector2(b.x * T + 8.0, b.y * T + 8.0)
		for o in cars:
			if not is_same(o, car) and o.get("hw", false) and Vector2(o.bx, o.by).distance_to(bc) < 20.0:
				return true
	return false


func _tile_of(car: Dictionary) -> int:
	return int(car.by / T) * W + int(car.bx / T)


## Стоит ли машина в начале клетки за перекрёстком (тогда въезжать некуда).
func _exit_blocked(car: Dictionary, t: Vector2i, dv: Vector2i):
	var ti := t.y * W + t.x
	var v := Vector2(dv)
	var entry := Vector2(t.x * T + 8.0, t.y * T + 8.0) - v * 8.0
	for o in cars:
		if is_same(o, car) or not o.get("stopped", false) or _tile_of(o) != ti:
			continue
		if (DIR_VEC[o.dir] as Vector2).dot(v) < -0.5:
			continue
		if (Vector2(o.bx, o.by) - entry).dot(v) < 12.0:
			return o
	return null


func _next_to(b: int, t: String) -> bool:
	for p in around(b):
		var o = obj_at(p.x, p.y)
		if o != null and o.t == t:
			return true
	return false


func rebuild_maps() -> void:
	residents = {}
	workers = {}
	inside_count = {}
	for c in cats:
		if c.home >= 0:
			if not residents.has(c.home):
				residents[c.home] = []
			residents[c.home].append(c)
		if c.job >= 0:
			if not workers.has(c.job):
				workers[c.job] = []
			workers[c.job].append(c)
		if c.state == "in":
			inside_count[c.at] = inside_count.get(c.at, 0) + 1
	lot_count = {}
	lot_colors = {}
	street_parked = []
	for c in cats:
		if c.car == "":
			continue
		_validate_car(c)
		if c.car_lot >= 0:
			lot_count[c.car_lot] = lot_count.get(c.car_lot, 0) + 1
			if not lot_colors.has(c.car_lot):
				lot_colors[c.car_lot] = []
			lot_colors[c.car_lot].append(c.car)
		elif c.car_tile >= 0:
			street_parked.append(c)
	for car in cars:
		if car.get("mode", "") == "lot":
			lot_count[car.lot] = lot_count.get(car.lot, 0) + 1


func town_happiness() -> float:
	var sum := 0.0
	var w := 0.0
	for h in stats.houses:
		var n: int = residents.get(h, []).size()
		var ww := float(n) if n > 0 else 0.3
		sum += stats.house_happy[h] * ww
		w += ww
	var v := sum / w if w > 0.0 else 50.0
	v -= minf(20.0, homeless_count() * 3.0)
	v -= minf(10.0, street_parked.size() * 0.5 + jammed * 0.5)
	if hungry:
		v -= 25.0
	v += pet_bonus
	v += events.happy_bonus()
	return clampf(v, 0.0, 100.0)


func homeless_count() -> int:
	var n := 0
	for c in cats:
		if c.home < 0:
			n += 1
	return n


## Точка, вокруг которой гуляет котик: его дом или место, где он ждёт новый дом.
func anchor_of(c: Dictionary) -> Vector2:
	if c.home >= 0 and objs[c.home] != null:
		return center_of(c.home)
	return Vector2(c.get("ax", c.x), c.get("ay", c.y))


func _cat_center(c: Dictionary) -> Vector2:
	if c.at >= 0 and objs[c.at] != null:
		return center_of(c.at)
	return anchor_of(c)


func _assign_homes() -> void:
	for c in cats:
		if c.home >= 0:
			continue
		var fh := free_houses()
		if fh.is_empty():
			return
		var cp := Vector2(c.x, c.y)
		fh.sort_custom(func(a, b): return center_of(a).distance_to(cp) < center_of(b).distance_to(cp))
		c.home = fh[0]
		rebuild_maps()
		hearts_at(cat_pos(c) + Vector2(0, -12), 3)
		ui.toast(tr("%s нашёл новый дом!") % I18n.cat(c.name), false, true)


func employed_count() -> int:
	var n := 0
	for c in cats:
		if c.job >= 0:
			n += 1
	return n


func _update_economy(dt: float) -> void:
	var n := cats.size()
	var fp := 0.0
	var shop_income := 0.0
	var employed := 0
	tourism = 0.0
	for b in stats.tourists:
		tourism += float(stat(objs[b], "tourism"))
	for b in stats.workplaces:
		var o = objs[b]
		var d := D.def(o.t)
		var nw: int = workers.get(b, []).size()
		employed += nw
		var boost := _produce(o, nw, dt)
		if d.has("food"):
			fp += (float(stat(o, "food")) + float(stat(o, "food_per", 0.0)) * nw) * (1.0 + (boost - 1.0) * 0.8)
		if d.has("shop") and nw > 0:
			shop_income += float(stat(o, "shop")) * (0.6 + 0.4 * nw / float(stat(o, "jobs"))) * boost
		elif boost > 1.0 and nw > 0:
			# стройконтора, архитекторы и другие без магазина: материалы — это премия работникам
			shop_income += nw * 0.3 * (boost - 1.0)
	stats.food_prod = fp
	eat_rate = n * 0.04
	food = clampf(food + (fp - eat_rate) * dt, 0.0, maxf(stats.food_cap, food))
	hungry = food <= 0.01 and eat_rate > fp
	pet_bonus = maxf(0.0, pet_bonus - dt * 0.05)
	happy = town_happiness()
	var mult: float = (0.5 + happy / 100.0) * 0.75 * (1.0 + events.income_bonus())
	income = (employed * 0.35 + (n - employed) * 0.08 + shop_income + tourism) * mult
	if coins < stats.coin_cap:
		coins = minf(stats.coin_cap, coins + income * dt)
	if n < stats.cap and happy >= 20.0:
		spawn_t += dt * (0.4 + happy / 100.0)
		if spawn_t >= 11.0:
			spawn_t = 0.0
			spawn_cat()


# =====================================================================
#  Производственные цепочки и грузовики
# =====================================================================

const OUT_CAP := 16.0
const IN_CAP := 16.0
const USE_CAP := 10.0
const DEPOT_CAP := 40.0
const MAKE_RATE := 0.1           # единиц товара в секунду при полном штате
const USE_RATE := 0.02           # сколько товара расходует магазин или кафе в секунду
const TRUCK_LOAD := 8


## Какие товары здание принимает: сырьё для переработки или товары для продажи.
func needs_of(t: String) -> Array:
	var out: Array = D.USES.get(t, []).duplicate()
	if D.MAKES.has(t):
		for g in D.MAKES[t][1]:
			if not out.has(g):
				out.append(g)
	return out


func stock_of(o, g: String) -> float:
	return float(o.get("stock", {}).get(g, 0.0))


func _cap_for(o, g: String) -> float:
	var d := D.def(o.t)
	if d.get("depot", false):
		return DEPOT_CAP * (1.0 + 0.5 * (int(o.get("lvl", 1)) - 1))
	if D.MAKES.has(o.t) and D.MAKES[o.t][1].has(g):
		return IN_CAP
	return USE_CAP


## Производство и расход товаров у одного здания. Возвращает множитель дохода (1 — как обычно).
func _produce(o: Dictionary, nw: int, dt: float) -> float:
	if nw <= 0:
		o.erase("busy")
		return 1.0
	var boost := 1.0
	var mk = D.MAKES.get(o.t)
	if mk != null:
		var f := float(nw) / float(stat(o, "jobs")) * (1.0 + 0.35 * (int(o.get("lvl", 1)) - 1))
		var r := MAKE_RATE * f * dt
		var out: float = o.get("out", 0.0)
		var busy := false
		if out < OUT_CAP:
			var ok := true
			for g in mk[1]:
				if stock_of(o, g) < r:
					ok = false
			if ok:
				for g in mk[1]:
					o.stock[g] = stock_of(o, g) - r
				o["out"] = minf(OUT_CAP, out + r)
				busy = true
		else:
			busy = not (mk[1] as Array).is_empty()
		if busy:
			o["busy"] = true
		else:
			o.erase("busy")
		if busy and not (mk[1] as Array).is_empty():
			boost = 1.5
	var uses: Array = D.USES.get(o.t, [])
	if not uses.is_empty():
		if not o.has("stock"):
			o["stock"] = {}
		var have := 0
		for g in uses:
			var v := stock_of(o, g)
			if v > 0.0:
				have += 1
				o.stock[g] = maxf(0.0, v - USE_RATE * dt)
		boost *= 1.0 + 0.6 * have / float(uses.size())
	return boost


func _truck_limit(b: int) -> int:
	var o = objs[b]
	return (2 if D.def(o.t).get("depot", false) else 1) + int(o.get("lvl", 1)) - 1


## Раз в секунду грузовики развозят готовые товары: сначала тем, кому они нужны, потом на склад или в порт.
func _update_freight(dt: float) -> void:
	_freight_t -= dt
	if _freight_t > 0.0:
		return
	_freight_t = 1.0
	var inc := {}
	var trucks := {}
	for car in cars:
		if not car.has("cargo"):
			continue
		trucks[car.base] = trucks.get(car.base, 0) + 1
		if not car.get("dropped", false):
			if not inc.has(car.target):
				inc[car.target] = {}
			inc[car.target][car.cargo] = inc[car.target].get(car.cargo, 0) + int(car.n)
	var sources: Array = []
	for b in stats.workplaces:
		var o = objs[b]
		if o == null or workers.get(b, []).is_empty() or trucks.get(b, 0) >= _truck_limit(b):
			continue
		if float(o.get("out", 0.0)) >= 4.0:
			sources.append(b)
		elif D.def(o.t).get("depot", false):
			for g in o.get("stock", {}):
				if o.stock[g] >= 4.0:
					sources.append(b)
					break
	sources.shuffle()
	var tries := 0
	for b in sources:
		if tries >= 3:
			break
		tries += 1
		_dispatch(b, inc)


func _dispatch(b: int, inc: Dictionary) -> void:
	var o = objs[b]
	var depot: bool = D.def(o.t).get("depot", false)
	var offers: Array = []
	if depot:
		for g in o.get("stock", {}):
			if o.stock[g] >= 4.0:
				offers.append([g, o.stock[g]])
		offers.shuffle()
	else:
		offers.append([D.MAKES[o.t][0], float(o.get("out", 0.0))])
	var starts := access_roads(b)
	if starts.is_empty():
		return
	var bc := center_of(b)
	for of in offers:
		var g: String = of[0]
		var have: float = of[1]
		var cands: Array = []
		for s in stats.sinks.get(g, []):
			if s == b or not is_ready(s):
				continue
			var space: float = _cap_for(objs[s], g) - stock_of(objs[s], g) - inc.get(s, {}).get(g, 0)
			if space >= 3.0:
				var sc := center_of(s)
				cands.append([absf(sc.x - bc.x) + absf(sc.y - bc.y), s, space])
		# лишнее — на склад, а если и он полон или его нет — в порт на экспорт (когда своё хранилище почти полно)
		if not depot and have >= OUT_CAP - 4.0:
			for s in stats.depots:
				var space: float = _cap_for(objs[s], g) - stock_of(objs[s], g) - inc.get(s, {}).get(g, 0)
				if is_ready(s) and space >= 3.0:
					var sc := center_of(s)
					cands.append([1000.0 + absf(sc.x - bc.x) + absf(sc.y - bc.y), s, space])
			for s in stats.ports:
				if is_ready(s):
					var sc := center_of(s)
					cands.append([2000.0 + absf(sc.x - bc.x) + absf(sc.y - bc.y), s, 99.0])
		cands.sort_custom(func(x, y): return x[0] < y[0])
		for k in mini(3, cands.size()):
			var s: int = cands[k][1]
			var route = road_route(starts, _to_set(access_roads(s)))
			if route == null:
				continue
			var n := mini(TRUCK_LOAD, int(minf(have, cands[k][2])))
			if n < 3:
				continue
			if depot:
				o.stock[g] -= n
			else:
				o.out = float(o.out) - n
			if route.size() < 2:
				# соседи у одной дороги — товар просто переносят через улицу
				_deliver({"target": s, "cargo": g, "n": n})
				return
			var car := _make_car("cargo", D.GOODS[g].col, route, null, s, b)
			car.base = b
			car["cargo"] = g
			car["n"] = n
			cars.append(car)
			if not inc.has(s):
				inc[s] = {}
			inc[s][g] = inc[s].get(g, 0) + n
			return


## Грузовик доехал: товар — в здание, а в порту — монетки за экспорт.
func _deliver(car: Dictionary) -> void:
	car["dropped"] = true
	var s: int = car.target
	if not is_ready(s):
		return
	var o = objs[s]
	var g: String = car.cargo
	deliveries += 1
	if D.def(o.t).get("export", false):
		var price := 2 if D.GOODS[g].get("raw", false) else 5
		var got: int = car.n * price
		if coins < stats.coin_cap:
			coins = minf(stats.coin_cap, coins + got)
		exported += int(car.n)
		float_text(center_of(s) * T + Vector2(8, -10), "+%d" % got, Color("c08a1a"))
		return
	if not o.has("stock"):
		o["stock"] = {}
	o.stock[g] = minf(_cap_for(o, g), stock_of(o, g) + car.n)


func _assign_jobs() -> void:
	for c in cats:
		if c.job >= 0 and not is_ready(c.job):
			c.job = -1
		if c.job >= 0:
			continue
		var hc := anchor_of(c)
		var best := -1
		var bd := 1e9
		for b in stats.workplaces:
			if workers.get(b, []).size() >= stat(objs[b], "jobs"):
				continue
			var bc := center_of(b)
			var dist := absf(bc.x - hc.x) + absf(bc.y - hc.y)
			if dist < bd:
				bd = dist
				best = b
		if best >= 0:
			c.job = best
			if not workers.has(best):
				workers[best] = []
			workers[best].append(c)
			var p := cat_pos(c)
			float_text(p + Vector2(0, -18), "%s: %s!" % [I18n.cat(c.name), tr(D.PROFESSIONS[D.def(objs[best].t).job]).to_lower()], Color("5b6bb0"))


# =====================================================================
#  Время суток (погода всегда ясная!)
# =====================================================================

func hour() -> float:
	return fposmod(time * 24.0 + 6.0, 24.0)


func abs_hour() -> float:
	return (day - 1) * 24.0 + time * 24.0


func is_night() -> bool:
	var h := hour()
	return h >= 21.0 or h < 5.5


static func darkness(h: float) -> float:
	var n := 0.42
	if h >= 7.0 and h < 18.0:
		return 0.0
	if h >= 18.0 and h < 20.5:
		return (h - 18.0) / 2.5 * n
	if h >= 20.5 or h < 4.5:
		return n
	return (1.0 - (h - 4.5) / 2.5) * n


# =====================================================================
#  Котики
# =====================================================================

func _pick_name() -> String:
	var avail: Array = D.CAT_NAMES.filter(func(n): return not used_names.has(n))
	var nm: String
	if avail.size() > 0:
		nm = avail.pick_random()
	else:
		nm = "%s %d" % [D.CAT_NAMES.pick_random(), used_names.size() - D.CAT_NAMES.size() + 2]
	used_names.append(nm)
	return nm


func free_houses() -> Array:
	return stats.houses.filter(func(h): return residents.get(h, []).size() < stat(objs[h], "cap"))


func spawn_cat() -> void:
	if homeless_count() > 0:
		return
	var houses := free_houses()
	if houses.is_empty():
		return
	houses.sort_custom(func(a, b): return stats.house_happy[a] > stats.house_happy[b])
	var h: int = houses[0]
	var wake := randf_range(6.2, 7.6)
	var c := {
		"id": next_id, "name": _pick_name(), "color": D.CAT_COLORS.keys().pick_random(), "casual": randi() % 6, "style": _city_style(),
		"home": h, "job": -1, "car": D.CAR_COLORS.pick_random() if randf() < 0.75 else "",
		"state": "in", "at": h, "x": float(h % W), "y": float(h / W), "path": [], "pi": 0, "dest": null,
		"timer": randf_range(0.5, 2.0), "dir": 1, "anim": randf() * 10.0, "pet": 0.0, "plan": null, "fail_until": 0.0,
		"wake": wake, "work_at": wake + randf_range(0.4, 1.2), "off": randf_range(16.5, 18.3), "bed": randf_range(20.6, 22.4),
		"lx": -1, "ly": -1, "car_lot": -1, "car_tile": -1, "car_dir": "r", "near_car": false,
	}
	next_id += 1
	cats.append(c)
	rebuild_maps()
	var prev := max_cats
	max_cats = maxi(max_cats, cats.size())
	var hc := center_of(h) * T + Vector2(8, 8)
	for k in 8:
		add_p({"type": "sparkle", "x": hc.x + randf_range(-8, 8), "y": hc.y + randf_range(-8, 4), "vx": randf_range(-6, 6), "vy": randf_range(-20, -8), "life": randf_range(0.6, 1.2)})
	ui.toast(tr("%s переезжает в %s!") % [I18n.cat(c.name), tr(city_name)], false, true)
	sound.play("mew", randf_range(0.9, 1.25))
	var opened := []
	for t in D.DEFS:
		var u := int(D.DEFS[t].get("unlock", 0))
		if u > prev and u <= max_cats:
			opened.append(tr(D.DEFS[t].name))
	if opened.size() > 0:
		ui.toast(tr("Открыто: %s!") % ", ".join(opened), true, true)
		sound.play("chime")
	ui.refresh_tools()


func outfit_key(c: Dictionary) -> String:
	if c.job >= 0 and objs[c.job] != null:
		return D.def(objs[c.job].t).get("job", "casual%d" % c.casual)
	if c.get("style", "") != "":
		return c.style
	return "casual%d" % c.casual


## Новые жители одеваются в стиле главных отраслей города:
## много офисов — больше котиков в пиджаках.
func _city_style() -> String:
	var weights := {}
	var total := 0.0
	for b in stats.workplaces:
		var j: String = D.def(objs[b].t).get("job", "")
		if j == "":
			continue
		var wgt := float(stat(objs[b], "jobs"))
		weights[j] = weights.get(j, 0.0) + wgt
		total += wgt
	if total <= 0.0 or randf() < 0.25:
		return ""
	var r := randf() * total
	for j in weights:
		r -= weights[j]
		if r <= 0.0:
			return j
	return ""


func profession(c: Dictionary) -> String:
	if c.job >= 0 and objs[c.job] != null:
		return tr(D.PROFESSIONS.get(D.def(objs[c.job].t).get("job", ""), ""))
	return tr("Ищет работу")


func _near(list: Array, c: Dictionary, dist: float) -> Array:
	var cc := _cat_center(c)
	var out := []
	for b in list:
		var bc := center_of(b)
		if absf(bc.x - cc.x) + absf(bc.y - cc.y) < dist:
			out.append(b)
	return out


func _pick_leisure(c: Dictionary) -> int:
	var opts := _near(stats.leisure, c, 26.0)
	return opts.pick_random() if opts.size() > 0 else -1


func _pick_stroll(c: Dictionary):
	var opts := _near(stats.strolls, c, 22.0)
	if opts.is_empty():
		return null
	var b: int = opts.pick_random()
	var bc := center_of(b)
	return {"x": roundi(bc.x), "y": roundi(bc.y), "b": b}


func _desired(c: Dictionary) -> Dictionary:
	var h := hour()
	var ah := abs_hour()
	if ah < c.fail_until and c.fail_until - ah < 1.0:
		return {"kind": "wander"}
	var homeless: bool = c.home < 0
	if h >= c.bed or h < c.wake:
		return {"kind": "rest"} if homeless else _maybe_transit(c, {"kind": "home", "b": c.home})
	if c.job >= 0 and is_ready(c.job) and h >= c.work_at and h < c.off:
		return _maybe_transit(c, {"kind": "work", "b": c.job})
	var pl = c.plan
	if pl != null and ah < pl.until and pl.until - ah < 3.0 and (not pl.has("b") or is_ready(pl.b)):
		return pl
	var p = null
	# у котика есть дела: сходить в кафе или магазин, прогуляться к красивому месту, съездить в другой район
	var r := randf()
	if r < 0.45:
		var l := _pick_leisure(c)
		if l >= 0:
			p = {"kind": "visit", "b": l}
	elif r < 0.7:
		var s = _pick_stroll(c)
		if s != null:
			p = {"kind": "stroll", "tx": s.x, "ty": s.y, "sb": s.b}
	elif r < 0.76 and transit.hubs.size() >= 2:
		p = _leisure_trip(c)
	elif r < 0.92 and not homeless:
		p = _maybe_transit(c, {"kind": "home", "b": c.home})
	if p == null:
		p = {"kind": "wander"}
	p["until"] = ah + randf_range(1.0, 2.5)
	c.plan = p
	return p


## Далеко идти (или пешком не дойти) — едем на поезде или летим самолётом.
func _maybe_transit(c: Dictionary, goal: Dictionary) -> Dictionary:
	var t = _via_transit(c, goal, false)
	return t if t != null else goal


func _via_transit(c: Dictionary, goal: Dictionary, any_distance: bool):
	if transit.hubs.size() < 2 or not goal.has("b") or goal.b < 0 or objs[goal.b] == null:
		return null
	var from := _cat_center(c)
	var to := center_of(goal.b)
	var direct := from.distance_to(to)
	var stuck: bool = abs_hour() < c.fail_until
	if direct <= 20.0 and not stuck and not any_distance:
		return null
	var best = null
	var best_d := 1e9
	for a in transit.hubs:
		if not is_ready(a):
			continue
		var da := center_of(a).distance_to(from)
		if da > 16.0:
			continue
		for b in transit.hubs:
			if not transit.connected(a, b):
				continue
			var db := center_of(b).distance_to(to)
			if db > 14.0:
				continue
			var total := da + db
			if (stuck or any_distance or total < direct * 0.8) and total < best_d:
				best_d = total
				best = [a, b]
	if best == null:
		return null
	return {"kind": "trip", "b": best[0], "to": best[1], "goal": goal}


## Просто съездить погулять в другой район.
func _leisure_trip(c: Dictionary):
	var opts: Array = stats.leisure + stats.strolls
	if opts.is_empty():
		return null
	for attempt in 4:
		var g: int = opts.pick_random()
		var t = _via_transit(c, {"kind": "visit", "b": g}, true)
		if t != null and center_of(t.to).distance_to(_cat_center(c)) > 10.0:
			return t
	return null


# --- поиск пути ---

func _tile_cost(i: int) -> float:
	var o = objs[i]
	if o != null:
		if o.t == "path" or o.t == "blvd":
			return 1.0
		if o.t == "road":
			# по проезжей части котики не гуляют — только переходят её, лучше по зебре
			return 4.0 if crosswalks.has(i) else 30.0
		if o.t == "rail" or o.t == "crossing":
			return 30.0
		return 1.6
	match terrain[i]:
		MOUNTAIN:
			return 3.5
		HILL:
			return 2.4
	return 2.0


## Пешеходный путь (Дейкстра; тротуары дешевле травы).
func walk_path(sx: int, sy: int, goals: Dictionary):
	var s := sy * W + sx
	if goals.has(s):
		return []
	var dist := PackedFloat32Array()
	dist.resize(W * H)
	dist.fill(1e20)
	var prev := PackedInt32Array()
	prev.resize(W * H)
	prev.fill(-1)
	var hk := PackedFloat32Array()
	var hv := PackedInt32Array()
	dist[s] = 0.0
	_heap_push(hk, hv, 0.0, s)
	while hk.size() > 0:
		var top := _heap_pop(hk, hv)
		var dd: float = top[0]
		var u: int = top[1]
		if dd > dist[u]:
			continue
		if goals.has(u):
			var out := []
			var k := u
			while k != s:
				out.append(Vector2i(k % W, k / W))
				k = prev[k]
			out.reverse()
			return out
		var ux := u % W
		var uy := u / W
		for dv in DIRS:
			var nx: int = ux + dv.x
			var ny: int = uy + dv.y
			if not in_map(nx, ny):
				continue
			var n := ny * W + nx
			if not walkable_idx(n):
				continue
			var nd := dd + _tile_cost(n)
			if nd < dist[n]:
				dist[n] = nd
				prev[n] = u
				_heap_push(hk, hv, nd, n)
	return null


static func _heap_push(k: PackedFloat32Array, v: PackedInt32Array, key: float, val: int) -> void:
	var i := k.size()
	k.append(key)
	v.append(val)
	while i > 0:
		var p := (i - 1) >> 1
		if k[p] <= key:
			break
		k[i] = k[p]
		v[i] = v[p]
		i = p
	k[i] = key
	v[i] = val


static func _heap_pop(k: PackedFloat32Array, v: PackedInt32Array) -> Array:
	var top := [k[0], v[0]]
	var last := k.size() - 1
	var lk := k[last]
	var lv := v[last]
	k.resize(last)
	v.resize(last)
	if last > 0:
		var i := 0
		while true:
			var m := i * 2 + 1
			if m >= last:
				break
			if m + 1 < last and k[m + 1] < k[m]:
				m += 1
			if k[m] >= lk:
				break
			k[i] = k[m]
			v[i] = v[m]
			i = m
		k[i] = lk
		v[i] = lv
	return top


func goals_around(b: int) -> Dictionary:
	var g := {}
	for p in around(b):
		if foot_ok(p.y * W + p.x):
			g[p.y * W + p.x] = true
	if g.is_empty():
		for p in around(b):
			if walkable_idx(p.y * W + p.x):
				g[p.y * W + p.x] = true
	return g


## Сколько «стоит» въехать на клетку: магистраль быстрее, светофоры и пробки — дольше.
func _step_cost(n: int) -> int:
	var o = objs[n]
	var c := 2 if o.t == "highway" else (6 if o.t == "crossing" else 4)
	if junctions.has(n):
		c += 3
	return c + mini(3, _cong.get(n, 0)) * 5


## Путь по дорогам: самый быстрый с учётом магистралей, светофоров и пробок.
func road_route(starts: Array, goals: Dictionary, avoid: Dictionary = {}):
	if starts.is_empty() or goals.is_empty():
		return null
	var dist := PackedInt32Array()
	dist.resize(W * H)
	dist.fill(1 << 30)
	var prev := PackedInt32Array()
	prev.resize(W * H)
	prev.fill(-2)
	var buckets: Array = [[]]
	for s0 in starts:
		dist[s0] = 0
		prev[s0] = -1
		buckets[0].append(s0)
	var c := 0
	while c < buckets.size():
		var bk: Array = buckets[c]
		var j := 0
		while j < bk.size():
			var u: int = bk[j]
			j += 1
			if dist[u] != c:
				continue
			if goals.has(u):
				var out := []
				var k := u
				while k != -1:
					out.append(Vector2i(k % W, k / W))
					k = prev[k]
				out.reverse()
				return out
			var ux := u % W
			var uy := u / W
			for di in 4:
				var dv: Vector2i = DIRS[di]
				var nx: int = ux + dv.x
				var ny: int = uy + dv.y
				if not is_drivable(nx, ny):
					continue
				var n := ny * W + nx
				if avoid.has(n):
					continue
				var nd := c + _step_cost(n)
				if nd < dist[n]:
					dist[n] = nd
					prev[n] = u
					while buckets.size() <= nd:
						buckets.append([])
					buckets[nd].append(n)
		c += 1
	return null


func roads_around(b: int) -> Array:
	var out := []
	for p in around(b):
		if is_road(p.x, p.y):
			out.append(p.y * W + p.x)
	return out


## Дорога, до которой от здания можно дойти: вплотную или в паре шагов по тротуару и траве.
func access_roads(b: int) -> Array:
	var near := roads_around(b)
	if not near.is_empty():
		return near
	var seen := {}
	var front: Array = []
	for p in around(b):
		var i: int = p.y * W + p.x
		if foot_ok(i):
			seen[i] = true
			front.append(i)
	var out: Array = []
	for depth in 3:
		var nxt: Array = []
		for i in front:
			for dv in DIRS:
				var nx: int = i % W + dv.x
				var ny: int = i / W + dv.y
				if not in_map(nx, ny):
					continue
				var n := ny * W + nx
				if seen.has(n):
					continue
				seen[n] = true
				if is_road(nx, ny):
					out.append(n)
				elif foot_ok(n):
					nxt.append(n)
		if not out.is_empty():
			return out
		front = nxt
	return out


func _door_of(b: int):
	for p in around(b):
		if foot_ok(p.y * W + p.x):
			return p
	for p in around(b):
		if walkable_idx(p.y * W + p.x):
			return p
	return null


# --- поведение ---

func _enter(c: Dictionary, b: int) -> void:
	c.state = "in"
	c.at = b
	c.timer = randf_range(0.5, 1.2)
	c.path = []
	c.dest = null


func _car_at_home(c: Dictionary) -> bool:
	return c.car_lot < 0 and c.car_tile < 0


## Если парковку снесли или дорогу под машиной убрали — машина возвращается в гараж дома.
func _validate_car(c: Dictionary) -> void:
	if c.car_lot >= 0 and (not is_ready(c.car_lot) or not D.def(objs[c.car_lot].t).has("parking")):
		c.car_lot = -1
	if c.car_tile >= 0 and not is_road(c.car_tile % W, c.car_tile / W):
		c.car_tile = -1


func lot_capacity(l: int) -> int:
	return int(stat(objs[l], "parking", 0))


func _find_lot(b: int) -> int:
	var bc := center_of(b)
	var best := -1
	var bd := 1e9
	for l in stats.lots:
		if lot_count.get(l, 0) >= lot_capacity(l) or roads_around(l).is_empty():
			continue
		var dist := center_of(l).distance_to(bc)
		if dist <= 8.0 and dist < bd:
			bd = dist
			best = l
	return best


func _walk_to_car(c: Dictionary, d: Dictionary, goals: Dictionary) -> bool:
	var path = walk_path(roundi(c.x), roundi(c.y), goals)
	if path == null:
		return false
	c.path = path
	c.pi = 0
	c.dest = {"kind": "tocar", "then": d}
	c.state = "walk"
	if path.is_empty():
		_walk_done(c)
	return true


## Поехать на машине: из гаража дома, с парковки или с места на улице.
func _try_drive(c: Dictionary, d: Dictionary) -> bool:
	var starts := []
	if c.car_tile >= 0:
		if c.state != "in" and roundi(c.y) * W + roundi(c.x) == c.car_tile:
			starts = [c.car_tile]
		else:
			return _walk_to_car(c, d, {c.car_tile: true})
	elif c.car_lot >= 0:
		if c.near_car:
			starts = roads_around(c.car_lot)
		else:
			return _walk_to_car(c, d, goals_around(c.car_lot))
	elif c.state == "in" and c.at == c.home and is_ready(c.home):
		starts = roads_around(c.home)
		if starts.is_empty():
			# дом не у самой дороги — сначала дойти до неё по тротуару
			var acc := access_roads(c.home)
			if acc.is_empty():
				return false
			return _walk_to_car(c, d, _to_set(acc))
	elif c.near_car and _car_at_home(c) and c.home >= 0:
		var here := roundi(c.y) * W + roundi(c.x)
		starts = [here] if is_road(roundi(c.x), roundi(c.y)) else access_roads(c.home)
	if starts.is_empty():
		return false
	var lot := -1
	if d.kind != "home":
		lot = _find_lot(d.b)
	var goal := _to_set(access_roads(lot if lot >= 0 else d.b))
	var route = road_route(starts, goal)
	if route == null and lot >= 0:
		lot = -1
		route = road_route(starts, _to_set(access_roads(d.b)))
	if route == null or route.size() < 2:
		return false
	c.car_tile = -1
	c.car_lot = -1
	c.near_car = false
	c.state = "drive"
	c.at = -1
	c.dest = d
	var car := _make_car(car_model(c), c.car, route, c, d.b, -1)
	car["mode"] = "home" if d.kind == "home" else ("lot" if lot >= 0 else "street")
	car["lot"] = lot
	cars.append(car)
	rebuild_maps()
	return true


func _go_to(c: Dictionary, d: Dictionary, allow_car := true) -> void:
	var ah := abs_hour()
	var kind: String = d.kind
	var trip := kind == "home" or kind == "work" or kind == "visit"
	var can_car: bool = allow_car and trip and c.car != "" and is_ready(d.b)
	if can_car:
		_validate_car(c)
	if c.state == "in":
		var from: int = c.at
		if can_car and _car_at_home(c) and from == c.home and _try_drive(c, d):
			return
		var door = _door_of(from) if objs[from] != null else null
		if door == null:
			c.timer = 4.0
			if objs[from] == null:
				c.state = "idle"
				c.at = -1
			return
		c.x = float(door.x)
		c.y = float(door.y)
		c.at = -1
		c.state = "idle"
		c.timer = 0.0
	if kind == "wander" or kind == "rest":
		return
	if can_car and (not _car_at_home(c) or c.near_car) and _try_drive(c, d):
		return
	# далеко идти, а машина у дома (и дом ближе) — сначала к машине, потом поехать
	if can_car and _car_at_home(c) and not c.near_car and c.home >= 0 and is_ready(c.home) and kind != "home":
		var cp := Vector2(c.x, c.y)
		var to_goal := cp.distance_to(center_of(d.b))
		if to_goal > 14.0 and cp.distance_to(center_of(c.home)) < to_goal * 0.6:
			var acc := access_roads(c.home)
			if not acc.is_empty() and _walk_to_car(c, d, _to_set(acc)):
				return
	var sx := roundi(c.x)
	var sy := roundi(c.y)
	var path = null
	if kind == "stroll":
		var g := {}
		for y in range(d.ty - 1, d.ty + 2):
			for x in range(d.tx - 1, d.tx + 2):
				if in_map(x, y) and walkable_idx(y * W + x):
					g[y * W + x] = true
		if objs[d.sb] != null:
			g.merge(goals_around(d.sb))
		path = walk_path(sx, sy, g) if g.size() > 0 else null
	elif d.has("b") and d.b >= 0 and objs[d.b] != null:
		path = walk_path(sx, sy, goals_around(d.b))
	if path == null:
		c.fail_until = ah + 0.6
		c.state = "idle"
		c.timer = 0.5
		# домой пешком не дойти — после пары попыток котик вызывает такси, а не спит на улице
		if kind == "home" and is_ready(d.b):
			c["home_fails"] = int(c.get("home_fails", 0)) + 1
			if c.home_fails >= 2:
				c.home_fails = 0
				float_text(cat_pos(c) + Vector2(0, -14), tr("Такси!"), Color("c8a020"))
				_enter(c, d.b)
		return
	c.path = path
	c.pi = 0
	c.dest = d
	c.state = "walk"
	if path.is_empty():
		_walk_done(c)


static func _to_set(arr: Array) -> Dictionary:
	var s := {}
	for a in arr:
		s[a] = true
	return s


func _wander_step(c: Dictionary, anchor: Vector2, rad: float) -> void:
	var cx := roundi(c.x)
	var cy := roundi(c.y)
	var opts := []
	for dv in DIRS:
		var nx: int = cx + dv.x
		var ny: int = cy + dv.y
		if in_map(nx, ny) and foot_ok(ny * W + nx):
			opts.append(Vector2i(nx, ny))
	if opts.is_empty():
		# стоим на дороге (вышли из машины) — сходим на ближайшую клетку
		for dv in DIRS:
			var nx: int = cx + dv.x
			var ny: int = cy + dv.y
			if in_map(nx, ny) and walkable_idx(ny * W + nx):
				opts.append(Vector2i(nx, ny))
	if opts.is_empty():
		c.state = "idle"
		c.timer = randf_range(1, 3)
		return
	var da := Vector2(cx, cy).distance_to(anchor)
	var total := 0.0
	var ws := []
	for o in opts:
		var w := 1.0
		var ob = obj_at(o.x, o.y)
		if ob != null and (ob.t == "path" or ob.t == "blvd"):
			w *= 4.0
		if ob != null and ob.t == "road":
			w *= 0.6
		if c.lx == o.x and c.ly == o.y:
			w *= 0.25
		if _standing_at(o.x, o.y, c):
			w *= 0.05
		if da > rad and Vector2(o).distance_to(anchor) < da:
			w *= 4.0
		total += w
		ws.append(w)
	var r := randf() * total
	var choice: Vector2i = opts[0]
	for k in opts.size():
		r -= ws[k]
		if r <= 0.0:
			choice = opts[k]
			break
	c.lx = cx
	c.ly = cy
	c.path = [choice]
	c.pi = 0
	c.dest = {"kind": "wander"}
	c.state = "walk"


## Стоит или спит ли на клетке другой котик (проходить мимо можно, стоять вдвоём — нет).
func _standing_at(x: int, y: int, me: Dictionary) -> bool:
	for o in cats:
		if is_same(o, me) or (o.state != "idle" and o.state != "sleep"):
			continue
		if roundi(o.x) == x and roundi(o.y) == y:
			return true
	return false


func _walk_done(c: Dictionary) -> void:
	var d = c.dest
	c.path = []
	c.dest = null
	if d != null and d.kind == "tocar":
		c.near_car = true
		c.state = "idle"
		_go_to(c, d.then)
		return
	c.near_car = false
	if d != null and d.kind == "trip" and is_ready(d.b):
		_enter(c, d.b)
		c["trip"] = {"to": d.to, "goal": d.goal, "wait": 0.0}
		return
	if d != null and (d.kind == "home" or d.kind == "work" or d.kind == "visit"):
		if is_ready(d.b) and (d.kind != "home" or c.home == d.b):
			_enter(c, d.b)
			return
	var o = obj_at(roundi(c.x), roundi(c.y))
	c.state = "idle"
	var daytime := hour() >= 9.0 and hour() < 18.0
	if o != null and o.t == "cushion" and daytime and randf() < 0.6:
		c.state = "sleep"
		c.timer = randf_range(8, 16)
		return
	if o != null and o.t == "bench" and daytime and randf() < 0.6:
		c.timer = randf_range(4, 9)
		return
	c.timer = randf_range(1.2, 3.5) if randf() < 0.22 else 0.0
	# на этой клетке уже кто-то стоит — отойти на соседнюю свободную
	if _standing_at(roundi(c.x), roundi(c.y), c):
		c.timer = 0.0
		_wander_step(c, Vector2(c.x, c.y), 1.0)


func _update_cat(c: Dictionary, dt: float) -> void:
	c.anim += dt
	if c.pet > 0.0:
		c.pet -= dt
	match c.state:
		"drive", "ride":
			return
		"in":
			if objs[c.at] == null:
				c.state = "idle"
				c.timer = 0.2
				c.at = -1
				c["trip"] = null
				return
			var tp = c.get("trip")
			if tp != null:
				# ждёт поезд или самолёт; если долго нет — идёт по своим делам
				tp.wait += dt
				if tp.wait > 45.0 or not transit.connected(c.at, tp.to):
					c["trip"] = null
				else:
					return
			c.timer -= dt
			if c.timer > 0.0:
				return
			c.timer = randf_range(0.4, 1.0)
			var d := _desired(c)
			if (d.kind == "home" or d.kind == "work" or d.kind == "visit") and d.b == c.at:
				return
			_go_to(c, d)
		"sleep":
			c.timer -= dt
			if randf() < dt * 0.6:
				add_p({"type": "z", "x": c.x * T + 10, "y": c.y * T + 2, "vx": randf_range(2, 6), "vy": -8.0, "life": 1.6})
			if c.timer <= 0.0:
				c.state = "idle"
				c.timer = 0.2
		"idle":
			c.timer -= dt
			if c.timer > 0.0:
				return
			var d := _desired(c)
			if d.kind == "wander":
				_wander_step(c, anchor_of(c), 7.0)
			elif d.kind == "rest":
				c.state = "sleep"
				c.timer = randf_range(12, 20)
			elif d.kind == "stroll" and Vector2(c.x, c.y).distance_to(Vector2(d.tx, d.ty)) <= 3.0:
				_wander_step(c, Vector2(d.tx, d.ty), 2.0)
			else:
				_go_to(c, d)
		"walk":
			var tgt: Vector2i = c.path[c.pi]
			# перед рельсами ждём, пока проедет поезд
			if is_rail(tgt.x, tgt.y) and not is_rail(roundi(c.x), roundi(c.y)) and transit.train_near(tgt):
				return
			var dx: float = tgt.x - c.x
			var dy: float = tgt.y - c.y
			var dist := sqrt(dx * dx + dy * dy)
			var o = obj_at(tgt.x, tgt.y)
			var sp := dt * (1.7 if o != null and (o.t == "path" or o.t == "blvd") else (1.4 if o != null and o.t == "road" else 1.1))
			if absf(dx) > 0.01:
				c.dir = 1 if dx > 0 else -1
			if dist <= sp:
				c.x = float(tgt.x)
				c.y = float(tgt.y)
				c.pi += 1
				if c.pi >= c.path.size():
					_walk_done(c)
			else:
				c.x += dx / dist * sp
				c.y += dy / dist * sp
			if happy > 70.0 and randf() < dt * 0.01:
				hearts_at(Vector2(c.x * T + 8, c.y * T + 2), 1)


func pet_cat(c: Dictionary) -> void:
	c.pet = 1.4
	var p := cat_pos(c)
	hearts_at(p + Vector2(0, -12), 5)
	float_text(p + Vector2(0, -16), tr("мрр... zZ") if c.state == "sleep" else [tr("Мурр!"), tr("Мяу!"), tr("Мрр~")].pick_random(), Color("ff6b8b"))
	sound.play("mew", randf_range(0.95, 1.3))
	pet_bonus = minf(10.0, pet_bonus + 1.5)
	pets_total += 1
	if c.state == "idle":
		c.timer = maxf(c.timer, 1.5)


func cat_pos(c: Dictionary) -> Vector2:
	if c.state == "ride":
		var vp = transit.cat_vehicle_pos(c)
		if vp != null:
			return vp
	if c.state == "drive":
		for car in cars:
			if car.cat == c:
				return Vector2(car.px, car.py)
	if c.state == "in" and c.at >= 0 and objs[c.at] != null:
		return center_of(c.at) * T + Vector2(8, 8)
	return Vector2(c.x * T + 8, c.y * T + 14)


func activity_text(c: Dictionary) -> String:
	var d = c.dest
	var where := func(dd) -> String:
		if dd == null:
			return ""
		match dd.kind:
			"home":
				return tr("домой")
			"work":
				return tr("на работу")
			"visit":
				return tr("в «%s»") % bname(dd.b)
		return tr("гулять")
	match c.state:
		"ride":
			return tr("летит на самолёте") if transit.vehicle_kind(c) == "air" else tr("едет на поезде")
		"drive":
			return tr("едет %s на машине") % where.call(d)
		"walk":
			return tr("идёт %s") % where.call(d) if d != null and d.kind != "wander" else tr("гуляет")
		"in":
			if c.get("trip") != null:
				return tr("ждёт %s в «%s»") % [tr("самолёт") if transit.hubs.get(c.at, {}).get("kind", "") == "air" else tr("поезд"), bname(c.at)]
			if c.at == c.home:
				return tr("спит дома") if is_night() else tr("отдыхает дома")
			if c.at == c.job:
				return tr("работает")
			return tr("в «%s»") % bname(c.at)
		"sleep":
			return tr("дремлет под открытым небом") if c.home < 0 else tr("дремлет")
	return tr("ждёт новый дом") if c.home < 0 else tr("отдыхает на улице")


# =====================================================================
#  Машины
# =====================================================================

const LANE := {"r": Vector2(0, 3), "l": Vector2(0, -3), "d": Vector2(-3, 0), "u": Vector2(3, 0)}
const DIR_VEC := {"r": Vector2(1, 0), "l": Vector2(-1, 0), "d": Vector2(0, 1), "u": Vector2(0, -1)}


## Что впереди: 0 — свободно, 1 — объезжаем припаркованную машину, 2 — стоим за другой машиной.
## Встречные машины не мешают; поперечные внутри одного перекрёстка друг друга пропускают.
func _traffic(car: Dictionary) -> int:
	car["blk"] = null
	var fwd_v: Vector2 = DIR_VEC[car.dir]
	var side_v := Vector2(fwd_v.y, fwd_v.x)
	var me := Vector2(car.bx, car.by)
	var hw: bool = car.get("hw", false)
	var multi: bool = hw
	var my_p := Vector2(car.px, car.py)
	var my_t := _tile_of(car)
	var in_box := junctions.has(my_t)
	for o in cars:
		if is_same(o, car):
			continue
		var odot := (DIR_VEC[o.dir] as Vector2).dot(fwd_v)
		var rel := Vector2(o.px, o.py) - my_p
		var fwd := rel.dot(fwd_v)
		var side := absf(rel.dot(side_v))
		if odot < -0.5:
			# встречная машина мешает, только если она объезжает и уже в моей полосе
			if o.get("passing", false) and fwd > 0.5 and fwd < 12.0 and side < 3.5:
				car["blk"] = o
				return 2
			continue
		# на многополосной дороге мешает только машина в своей полосе
		if multi and o.get("hw", false) and o.get("lane", 0) != car.get("lane", 0):
			continue
		if fwd > 0.5 and fwd < 11.0 and side < 3.5:
			if odot < 0.5 and in_box and _tile_of(o) == my_t:
				continue
			if multi and _lane_free(car, 1 - int(car.get("lane", 0))):
				car["lane"] = 1 - int(car.get("lane", 0))
				return 0
			car["blk"] = o
			return 2
	for c in street_parked:
		var pp := Vector2(c.car_tile % W * T + 8.0, c.car_tile / W * T + 8.0)
		var rel := pp - me
		var fwd := rel.dot(fwd_v)
		var side := absf(rel.dot(side_v))
		if fwd > -8.0 and fwd < 14.0 and side < 4.0:
			# прежде чем выехать на встречку, пропускаем встречных (кто уже объезжает — едет дальше)
			if not car.get("passing", false) and _oncoming(car, 18.0) != null:
				car["blk"] = _oncoming(car, 18.0)
				return 2
			return 1
	return 0


func _oncoming(car: Dictionary, dist: float):
	var fwd_v: Vector2 = DIR_VEC[car.dir]
	var me := Vector2(car.bx, car.by)
	for o in cars:
		if is_same(o, car) or (DIR_VEC[o.dir] as Vector2).dot(fwd_v) > -0.5:
			continue
		var rel := Vector2(o.bx, o.by) - me
		if rel.dot(fwd_v) > -4.0 and rel.dot(fwd_v) < dist and absf(rel.dot(Vector2(fwd_v.y, fwd_v.x))) < 4.0:
			return o
	return null


## Свободна ли соседняя полоса (магистраль или одностороннее движение) для перестроения.
func _lane_free(car: Dictionary, lane: int) -> bool:
	var fwd_v: Vector2 = DIR_VEC[car.dir]
	var me := Vector2(car.bx, car.by)
	for o in cars:
		if is_same(o, car) or o.dir != car.dir or int(o.get("lane", 0)) != lane:
			continue
		var fwd := (Vector2(o.bx, o.by) - me).dot(fwd_v)
		if fwd > -12.0 and fwd < 14.0:
			return false
	return true


## Калифорния: у многих котиков кабриолет или спортивная машина (у каждого своя, навсегда).
func car_model(c: Dictionary) -> String:
	return ["car", "convertible", "sport", "car", "convertible"][int(c.get("id", 0)) % 5]


func _make_car(kind: String, color: String, route: Array, cat, target: int, return_to: int) -> Dictionary:
	var car := {"kind": kind, "color": color, "route": route, "k": 0, "prog": 0.0, "cat": cat, "target": target,
		"return_to": return_to, "px": 0.0, "py": 0.0, "bx": 0.0, "by": 0.0, "dir": "r", "speed": 3.0 if kind in ["car", "convertible", "sport"] else 2.6,
		"base": -1, "wait": 0.0, "passing": false, "mode": "home", "lot": -1, "lane": randi() % 2, "hw": false}
	_car_pos(car)
	return car


func _car_pos(car: Dictionary) -> void:
	var a: Vector2i = car.route[car.k]
	var b: Vector2i = car.route[mini(car.k + 1, car.route.size() - 1)]
	var dx := b.x - a.x
	var dy := b.y - a.y
	if dx > 0:
		car.dir = "r"
	elif dx < 0:
		car.dir = "l"
	elif dy > 0:
		car.dir = "d"
	elif dy < 0:
		car.dir = "u"
	var off: Vector2 = LANE[car.dir]
	var hw := is_highway(a.x, a.y) or is_highway(b.x, b.y)
	car["hw"] = hw
	if hw:
		# магистраль: ближняя полоса — 2 px от разделительной, дальняя — 5 px
		off = off / 3.0 * (2.0 if car.get("lane", 0) == 0 else 5.0)
	elif car.get("passing", false):
		off = -off
	car["bx"] = (a.x + dx * car.prog) * T + 8.0
	car["by"] = (a.y + dy * car.prog) * T + 8.0
	# смещение по полосе меняется плавно: повороты и перестроения без рывков
	if not car.has("ox"):
		car["ox"] = off.x
		car["oy"] = off.y
	else:
		car.ox = move_toward(car.ox, off.x, 0.6)
		car.oy = move_toward(car.oy, off.y, 0.6)
	car.px = car.bx + car.ox
	car.py = car.by + car.oy


## Взаимная блокировка: цепочка «кто кого ждёт» замкнулась.
func _in_cycle(car: Dictionary) -> bool:
	var x = car.get("blk")
	for k in 16:
		if x == null:
			return false
		if is_same(x, car):
			return true
		x = x.get("blk")
	return false


## Застрявшая машина ищет объезд, не заезжая на клетку, где стоит пробка.
func _reroute(car: Dictionary) -> bool:
	var route: Array = car.route
	if car.k + 2 >= route.size():
		return false
	var cur: Vector2i = route[car.k]
	var nxt: Vector2i = route[car.k + 1]
	var e: Vector2i = route[route.size() - 1]
	var nr = road_route([cur.y * W + cur.x], {e.y * W + e.x: true}, {nxt.y * W + nxt.x: true})
	if nr == null or nr.size() < 2 or nr.size() > (route.size() - car.k) * 2 + 8:
		return false
	car.route = nr
	car.k = 0
	car.prog = 0.0
	return true


func _update_cars(dt: float) -> void:
	_cong = {}
	for car in cars:
		if car.get("stopped", false):
			var ti := _tile_of(car)
			_cong[ti] = _cong.get(ti, 0) + 1
	var n := cars.size()
	while n > 0:
		n -= 1
		var car: Dictionary = cars[n]
		var route: Array = car.route
		if route.size() < 2:
			_finish_car(car, false)
			cars.remove_at(n)
			continue
		var a: Vector2i = route[car.k]
		var b: Vector2i = route[mini(car.k + 1, route.size() - 1)]
		if not is_drivable(a.x, a.y) or not is_drivable(b.x, b.y):
			_finish_car(car, true)
			cars.remove_at(n)
			continue
		car["stopped"] = true
		var ghost: float = car.get("ghost", 0.0)
		if ghost > 0.0:
			# аварийный выход из взаимной блокировки: аккуратно проезжаем
			car["ghost"] = ghost - dt
			car["blk"] = null
		elif _must_stop(car):
			car["red"] = true
			car["hold"] = car.get("hold", 0.0) + dt
			if car.get("blk") != null and car.hold > 3.0 and _in_cycle(car):
				car["ghost"] = 1.2
				car["hold"] = 0.0
			_car_pos(car)
			continue
		car["red"] = false
		var tr := 0 if ghost > 0.0 else _traffic(car)
		car["passing"] = tr == 1
		# ждём, пока впереди освободится (сквозь машины не проезжаем)
		if tr == 2:
			car["wait"] = car.get("wait", 0.0) + dt
			var w: float = car.wait
			if w > 3.0 and _in_cycle(car):
				car["ghost"] = 1.2
				car["wait"] = 0.0
			elif w > 7.0 and car.get("rr", 0.0) <= 0.0:
				car["rr"] = 12.0
				if _reroute(car):
					car["wait"] = 0.0
			elif w > 45.0:
				car["ghost"] = 1.2
				car["wait"] = 0.0
			if w > 4.0 and randf() < dt * 0.25:
				float_text(Vector2(car.px, car.py - 10), tr("Би-бип!"), Color("6a6478"))
			car["rr"] = car.get("rr", 0.0) - dt
			_car_pos(car)
			continue
		car["blk"] = null
		car["stopped"] = false
		car["wait"] = 0.0
		car["hold"] = 0.0
		car["rr"] = car.get("rr", 0.0) - dt
		var p0: float = car.prog
		car.prog += car.speed * dt * (0.3 if tr == 1 else (1.9 if car.get("hw", false) else 1.0))
		# перед перекрёстком и переездом всегда притормаживаем у стоп-линии, чтобы проверить светофор
		if ghost <= 0.0 and p0 < 0.45 and car.prog > 0.45 and car.k + 1 < route.size():
			var bi: int = b.y * W + b.x
			var ai: int = a.y * W + a.x
			if (junctions.has(bi) and not junctions.has(ai)) or (crossings.has(bi) and not crossings.has(ai)):
				car.prog = 0.45
		while car.prog >= 1.0 and car.k < route.size() - 1:
			car.prog -= 1.0
			car.k += 1
		if car.k >= route.size() - 1:
			car.k = route.size() - 1
			car.prog = 0.0
			if car.has("cargo") and not car.get("dropped", false):
				_deliver(car)
			if car.return_to >= 0 and is_ready(car.return_to):
				var e: Vector2i = route[route.size() - 1]
				var back = road_route([e.y * W + e.x], _to_set(access_roads(car.return_to)))
				car.return_to = -1
				if back != null and back.size() >= 2:
					car.route = back
					car.k = 0
					car.prog = 0.0
					_car_pos(car)
					continue
			_finish_car(car, false)
			cars.remove_at(n)
			continue
		_car_pos(car)


func _finish_car(car: Dictionary, broken: bool) -> void:
	var c = car.cat
	if c == null or not cats.has(c):
		return
	var end: Vector2i = car.route[mini(car.k, car.route.size() - 1)]
	var d = c.dest
	c.state = "idle"
	c.timer = 0.3
	c.at = -1
	c.x = float(end.x)
	c.y = float(end.y)
	c.dest = null
	if broken or d == null:
		return
	match car.get("mode", "home"):
		"home":
			if is_ready(car.target):
				if roads_around(car.target).has(end.y * W + end.x):
					_enter(c, car.target)
				else:
					# машина уехала в гараж, а котик идёт от дороги до двери
					_go_to(c, d, false)
		"lot":
			if is_ready(car.lot):
				c.car_lot = car.lot
				var door = _door_of(car.lot)
				if door != null:
					c.x = float(door.x)
					c.y = float(door.y)
			else:
				c.car_tile = end.y * W + end.x
				c.car_dir = car.dir
			_go_to(c, d, false)
		"street":
			# парковки рядом нет — машина остаётся прямо на дороге
			c.car_tile = end.y * W + end.x
			c.car_dir = car.dir
			_go_to(c, d, false)
	rebuild_maps()


func _spawn_service_vehicles(dt: float) -> void:
	_service_t -= dt
	if _service_t > 0.0:
		return
	_service_t = randf_range(3, 7)
	var h := hour()
	if h < 7.0 or h > 21.0:
		return
	var bases: Array = stats.vehicle_bases.filter(func(b): return workers.get(b, []).size() > 0)
	if bases.is_empty():
		return
	var b: int = bases.pick_random()
	for k in cars:
		if k.base == b:
			return
	var starts := roads_around(b)
	if starts.is_empty():
		return
	var seen := _to_set(starts)
	var q: Array = starts.duplicate()
	var head := 0
	while head < q.size() and q.size() < 800:
		var u: int = q[head]
		head += 1
		for dv in DIRS:
			var nx: int = u % W + dv.x
			var ny: int = u / W + dv.y
			var ni := ny * W + nx
			if is_drivable(nx, ny) and not seen.has(ni):
				seen[ni] = true
				q.append(ni)
	var far: Array = q.filter(func(u): return absi(u % W - b % W) + absi(u / W - b / W) >= 4)
	if far.is_empty():
		return
	var route = road_route(starts, {far.pick_random(): true})
	if route == null or route.size() < 3:
		return
	var kind: String = D.def(objs[b].t).vehicle
	var car := _make_car(kind, D.SERVICE_COLORS[kind], route, null, -1, b)
	car.base = b
	cars.append(car)


# =====================================================================
#  Строительство
# =====================================================================

func can_place(t: String, x: int, y: int) -> Dictionary:
	var d := D.def(t)
	if d.is_empty() or not in_map(x, y):
		return {"ok": false}
	if not unlimited and max_cats < d.get("unlock", 0):
		return {"ok": false, "reason": tr("Пока закрыто")}
	if d.has("terra"):
		var i := y * W + x
		var o = objs[i]
		if terrain[i] == d.terra:
			return {"ok": false}
		if o != null and o.t != "road" and o.t != "path" and o.t != "blvd":
			return {"ok": false, "reason": tr("Сначала уберите постройку")}
		return {"ok": true, "cost": 0}
	if d.get("need_blvd", false):
		var near := false
		for dv in DIRS:
			var nb = obj_at(x + dv.x, y + dv.y)
			if nb != null and nb.t == "blvd":
				near = true
		if not near:
			return {"ok": false, "reason": tr("Ставится только рядом с Голливудским бульваром")}
	if d.get("need_rail", false):
		var near_rail := false
		var sz := D.size_of(t)
		for yy in range(y - 1, y + sz + 1):
			for xx in range(x - 1, x + sz + 1):
				var inside := xx >= x and xx < x + sz and yy >= y and yy < y + sz
				var corner := (xx == x - 1 or xx == x + sz) and (yy == y - 1 or yy == y + sz)
				if not inside and not corner and is_rail(xx, yy):
					near_rail = true
		if not near_rail:
			return {"ok": false, "reason": tr("Ставьте вплотную к рельсам")}
	if d.get("wonder", false) and wonder_built(t):
		return {"ok": false, "reason": tr("Эта достопримечательность уже есть в городе")}
	var w := D.size_of(t)
	var water := 0
	var cost: int = d.cost
	for yy in range(y, y + w):
		for xx in range(x, x + w):
			if not in_map(xx, yy):
				return {"ok": false, "reason": tr("Не помещается")}
			var i := yy * W + xx
			if objs[i] != null:
				return {"ok": false, "reason": tr("Здесь занято")}
			if terrain[i] == WATER:
				water += 1
	var high := 0
	var mount := 0
	for yy in range(y, y + w):
		for xx in range(x, x + w):
			if terrain[yy * W + xx] == MOUNTAIN:
				mount += 1
			if is_high(yy * W + xx):
				high += 1
	if d.get("need_high", false) and high < w * w:
		return {"ok": false, "reason": tr("Строится только на холмах и в горах")}
	if mount > 0 and not (d.has("cap") or t in ["road", "highway", "path", "blvd", "parking", "rail"] or (d.has("happy") and not d.has("jobs")) or d.get("wonder", false)):
		return {"ok": false, "reason": tr("Слишком круто: в горах — только жильё и дороги")}
	if water > 0:
		if t == "road":
			cost = 8
		elif t == "highway":
			cost = 14
		elif t == "path" or t == "blvd":
			cost = 6
		elif t == "rail":
			cost = 12
		else:
			return {"ok": false, "reason": tr("Нельзя на воде")}
	if d.get("need_water", false):
		var near := false
		for dv in DIRS:
			if in_map(x + dv.x, y + dv.y) and terrain[(y + dv.y) * W + x + dv.x] == WATER:
				near = true
		if not near:
			return {"ok": false, "reason": tr("Нужна вода рядом")}
	if unlimited:
		cost = 0
	if coins < cost:
		return {"ok": false, "reason": tr("Не хватает монеток"), "cost": cost}
	return {"ok": true, "cost": cost}


func wonder_built(t: String) -> bool:
	for i in W * H:
		var o = objs[i]
		if o != null and o.i == i and o.t == t:
			return true
	return false


func _terraform(x: int, y: int, kind: int) -> void:
	terrain[y * W + x] = kind
	mark_dirty(x, y, 1)
	compute_shore()
	if randf() < 0.5:
		_dust(x, y)
	if Time.get_ticks_msec() - _last_reason_ms > 90:
		_last_reason_ms = Time.get_ticks_msec()
		sound.play("pop", 0.8 if kind == WATER else 1.15)


func apply_tool(x: int, y: int, first: bool) -> void:
	if not in_map(x, y):
		return
	if tool == "bulldoze":
		_bulldoze(x, y, first)
		return
	var here = objs[y * W + x]
	if here != null and ((tool == "rail" and here.t == "road") or (tool == "road" and here.t == "rail")):
		_make_crossing(x, y)
		return
	var r := can_place(tool, x, y)
	if not r.ok:
		if r.has("reason") and first and Time.get_ticks_msec() - _last_reason_ms > 400:
			_last_reason_ms = Time.get_ticks_msec()
			float_text(Vector2(x * T + 8, y * T), r.reason, Color("c24a5a"))
		return
	var d := D.def(tool)
	if d.has("terra"):
		_terraform(x, y, d.terra)
		return
	coins -= r.cost
	place_obj(y * W + x, tool, randi() % 1000, d.get("build", 0.0))
	sound.play("pop")
	var w := D.size_of(tool)
	for k in w * w:
		_dust(x + k % w, y + k / w)
	if r.cost > 0:
		float_text(Vector2(x * T + 8 * w, y * T), "-%d" % r.cost, Color("8a5a3b"))
	recalc()


## Рельсы через дорогу (или дорога через рельсы) — переезд со шлагбаумом.
func _make_crossing(x: int, y: int) -> void:
	var cost := 0 if unlimited else 6
	if coins < cost:
		float_text(Vector2(x * T + 8, y * T), tr("Не хватает монеток"), Color("c24a5a"))
		return
	if not unlimited and max_cats < 6:
		return
	coins -= cost
	remove_obj(objs[y * W + x])
	place_obj(y * W + x, "crossing", 0, 0.0)
	sound.play("pop")
	_dust(x, y)
	recalc()


func _bulldoze(x: int, y: int, first: bool) -> void:
	var o = obj_at(x, y)
	if o == null:
		return
	var d := D.def(o.t)
	if d.get("natural", false) and unlimited:
		pass
	elif d.get("natural", false):
		if coins < 2.0:
			if first:
				float_text(Vector2(x * T + 8, y * T), tr("Нужно 2 монетки"), Color("c24a5a"))
			return
		coins -= 2.0
	else:
		var on_water: bool = terrain[o.i] == WATER
		var refund: int = 3 if (o.t == "road" or o.t == "path" or o.t == "blvd") and on_water else int(d.cost / 2)
		coins += refund
		if refund > 0:
			float_text(Vector2(x * T + 8, y * T), "+%d" % refund, Color("c08a1a"))
	var b: int = o.i
	remove_obj(o)
	for yy in o.w:
		for xx in o.w:
			_dust(b % W + xx, b / W + yy)
	sound.play("dig")
	recalc()
	_release_building(b, o)
	if info_target != null and info_target.has("tile") and info_target.tile == b:
		info_target = null


func _release_building(b: int, o: Dictionary) -> void:
	rebuild_maps()
	var x0 := b % W
	var y0 := b / W
	for c in cats.duplicate():
		if c.state == "in" and c.at == b:
			c.state = "idle"
			c.at = -1
			c.timer = 0.3
			c.x = float(x0 + randi() % o.w)
			c.y = float(y0 + randi() % o.w)
		if c.job == b:
			c.job = -1
		if c.plan != null and c.plan.has("b") and c.plan.b == b:
			c.plan = null
		if c.home == b:
			# котик не пропадает: гуляет рядом и ждёт новый дом
			c.home = -1
			c["ax"] = float(x0)
			c["ay"] = float(y0)
			if c.plan != null and c.plan.kind == "home":
				c.plan = null
			ui.toast(tr("%s остался без дома и ждёт новый") % I18n.cat(c.name), false, true)
	rebuild_maps()


func _update_construction(dt: float) -> void:
	if stats.constructing.is_empty():
		return
	var yards: int = stats.builder_yards.filter(func(b): return workers.get(b, []).size() > 0).size()
	var spd := 1.0 + minf(2.0, yards * 0.75)
	var done := false
	for b in stats.constructing:
		var o = objs[b]
		if o == null or o.i != b or o.build <= 0.0:
			continue
		o.build -= dt * spd
		if o.build <= 0.0:
			o.build = 0.0
			done = true
			var cp := Vector2(b % W * T + o.w * 8, b / W * T + o.w * 8)
			for k in 14:
				add_p({"type": "sparkle", "x": cp.x + randf_range(-10, 10), "y": cp.y + randf_range(-10, 6), "vx": randf_range(-25, 25), "vy": randf_range(-35, -10), "life": randf_range(0.7, 1.3)})
			float_text(cp + Vector2(0, -10), tr("%s — готово!") % tr(D.def(o.t).name), Color("4f8a4f"))
			sound.play("pop")
			if D.def(o.t).get("wonder", false):
				ui.toast(tr("Достопримечательность построена: %s! Туристы уже едут.") % tr(D.def(o.t).name), true, true)
				sound.play("chime")
				for k in 30:
					add_p({"type": "sparkle", "x": cp.x + randf_range(-20, 20), "y": cp.y + randf_range(-30, 6), "vx": randf_range(-30, 30), "vy": randf_range(-45, -10), "life": randf_range(1.0, 2.0)})
				hearts_at(cp + Vector2(0, -20), 8)
	if done:
		recalc()


# =====================================================================
#  Частицы и надписи
# =====================================================================

func add_p(p: Dictionary) -> void:
	if parts.size() < 600:
		p["mx"] = p.life
		parts.append(p)


func hearts_at(pos: Vector2, n: int) -> void:
	for k in n:
		add_p({"type": "heart", "x": pos.x + randf_range(-5, 5), "y": pos.y + randf_range(-3, 3), "vx": randf_range(-8, 8), "vy": randf_range(-26, -14), "life": randf_range(0.9, 1.5)})


func _dust(x: int, y: int) -> void:
	for k in 6:
		add_p({"type": "dust", "x": x * T + randf_range(2, 14), "y": y * T + randf_range(8, 15), "vx": randf_range(-20, 20), "vy": randf_range(-18, -4), "life": randf_range(0.4, 0.8)})


func float_text(pos: Vector2, text: String, color: Color) -> void:
	# в режиме «Дзен» — тишина: остаются только красные подсказки о том, почему нельзя строить
	if ui != null and ui.zen and color != Color("c24a5a"):
		return
	floats.append({"pos": pos, "text": text, "color": color, "life": 1.6, "mx": 1.6})


func _ambient(dt: float) -> void:
	var v := visible_range()
	for y in range(v[1], v[3] + 1):
		for x in range(v[0], v[2] + 1):
			var i := y * W + x
			var o = objs[i]
			if o == null or o.i != i:
				continue
			if o.build > 0.0:
				if randf() < dt * 3.0:
					add_p({"type": "sparkle", "x": x * T + o.w * 8 + randf_range(-o.w * 6, o.w * 6), "y": (y + o.w) * T - randf_range(4, o.w * 14), "vx": randf_range(-10, 10), "vy": randf_range(-20, -5), "life": 0.5})
				continue
			var d := D.def(o.t)
			if o.t == "jacaranda" and randf() < dt * 0.25:
				add_p({"type": "petal", "x": x * T + randf_range(2, 14), "y": y * T + randf_range(-6, 4), "vx": randf_range(4, 12), "vy": randf_range(5, 10), "life": randf_range(2, 3.5), "ph": randf() * 6.0})
			elif o.t == "fountain" and randf() < dt * 8.0:
				add_p({"type": "drop", "x": x * T + 8 + randf_range(-1, 1), "y": y * T - 3, "vx": randf_range(-14, 14), "vy": randf_range(-28, -18), "g": 90.0, "life": 0.55})
			elif d.get("smoke", false) and workers.get(i, []).size() > 0 and randf() < dt * 2.0:
				add_p({"type": "smoke", "x": x * T + 27, "y": y * T - 8, "vx": randf_range(2, 8), "vy": randf_range(-12, -7), "life": randf_range(2, 3)})
			elif d.has("shop") and inside_count.get(i, 0) > 0 and randf() < dt * 0.15:
				add_p({"type": "coin", "x": x * T + o.w * 8, "y": (y + o.w) * T - 26, "vx": 0.0, "vy": -12.0, "life": 1.2})
			elif o.t == "flowers" and dark < 0.1 and randf() < dt * 0.02:
				add_p({"type": "bfly", "x": x * T + 8, "y": y * T + 4, "vx": randf_range(-10, 10), "vy": randf_range(-6, 2), "life": randf_range(5, 8), "ph": randf() * 6.0, "col": ["fff3a0", "ffffff", "c8a8ff"].pick_random()})
			elif (o.t == "wildpalm" or o.t == "palm") and dark > 0.25 and randf() < dt * 0.05:
				add_p({"type": "firefly", "x": x * T + randf_range(0, 16), "y": y * T + randf_range(-4, 12), "vx": randf_range(-5, 5), "vy": randf_range(-5, 5), "life": randf_range(3, 6), "ph": randf() * 6.0})
			elif d.has("cap") and dark > 0.2 and inside_count.get(i, 0) > 0 and randf() < dt * 0.1:
				add_p({"type": "z", "x": x * T + o.w * 8 + 3, "y": (y + o.w) * T - 26, "vx": randf_range(2, 6), "vy": -8.0, "life": 1.8})


func _ambient_gulls(dt: float) -> void:
	if dark > 0.2 or randf() > dt * 0.5:
		return
	var v := visible_range()
	for attempt in 6:
		var x := randi_range(v[0], v[2])
		var y := randi_range(v[1], v[3])
		if terrain[y * W + x] == WATER:
			add_p({"type": "gull", "x": x * T + 8.0, "y": y * T - 6.0, "vx": randf_range(-14, 14), "vy": randf_range(-3, 3), "life": randf_range(6, 10), "ph": randf() * 6.0})
			return


func _update_parts(dt: float) -> void:
	var k := parts.size() - 1
	while k >= 0:
		var p: Dictionary = parts[k]
		p.life -= dt
		if p.life <= 0.0:
			if p.type == "rocket":
				events.burst(p)
			parts.remove_at(k)
			k -= 1
			continue
		if p.has("g"):
			p.vy += p.g * dt
		if p.type == "balloon" or p.type == "confetti":
			p.vx = sin(p.life * 3.0 + p.ph) * 6.0
		if p.type == "petal":
			p.vx = 8.0 + sin(p.life * 3.0 + p.ph) * 10.0
		if p.type == "bfly" or p.type == "firefly":
			p.vx += sin(p.life * 2.0 + p.ph) * 20.0 * dt
			p.vy += cos(p.life * 1.7 + p.ph) * 20.0 * dt
		p.x += p.vx * dt
		p.y += p.vy * dt
		k -= 1
	k = floats.size() - 1
	while k >= 0:
		floats[k].life -= dt
		if floats[k].life <= 0.0:
			floats.remove_at(k)
		k -= 1


# =====================================================================
#  Главный цикл
# =====================================================================

func _process(delta: float) -> void:
	var dt := minf(0.1, delta)
	anim_time += dt
	_key_pan(dt)
	# на больших скоростях считаем мелкими шагами, чтобы машины не «перепрыгивали»
	var gdt := dt * speed
	while gdt > 0.0:
		var s := minf(gdt, 0.05)
		_step(s)
		gdt -= s
	_ambient_t += dt
	if _ambient_t > 0.1:
		_ambient(_ambient_t * maxf(speed, 0.3))
		_ambient_gulls(_ambient_t)
		_ambient_t = 0.0
	_update_parts(dt)
	dark = darkness(hour())
	if not dirty_tiles.is_empty():
		for key in dirty_tiles:
			_draw_tile(key % W, key / W)
		dirty_tiles.clear()
		terrain_tex.update(terrain_img)
	_goal_t += dt
	if _goal_t > 1.0:
		_goal_t = 0.0
		var got: Array = goals.check()
		if not got.is_empty():
			ui.goals_done(got)
	_amb_t += dt
	if _amb_t > 0.5:
		_amb_t = 0.0
		_update_ambience()
	_save_t += dt
	if _save_t > 10.0:
		_save_t = 0.0
		save_game()
	queue_redraw()


func _step(gdt: float) -> void:
	var was_night := is_night()
	time += gdt / DAY_LEN
	if time >= 1.0:
		time -= 1.0
		day += 1
		ui.toast(tr("Доброе утро! Начинается день %d") % day, false, true)
	if was_night != is_night():
		sound.night = is_night()
	rebuild_maps()
	_job_t -= gdt
	if _job_t <= 0.0:
		_job_t = 1.0
		_assign_homes()
		_assign_jobs()
	_update_economy(gdt)
	_update_construction(gdt)
	for c in cats:
		_update_cat(c, gdt)
	_update_cars(gdt)
	jammed = 0
	for car in cars:
		if car.get("wait", 0.0) > 4.0 or car.get("passing", false):
			jammed += 1
	_spawn_service_vehicles(gdt)
	_update_freight(gdt)
	events.update(gdt)
	transit.update(gdt)
	boats.update(gdt)
	_light_clock += gdt


# =====================================================================
#  Камера и ввод
# =====================================================================

func view_size() -> Vector2:
	return get_viewport_rect().size / float(zoom)


func _apply_zoom() -> void:
	if cam:
		cam.zoom = Vector2(zoom, zoom)


func center_cam(tx: float, ty: float) -> void:
	cam.position = Vector2(tx * T + 8, ty * T + 8)
	clamp_cam()


func clamp_cam() -> void:
	cam.position.x = clampf(cam.position.x, 0.0, W * T)
	cam.position.y = clampf(cam.position.y, 0.0, H * T)


func set_zoom(z: int, screen_pos = null) -> void:
	z = clampi(z, ZOOM_MIN, ZOOM_MAX)
	if z == zoom:
		return
	var vp := get_viewport_rect().size
	var sp: Vector2 = screen_pos if screen_pos != null else vp / 2.0
	var world_before := cam.position + (sp - vp / 2.0) / float(zoom)
	zoom = z
	_apply_zoom()
	cam.position = world_before - (sp - vp / 2.0) / float(zoom)
	clamp_cam()


func visible_range() -> Array:
	var vs := view_size()
	var tl := cam.position - vs / 2.0
	return [
		maxi(0, int(floor(tl.x / T)) - 2), maxi(0, int(floor(tl.y / T)) - 2),
		mini(W - 1, int(ceil((tl.x + vs.x) / T)) + 1), mini(H - 1, int(ceil((tl.y + vs.y) / T)) + 3),
	]


func _key_pan(dt: float) -> void:
	var sp := 500.0 / zoom * dt
	var dv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dv.x -= sp
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dv.x += sp
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dv.y -= sp
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dv.y += sp
	if dv != Vector2.ZERO:
		cam.position += dv
		clamp_cam()


func _update_mouse() -> void:
	var m := get_global_mouse_position()
	mouse_tile = Vector2i(int(floor(m.x / T)), int(floor(m.y / T)))
	mouse_in = true


func cat_at(wp: Vector2):
	var best = null
	for c in cats:
		if c.state == "in" or c.state == "drive" or c.state == "ride":
			continue
		var sx: float = c.x * T + 3
		var sy: float = c.y * T - 1
		if wp.x >= sx - 2 and wp.x <= sx + 12 and wp.y >= sy and wp.y <= sy + 17:
			if best == null or c.y > best.y:
				best = c
	if best != null:
		return best
	for car in cars:
		if car.cat != null and absf(wp.x - car.px) <= 9 and wp.y >= car.py - 10 and wp.y <= car.py + 5:
			return car.cat
	return null


func _unhandled_input(event: InputEvent) -> void:
	if ui.title_open():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() == 2:
			# второй палец: отменяем стройку и перетаскивание одним пальцем
			_pan_active = false
			_painting = false
			_touch_pending = false
			_begin_pinch()
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			_pinch_move()
		return
	if _touches.size() >= 2 and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventMouseButton:
		_update_mouse()
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom + 1, mb.position)
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom - 1, mb.position)
			return
		if mb.pressed:
			ui.hide_tooltip()
			if mb.button_index == MOUSE_BUTTON_LEFT and tool != "hand":
				# касание пальцем: строим, когда палец отпущен — вдруг это жест двумя пальцами
				if mb.device == InputEvent.DEVICE_ID_EMULATION:
					_touch_pending = true
					_last_paint = mouse_tile.y * W + mouse_tile.x
					return
				_painting = true
				_last_paint = mouse_tile.y * W + mouse_tile.x
				apply_tool(mouse_tile.x, mouse_tile.y, true)
				return
			_pan_active = true
			_pan_moved = false
			_pan_button = mb.button_index
			_pan_start = mb.position
			_pan_cam = cam.position
		else:
			if _touch_pending:
				_touch_pending = false
				_painting = false
				apply_tool(mouse_tile.x, mouse_tile.y, true)
				return
			if _pan_active and not _pan_moved:
				if _pan_button == MOUSE_BUTTON_LEFT:
					_click(get_global_mouse_position())
				elif _pan_button == MOUSE_BUTTON_RIGHT and tool != "hand":
					select_tool("hand")
			_pan_active = false
			_painting = false
	elif event is InputEventMouseMotion:
		_update_mouse()
		var mm := event as InputEventMouseMotion
		if _pan_active:
			var dlt := mm.position - _pan_start
			if absf(dlt.x) + absf(dlt.y) > 5.0:
				_pan_moved = true
			if _pan_moved:
				cam.position = _pan_cam - dlt / float(zoom)
				clamp_cam()
		elif _painting:
			var i := mouse_tile.y * W + mouse_tile.x
			var d := D.def(tool)
			if i != _last_paint and (tool == "bulldoze" or d.get("paint", false)):
				_last_paint = i
				apply_tool(mouse_tile.x, mouse_tile.y, false)
		elif _touch_pending:
			# провели пальцем — для дорог и рельефа начинаем «рисовать»
			var i := mouse_tile.y * W + mouse_tile.x
			var d := D.def(tool)
			if i != _last_paint and (tool == "bulldoze" or d.get("paint", false)):
				_touch_pending = false
				_painting = true
				apply_tool(_last_paint % W, _last_paint / W, true)
				_last_paint = i
				apply_tool(mouse_tile.x, mouse_tile.y, false)
		_update_cursor()
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		if g.factor > 1.05:
			set_zoom(zoom + 1, g.position)
		elif g.factor < 0.95:
			set_zoom(zoom - 1, g.position)
	elif event is InputEventPanGesture:
		cam.position += (event as InputEventPanGesture).delta * 8.0 / float(zoom)
		clamp_cam()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.physical_keycode:
			KEY_ESCAPE:
				select_tool("hand")
				info_target = null
				ui.close_modals()
			KEY_B:
				select_tool("bulldoze")
			KEY_H:
				select_tool("hand")
			KEY_TAB:
				ui.next_tab(-1 if k.shift_pressed else 1)
			KEY_EQUAL, KEY_KP_ADD:
				set_zoom(zoom + 1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_zoom(zoom - 1)
			KEY_Z:
				ui.set_zen(not ui.zen)
			KEY_V:
				ui.set_build_hidden(not ui.build_hidden)
			KEY_SPACE:
				cycle_speed()
			_:
				if k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9:
					ui.select_tab_tool(k.physical_keycode - KEY_1)
		get_viewport().set_input_as_handled()


func _begin_pinch() -> void:
	var pts: Array = _touches.values()
	_pinch_d = maxf(1.0, (pts[0] as Vector2).distance_to(pts[1]))
	_pinch_mid = ((pts[0] as Vector2) + (pts[1] as Vector2)) / 2.0


func _pinch_move() -> void:
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var mid := (a + b) / 2.0
	var d := maxf(1.0, a.distance_to(b))
	cam.position -= (mid - _pinch_mid) / float(zoom)
	_pinch_mid = mid
	clamp_cam()
	# масштаб ступенчатый (пиксели остаются чёткими), поэтому меняем его по порогам
	if d / _pinch_d > 1.3:
		set_zoom(zoom + 1, mid)
		_pinch_d = d
	elif d / _pinch_d < 0.75:
		set_zoom(zoom - 1, mid)
		_pinch_d = d


func _update_cursor() -> void:
	var shape := Input.CURSOR_CROSS
	if tool == "hand":
		shape = Input.CURSOR_DRAG if _pan_moved else Input.CURSOR_ARROW
		var o = obj_at(mouse_tile.x, mouse_tile.y)
		if cat_at(get_global_mouse_position()) != null or (o != null and o.t != "path" and o.t != "blvd" and o.t != "road"):
			shape = Input.CURSOR_POINTING_HAND
	Input.set_default_cursor_shape(shape)


func _click(wp: Vector2) -> void:
	var c = cat_at(wp)
	if c != null:
		pet_cat(c)
		info_target = {"cat": c}
		return
	var o = obj_at(mouse_tile.x, mouse_tile.y)
	if o != null and o.t != "path" and o.t != "blvd" and o.t != "road":
		info_target = {"tile": o.i}
	else:
		info_target = null


func select_tool(t: String) -> void:
	var d := D.def(t)
	if not d.is_empty() and not unlimited and max_cats < d.get("unlock", 0):
		ui.toast(tr("«%s» откроется, когда в городе будет %d котиков") % [tr(d.name), d.unlock])
		return
	tool = t
	ui.refresh_tools()


func cycle_speed() -> void:
	speed = (speed + 1) % 4
	ui.refresh_speed()


# =====================================================================
#  Отрисовка земли (в картинку, обновляется по клеткам)
# =====================================================================

func mark_dirty(x0: int, y0: int, w: int) -> void:
	for y in range(y0 - 2, y0 + w + 2):
		for x in range(x0 - 2, x0 + w + 2):
			if in_map(x, y):
				dirty_tiles[y * W + x] = true


var shore: Array = []


func _render_terrain_full() -> void:
	for y in H:
		for x in W:
			_draw_tile(x, y)
	dirty_tiles.clear()
	compute_shore()


func compute_shore() -> void:
	shore = []
	for y in H:
		for x in W:
			if terrain[y * W + x] != WATER:
				continue
			for dv in DIRS:
				var nx: int = x + dv.x
				var ny: int = y + dv.y
				if in_map(nx, ny) and terrain[ny * W + nx] != WATER:
					shore.append([x, y, dv])


func _is_land(x: int, y: int) -> bool:
	return in_map(x, y) and terrain[y * W + x] != WATER


func _r(px: int, py: int, a: int, b: int, w: int, h: int, col: String) -> void:
	terrain_img.fill_rect(Rect2i(px + a, py + b, w, h), Color(col))


func _draw_tile(x: int, y: int) -> void:
	var px := x * T
	var py := y * T
	var i := y * W + x
	var t := terrain[i]
	var hs := func(k: int) -> float: return hashf(x, y, k)
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
	var o = objs[i]
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
	return terrain[y * W + x] if in_map(x, y) else WATER


func _is_high_at(x: int, y: int) -> bool:
	return in_map(x, y) and is_high(y * W + x)


## Магистраль: 2 полосы в каждую сторону, двойная жёлтая посередине.
func _draw_highway(px: int, py: int, x: int, y: int, water: bool) -> void:
	var up := is_highway(x, y - 1)
	var dn := is_highway(x, y + 1)
	var lf := is_highway(x - 1, y)
	var rt := is_highway(x + 1, y)
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
		_hw_edge(px, py, is_road(x, y - 1), 0, true, edge)
		_hw_edge(px, py, is_road(x, y + 1), 15, true, edge)
	else:
		_r(px, py, 7, 0, 1, 16, "ffd23f"); _r(px, py, 8, 0, 1, 16, "ffd23f")
		_r(px, py, 4, 1, 1, 5, "ffffff"); _r(px, py, 4, 9, 1, 5, "ffffff")
		_r(px, py, 11, 1, 1, 5, "ffffff"); _r(px, py, 11, 9, 1, 5, "ffffff")
		_hw_edge(px, py, is_road(x - 1, y), 0, false, edge)
		_hw_edge(px, py, is_road(x + 1, y), 15, false, edge)


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
	var up := is_road(x, y - 1) or (is_highway(x, y - 1) and not is_road(x - 1, y) and not is_road(x + 1, y))
	var dn := is_road(x, y + 1) or (is_highway(x, y + 1) and not is_road(x - 1, y) and not is_road(x + 1, y))
	var lf := is_road(x - 1, y) or (is_highway(x - 1, y) and not is_road(x, y - 1) and not is_road(x, y + 1))
	var rt := is_road(x + 1, y) or (is_highway(x + 1, y) and not is_road(x, y - 1) and not is_road(x, y + 1))
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
	if not water and is_crosswalk(x, y):
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
	var lf := is_rail(x - 1, y)
	var rt := is_rail(x + 1, y)
	var up := is_rail(x, y - 1)
	var dn := is_rail(x, y + 1)
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


## Шлагбаумы на переездах: закрыты, пока рядом поезд.
func _draw_crossings(v: Array) -> void:
	for i in crossings:
		var x: int = i % W
		var y: int = i / W
		if x < v[0] or x > v[2] or y < v[1] or y > v[3]:
			continue
		var shut: bool = transit.closed.has(i)
		var rail_h := is_rail(x - 1, y) or is_rail(x + 1, y)
		var px := x * T
		var py := y * T
		var blink := int(anim_time * 4.0) % 2 == 0
		for k in 2:
			var post: Vector2
			if rail_h:
				post = Vector2(px + (1 if k == 0 else 14), py + (1 if k == 0 else 14))
			else:
				post = Vector2(px + (14 if k == 0 else 1), py + (1 if k == 0 else 14))
			draw_rect(Rect2(post.x, post.y - 6, 1, 7), Color("4a4458"))
			draw_rect(Rect2(post.x - 1, post.y - 7, 3, 2), Color("e0483a") if shut and (blink == (k == 0)) else Color("5a3a3a"))
			if shut and blink == (k == 0) and dark > 0.1:
				lights.append(Vector3(post.x + 0.5, post.y - 6, 6))
			if shut:
				# опущенная стрела поперёк дороги, красно-белая
				for s in 7:
					var col := Color("e0483a") if s % 2 == 0 else Color("f4f4f8")
					if rail_h:
						draw_rect(Rect2(post.x + (1 + s if k == 0 else -1 - s), post.y - 4, 1, 1), col)
					else:
						draw_rect(Rect2(post.x - 4, post.y + (1 + s if k == 0 else -1 - s) - 4, 1, 1), col)
			else:
				for s in 5:
					draw_rect(Rect2(post.x + 1, post.y - 7 - s, 1, 1), Color("e0483a") if s % 2 == 0 else Color("f4f4f8"))


func _path_conn(x: int, y: int) -> bool:
	var n = obj_at(x, y)
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


# =====================================================================
#  Отрисовка мира
# =====================================================================

func _draw() -> void:
	if terrain_tex == null:
		return
	draw_texture(terrain_tex, Vector2.ZERO)
	var v := visible_range()
	var tick := int(anim_time * 1.5)
	var sparkle := Color("d6f2fa")
	for y in range(v[1], v[3] + 1):
		for x in range(v[0], v[2] + 1):
			if terrain[y * W + x] != WATER or objs[y * W + x] != null:
				continue
			if hashf(x, y, tick) < 0.18:
				draw_rect(Rect2(x * T + int(hashf(x, y, tick + 3) * 12) + 2, y * T + int(hashf(x, y, tick + 7) * 12) + 2, 2, 1), sparkle)

	var foam := Color(1, 1, 1, 0.75)
	for sh in shore:
		var x: int = sh[0]
		var y: int = sh[1]
		if x < v[0] or x > v[2] or y < v[1] or y > v[3] or objs[y * W + x] != null:
			continue
		var dv: Vector2i = sh[2]
		var off := 2 + roundi((sin(anim_time * 1.6 + x * 0.7 + y * 0.5) + 1.0) * 1.5)
		match dv:
			Vector2i(0, -1):
				draw_rect(Rect2(x * T, y * T + off, T, 1), foam)
			Vector2i(0, 1):
				draw_rect(Rect2(x * T, y * T + T - 1 - off, T, 1), foam)
			Vector2i(-1, 0):
				draw_rect(Rect2(x * T + off, y * T, 1, T), foam)
			Vector2i(1, 0):
				draw_rect(Rect2(x * T + T - 1 - off, y * T, 1, T), foam)

	var h := hour()
	lights = []
	var list := []
	for y in range(v[1], v[3] + 1):
		for x in range(v[0], v[2] + 1):
			var i := y * W + x
			var o = objs[i]
			if o != null and o.i == i and o.t != "path" and o.t != "blvd" and o.t != "road" and pairs.get(i, "") != "R":
				# плоские постройки (парковки, корты) — часть земли: котики и машины поверх них
				list.append([(y * T - 8.0) if FLAT.has(o.t) else float((y + o.w) * T), 0, o, x, y])
				if SCENES.has(o.t) and _scene_on(o, h):
					list.append([float((y + o.w) * T) + 2.0, 5, o])
	for c in cats:
		if c.state == "in" or c.state == "drive" or c.state == "ride":
			continue
		if c.x < v[0] - 1 or c.x > v[2] + 1 or c.y < v[1] - 1 or c.y > v[3] + 1:
			continue
		list.append([c.y * T + 14.0, 1, c])
	for car in cars:
		list.append([car.py + 4.0, 2, car])
	for vis in events.visitors:
		list.append([vis.y * T + 14.0, 3, vis])
	transit.draw_items(list)
	boats.draw_items(list)
	for c in street_parked:
		var tx: int = c.car_tile % W
		var ty: int = c.car_tile / W
		if tx < v[0] or tx > v[2] or ty < v[1] or ty > v[3]:
			continue
		var off: Vector2 = LANE.get(c.car_dir, Vector2.ZERO)
		var pc := {"kind": car_model(c), "color": c.car, "px": tx * T + 8.0 + off.x, "py": ty * T + 8.0 + off.y, "dir": c.car_dir, "cat": null, "parked": true}
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
				transit.draw_segment(it[2])
			5:
				_draw_scene(it[2])
			6:
				boats.draw_boat(it[2])
			7:
				transit.draw_heli(it[2])

	_draw_bunting()
	_draw_traffic_lights(v)
	_draw_crossings(v)
	_draw_ramp_signs(v)
	_draw_ghost()
	_draw_particles()
	transit.draw_planes()


func _draw_obj(o: Dictionary, x: int, y: int, h: float) -> void:
	if o.build > 0.0:
		_draw_construction(o, x, y)
		return
	var paired: bool = pairs.get(o.i, "") == "L"
	var tx: Texture2D
	var wins: Array
	if paired:
		var pv: Array = spr.pair_variant(o)
		tx = pv[0]
		wins = pv[1]
	else:
		tx = spr.obj_texture(o)
		if tx != null:
			wins = spr.windows_for(o)
	if tx == null:
		return
	var span: int = 2 if paired else o.w
	var sx: int = x * T + (span * T - tx.get_width()) / 2
	var sy: int = (y + o.w) * T - tx.get_height()
	draw_texture(tx, Vector2(sx, sy))
	var mk = D.MAKES.get(o.t)
	if mk != null and float(o.get("out", 0.0)) >= 4.0:
		# готовые ящики с товаром у здания
		var gc := Color(D.GOODS[mk[0]].col)
		var by: int = (y + o.w) * T - 4
		for k in mini(4, int(o.out / 4.0)):
			var bx: int = x * T + o.w * T - 7 - (k % 2) * 5
			var yy: int = by - (k / 2) * 3
			draw_rect(Rect2(bx, yy, 5, 4), Color("5a3c30"))
			draw_rect(Rect2(bx + 1, yy + 1, 3, 2), gc)
	if o.t == "parking" or o.t == "garage":
		var slots: Array = spr.PARKING_SLOTS if o.t == "parking" else spr.GARAGE_SLOTS
		var cols: Array = lot_colors.get(o.i, [])
		for k in mini(cols.size(), slots.size()):
			var sl: Vector2i = slots[k]
			var big: bool = o.t == "parking"
			draw_rect(Rect2(sx + sl.x, sy + sl.y, 5 if big else 4, 3 if big else 2), Color(cols[k]))
			draw_rect(Rect2(sx + sl.x + 1, sy + sl.y, 2, 1), Color("bfe6f7"))
	if wins.size() > 0 and dark > 0.08:
		var d := D.def(o.t)
		var lit: bool
		if o.t == "lantern":
			lit = true
		elif d.get("leisure", false) or d.get("wonder", false):
			lit = (h >= 17.0 and h < 23.5) or inside_count.get(o.i, 0) > 0
		else:
			lit = inside_count.get(o.i, 0) > 0 or (paired and inside_count.get(o.i + 1, 0) > 0)
		if lit:
			# горят не все окна — у каждого здания свой рисунок света
			var few: bool = wins.size() <= 2 or o.t == "lantern"
			for k in wins.size():
				if not few and hashf(o.i, k, 77) > 0.6:
					continue
				var wr: Rect2i = wins[k]
				var glow := Color("ffd36e") if hashf(o.i, k, 78) < 0.7 else Color("ffe9a8")
				draw_rect(Rect2(sx + wr.position.x, sy + wr.position.y, wr.size.x, wr.size.y), glow)
			var r := 48.0 if o.t == "lantern" else (34.0 if o.w == 2 or paired else 18.0)
			var mid: Rect2i = wins[wins.size() / 2]
			lights.append(Vector3(sx + mid.position.x + 2, sy + mid.position.y + 2, r))


func _draw_construction(o: Dictionary, x: int, y: int) -> void:
	var tx: Texture2D = spr.scaffold[o.w]
	var sx: int = x * T + (o.w * T - tx.get_width()) / 2
	var sy: int = (y + o.w) * T - tx.get_height()
	draw_texture(tx, Vector2(sx, sy))
	var total: float = D.def(o.t).get("build", 1.0)
	var k := clampf(1.0 - o.build / total, 0.0, 1.0)
	draw_rect(Rect2(sx + 2, sy - 4, tx.get_width() - 4, 3), INK)
	draw_rect(Rect2(sx + 3, sy - 3, roundi((tx.get_width() - 6) * k), 1), Color("7fd38f"))
	# строитель в каске стучит молотком
	var fs: Dictionary = spr.cat_set(["ginger", "gray", "tabby", "cream"][int(o.v) % 4], "builder")
	var up := int(anim_time * 4.0) % 2 == 1
	var frame: Texture2D = fs.walkA[1] if up else fs.stand[1]
	var bx := sx + tx.get_width() - 7
	var by: int = (y + o.w) * T - 15
	draw_texture(frame, Vector2(bx, by))
	draw_rect(Rect2(bx - 1, by + (8 if up else 10), 2, 1), Color("6a6478"))
	draw_rect(Rect2(bx, by + (9 if up else 11), 1, 2), Color("8a5a3b"))


func _cat_texture(c: Dictionary) -> Texture2D:
	var fs: Dictionary = spr.cat_set(c.color, outfit_key(c))
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
	draw_rect(Rect2(sx + 1, sy + 15, 8, 1), Color(0.157, 0.118, 0.196, 0.2))
	draw_texture(tx, Vector2(sx, sy))
	if info_target != null and info_target.has("cat") and info_target.cat == c:
		var bob := roundi(sin(anim_time * 5.0) * 1.5)
		draw_texture(spr.small.heart, Vector2(sx + 3, sy - 4 + bob))


## Гость события: котик в праздничной одежде, появляется и исчезает плавно.
func _draw_visitor(v: Dictionary) -> void:
	var fs: Dictionary = spr.cat_set(v.color, v.outfit)
	var f := 1 if v.dir < 0 else 0
	var tx: Texture2D = fs.stand[f]
	if v.walking:
		tx = fs.walkB[f] if int(v.anim * 6.0) % 2 == 1 else fs.walkA[f]
	var sx := roundi(v.x * T + 3)
	var sy := roundi(v.y * T - 1)
	if not v.walking and events.active != null and (events.active.kind == "game" or events.active.kind == "beach"):
		sy -= int(v.anim * 3.0) % 2  # пританцовывают
	var m := Color(1, 1, 1, clampf(v.fade, 0.0, 1.0))
	draw_rect(Rect2(sx + 1, sy + 15, 8, 1), Color(0.157, 0.118, 0.196, 0.2 * m.a))
	draw_texture(tx, Vector2(sx, sy), m)


## Флажки-гирлянда над местом праздника.
func _draw_bunting() -> void:
	var ev = events.active
	if ev == null or not (ev.kind == "beach" or ev.kind == "market" or ev.kind == "tourists"):
		return
	var c: Vector2 = ev.pos * T + Vector2(8, -6)
	var cols := ["ff6b8b", "ffd75e", "7fc4e8", "9ed8c8", "c8a8ff"]
	var a := c + Vector2(-34, 0)
	var b := c + Vector2(34, 0)
	draw_line(a + Vector2(0, -6), a + Vector2(0, 14), INK, 1.0)
	draw_line(b + Vector2(0, -6), b + Vector2(0, 14), INK, 1.0)
	for k in 17:
		var t := k / 16.0
		var p := a.lerp(b, t) + Vector2(0, -6 + sin(t * PI) * 6.0)
		if k < 16:
			var q := a.lerp(b, (k + 1) / 16.0) + Vector2(0, -6 + sin((k + 1) / 16.0 * PI) * 6.0)
			draw_line(p, q, Color(INK, 0.7), 1.0)
		if k % 2 == 1:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 0), p + Vector2(2, 0), p + Vector2(0, 4)]), Color(cols[(k / 2) % cols.size()]))


const LIGHT_COLS := [Color("e0483a"), Color("ffd23f"), Color("5fd38f")]


## Светофоры на углах перекрёстков: слева сверху — для едущих по горизонтали, справа снизу — по вертикали.
func _draw_traffic_lights(v: Array) -> void:
	for i in junctions:
		var x: int = i % W
		var y: int = i / W
		if x < v[0] or x > v[2] or y < v[1] or y > v[3]:
			continue
		for k in 2:
			var horiz := k == 0
			var bx := x * T + (0 if horiz else 15)
			var by := y * T + (2 if horiz else 13)
			var stt := light_state(i, horiz)
			draw_rect(Rect2(bx, by - 6, 1, 7), Color("4a4458"))
			draw_rect(Rect2(bx - 1, by - 10, 3, 5), INK)
			var lc: Color = LIGHT_COLS[stt]
			draw_rect(Rect2(bx, by - 9 + (2 - stt) * 1, 1, 1), lc)
			if dark > 0.15:
				lights.append(Vector3(bx + 0.5, by - 8.5, 5))


## Зелёные указатели фривея у въездов на магистраль.
func _draw_ramp_signs(v: Array) -> void:
	for r in ramps:
		var i: int = r[0]
		var dv: Vector2i = r[1]
		var x := i % W
		var y := i / W
		if x < v[0] or x > v[2] or y < v[1] or y > v[3]:
			continue
		var bx := x * T + (14 if dv.x <= 0 else 1)
		var by := y * T + 13
		draw_rect(Rect2(bx, by - 8, 1, 9), Color("4a4458"))
		var sx := bx - 5
		var sy := by - 15
		draw_rect(Rect2(sx, sy, 11, 7), Color("f4f4f8"))
		draw_rect(Rect2(sx + 1, sy + 1, 9, 5), Color("2f8a4f"))
		# щит шоссе «101» и стрелка
		draw_rect(Rect2(sx + 2, sy + 2, 3, 3), Color("f4f4f8"))
		draw_rect(Rect2(sx + 3, sy + 3, 1, 1), Color("3d5a98"))
		# стрелка к магистрали
		var ac := Vector2(sx + 7, sy + 3)
		var f := Vector2(dv)
		var side := Vector2(-f.y, f.x)
		# галочка-шеврон «туда»
		for q in [ac + f, ac + side, ac - side, ac - f + side * 2, ac - f - side * 2]:
			draw_rect(Rect2(q, Vector2.ONE), Color("f4f4f8"))


## Въезды на парковки: опущенный бордюр, светлая полоса, стоп-линия и стрелка внутрь.
func _draw_driveways(v: Array) -> void:
	var apron := Color("a9a6b8")
	var edge := Color("d8d4e4")
	var arrow := Color("ffd23f")
	for l in stats.lots:
		var o = objs[l]
		if o == null:
			continue
		var lx: int = l % W
		var ly: int = l / W
		if lx + o.w < v[0] or lx > v[2] or ly + o.w < v[1] or ly > v[3]:
			continue
		var made := 0
		for p in around(l):
			if made >= (2 if o.w > 1 else 1) or not is_road(p.x, p.y):
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
			draw_rect(r, apron)
			# бортики по краям съезда
			draw_rect(Rect2(c - fd * 2.0 - side * 7.0, fd * 8.0 + side).abs(), edge)
			draw_rect(Rect2(c - fd * 2.0 + side * 6.0, fd * 8.0 + side).abs(), edge)
			# пунктирная стоп-линия на выезде
			var sl := c + fd * 5.0
			for k in range(-5, 6, 2):
				draw_rect(Rect2(sl + side * k, Vector2.ONE), Color(1, 1, 1, 0.9))
			# стрелка внутрь парковки
			var tip := c - fd * 1.0
			for q in [tip, tip + fd + side, tip + fd - side, tip + fd * 2.0 + side * 2.0, tip + fd * 2.0 - side * 2.0, tip + fd * 2.0, tip + fd * 3.0]:
				draw_rect(Rect2(q, Vector2.ONE), arrow)


# ---------- сценки у построек ----------
const SCENES := ["tennis", "volleyball", "skatepark", "playground", "umbrella", "fountain", "icecream", "cafe", "boba", "juicebar", "pier", "surf"]
const SIT_OUTSIDE := ["cafe", "boba", "juicebar"]


func _scene_on(o: Dictionary, h: float) -> bool:
	if o.build > 0.0 or h < 8.0 or h > (21.5 if SIT_OUTSIDE.has(o.t) else 19.5):
		return false
	var d := D.def(o.t)
	return not d.has("jobs") or not workers.get(o.i, []).is_empty()


func _free_tile(x: int, y: int) -> bool:
	return in_map(x, y) and objs[y * W + x] == null and terrain[y * W + x] != WATER


func _scene_cat(k: int, i: int, outfit: String, feet: Vector2, face: int, frame := "stand", bob := 0) -> void:
	var keys: Array = D.CAT_COLORS.keys()
	var fs: Dictionary = spr.cat_set(keys[(i * 7 + k * 13) % keys.size()], outfit)
	var tx: Texture2D = fs[frame][1 if face < 0 else 0]
	var pos := Vector2(roundi(feet.x - tx.get_width() / 2.0), roundi(feet.y - tx.get_height() + bob))
	draw_rect(Rect2(pos.x + 1, feet.y - 1, tx.get_width() - 2, 1), Color(0.157, 0.118, 0.196, 0.2))
	draw_texture(tx, pos)


func _draw_scene(o: Dictionary) -> void:
	var bx := float(o.i % W * T)
	var by := float(o.i / W * T)
	var t := anim_time + hashf(o.i, 3) * 10.0
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
			draw_rect(Rect2(bx + 11, by + 19, 1, 3), Color("8a5a3b"))
			draw_rect(Rect2(bx + 20, by + 19, 1, 3), Color("8a5a3b"))
			draw_rect(Rect2(roundi(bxp), by + 26, 2, 1), Color(0.157, 0.118, 0.196, 0.25))
			draw_rect(Rect2(roundi(bxp), roundi(byp), 2, 2), Color("f2e060"))
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
			draw_rect(Rect2(roundi(bxp), roundi(byp), 2, 2), Color("fff6e0"))
			draw_rect(Rect2(roundi(bxp), roundi(byp), 1, 1), Color("ff9f43"))
		"skatepark":
			# скейтер катается по рампе туда-сюда
			var k := sin(t * 1.4)
			var px := bx + 16.0 + k * 10.0
			var py := by + 27.0 - k * k * 9.0
			var face := 1 if cos(t * 1.4) > 0.0 else -1
			_scene_cat(0, i, "casual4", Vector2(px, py - 1), face)
			draw_rect(Rect2(roundi(px) - 4, roundi(py) - 1, 8, 1), Color("3b3b4a"))
			draw_rect(Rect2(roundi(px) - 3, roundi(py), 1, 1), Color("ffd23f"))
			draw_rect(Rect2(roundi(px) + 2, roundi(py), 1, 1), Color("ffd23f"))
		"playground":
			# котёнок качается на качелях
			var pv := Vector2(bx + 9, by + 12)
			var ang := sin(t * 2.2) * 0.7
			var seat := pv + Vector2(sin(ang), cos(ang)) * 9.0
			draw_rect(Rect2(pv.x - 6, pv.y - 1, 13, 1), Color("8a5a3b"))
			draw_line(pv + Vector2(-2, 0), seat + Vector2(-2, 0), Color("6a6478"), 1.0)
			draw_line(pv + Vector2(2, 0), seat + Vector2(2, 0), Color("6a6478"), 1.0)
			_scene_cat(0, i, "casual1", seat + Vector2(0, 2), 1 if cos(t * 2.2) > 0.0 else -1)
			draw_rect(Rect2(seat.x - 3, seat.y, 6, 1), Color("e45b6b"))
		"umbrella":
			# котик загорает на полотенце
			if hour() < 9.0 or hour() > 18.0:
				return
			draw_rect(Rect2(bx + 1, by + 11, 13, 4), Color("ff8fab"))
			draw_rect(Rect2(bx + 1, by + 12, 13, 1), Color("ffffff"))
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
				draw_rect(Rect2(cx, fy - 9 - lick, 2, 3), Color("d8a060"))
				draw_rect(Rect2(cx, fy - 11 - lick, 2, 2), Color("ff9fc0") if k == 0 else Color("9ed8c8"))
		"cafe", "boba", "juicebar":
			# столик на улице: двое болтают, над чашками пар
			if not _free_tile(o.i % W, o.i / W + 1):
				return
			draw_rect(Rect2(bx + 5, by + 22, 7, 2), Color("f4ead8"))
			draw_rect(Rect2(bx + 8, by + 24, 1, 5), Color("8a5a3b"))
			draw_rect(Rect2(bx + 6, by + 20, 1, 2), Color("ffffff"))
			draw_rect(Rect2(bx + 10, by + 20, 1, 2), Color("ffffff") if o.t == "cafe" else Color("c8a8ff"))
			if o.t == "cafe":
				for k in 2:
					var st := fposmod(t * 0.8 + k * 0.5, 1.0)
					draw_rect(Rect2(bx + 6 + k * 4 + roundi(sin(st * 6.0)), by + 19 - st * 6.0, 1, 1), Color(1, 1, 1, 0.8 * (1.0 - st)))
			_scene_cat(0, i, "casual%d" % (i % 6), Vector2(bx + 1, by + 30), 1)
			_scene_cat(1, i, "casual%d" % ((i + 3) % 6), Vector2(bx + 16, by + 30), -1)
		"pier":
			# рыбак с удочкой, поплавок качается на воде
			var wd := Vector2i(0, 0)
			for dv in DIRS:
				var nx: int = o.i % W + dv.x
				var ny: int = o.i / W + dv.y
				if in_map(nx, ny) and terrain[ny * W + nx] == WATER:
					wd = dv
					break
			if wd == Vector2i(0, 0):
				return
			var feet := Vector2(bx + 8, by + 14) + Vector2(wd) * 5.0
			_scene_cat(0, i, "fisher", feet, 1 if wd.x >= 0 else -1)
			var tip := feet + Vector2(wd.x * 6 + (3 if wd.x == 0 else 0), -12)
			draw_line(feet + Vector2(0, -8), tip, Color("8a5a3b"), 1.0)
			var bob := feet + Vector2(wd) * 12.0 + Vector2(0, 2 + roundi(sin(t * 3.0)))
			draw_line(tip, bob, Color(1, 1, 1, 0.6), 1.0)
			draw_rect(Rect2(bob.x, bob.y, 2, 2), Color("e0483a"))
		"surf":
			# серфер качается на волне у берега
			var wd := Vector2i(0, 0)
			for dv in DIRS:
				var nx: int = o.i % W + dv.x
				var ny: int = o.i / W + dv.y
				if in_map(nx, ny) and terrain[ny * W + nx] == WATER:
					wd = dv
					break
			if wd == Vector2i(0, 0):
				return
			var c := Vector2(bx + 8, by + 13) + Vector2(wd) * 16.0 + Vector2(sin(t * 0.5) * 4.0, sin(t * 2.0) * 1.5)
			draw_rect(Rect2(roundi(c.x) - 5, roundi(c.y), 10, 2), Color("ffd23f"))
			draw_rect(Rect2(roundi(c.x) - 6, roundi(c.y) + 2, 12, 1), Color(1, 1, 1, 0.7))
			_scene_cat(0, i, "surfer", c, 1 if wd.x >= 0 else -1)


func on_screen(wp: Vector2) -> bool:
	var vs := view_size()
	return Rect2(cam.position - vs / 2.0, vs).has_point(wp)


## Звуки окружения: волны у берега, птицы над зеленью, сверчки ночью, гул машин.
func _update_ambience() -> void:
	var v := visible_range()
	var tot := 0.0
	var water := 0.0
	var green := 0.0
	for y in range(v[1], v[3] + 1, 2):
		for x in range(v[0], v[2] + 1, 2):
			var i := y * W + x
			tot += 1.0
			if terrain[i] == WATER:
				water += 1.0
			var o = objs[i]
			if o != null and ["palm", "wildpalm", "jacaranda", "flowers", "agave"].has(o.t):
				green += 1.0
			elif terrain[i] == MEADOW or terrain[i] == GRASS:
				green += 0.08
	tot = maxf(tot, 1.0)
	var shore_vis := 0
	for sh in shore:
		if sh[0] >= v[0] and sh[0] <= v[2] and sh[1] >= v[1] and sh[1] <= v[3]:
			shore_vis += 1
	var cars_vis := 0
	for car in cars:
		if on_screen(Vector2(car.px, car.py)):
			cars_vis += 1
	var near := 0.6 + 0.4 * (zoom - ZOOM_MIN) / float(ZOOM_MAX - ZOOM_MIN)
	var day_k := 1.0 - clampf(dark / 0.35, 0.0, 1.0)
	sound.amb.waves = clampf(shore_vis / 30.0 * 0.8 + water / tot * 0.35, 0.0, 1.0) * near
	sound.amb.birds = clampf(green / 10.0, 0.0, 1.0) * day_k * 0.8
	sound.amb.crickets = (1.0 - day_k) * clampf((tot - water) / tot * 1.6, 0.0, 1.0) * near
	sound.amb.traffic = clampf(cars_vis / 10.0, 0.0, 1.0) * near
	if jammed >= 3 and randf() < 0.08 and not ui.zen:
		sound.play("honk", randf_range(0.9, 1.15), -16.0)


func _draw_car(car: Dictionary) -> void:
	var v: Dictionary = spr.vehicle(car.kind, car.color)
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
	draw_rect(Rect2(sx + 2, sy + tx.get_height() - 1, tx.get_width() - 4, 1), Color(0.157, 0.118, 0.196, 0.2))
	draw_texture(tx, Vector2(sx, sy))
	var fur: Dictionary = D.CAT_COLORS[car.cat.color] if car.cat != null else D.CAT_COLORS[["ginger", "gray", "white", "tabby"][car.kind.length() % 4]]
	if car.get("parked", false):
		dpos = null
	if dpos != null:
		var fc := Color(fur.a)
		draw_rect(Rect2(sx + dpos.x, sy + dpos.y, 2, 2), fc)
		draw_rect(Rect2(sx + dpos.x, sy + dpos.y - 1, 1, 1), fc)
		draw_rect(Rect2(sx + dpos.x + 1, sy + dpos.y - 1, 1, 1), fc)
		draw_rect(Rect2(sx + dpos.x + (0 if flip else 1), sy + dpos.y, 1, 1), Color(fur.get("e", "2b2233")))
	if v.lights != null:
		var on := int(anim_time * 4.0) % 2
		var pts: Array = v.lights.side if car.dir == "r" or car.dir == "l" else v.lights.fb
		for k in pts.size():
			var lx: int = pts[k][0]
			var x: int = tx.get_width() - lx - 2 if flip else lx
			draw_rect(Rect2(sx + x, sy + pts[k][1], 2, 1), Color("ff4d5e") if (k + on) % 2 == 1 else Color("4d8dff"))
	if dark > 0.1 and not car.get("parked", false):
		var f: Vector2 = {"r": Vector2(8, 0), "l": Vector2(-8, 0), "d": Vector2(0, 6), "u": Vector2(0, -6)}[car.dir]
		lights.append(Vector3(car.px + f.x, car.py + f.y, 14))
	if car.cat != null and info_target != null and info_target.has("cat") and info_target.cat == car.cat:
		var bob := roundi(sin(anim_time * 5.0) * 1.5)
		draw_texture(spr.small.heart, Vector2(roundi(car.px) - 2, roundi(car.py) - 16 + bob))


func _draw_ghost() -> void:
	if not mouse_in or tool == "hand" or _pan_active:
		return
	var tx := mouse_tile.x
	var ty := mouse_tile.y
	if not in_map(tx, ty):
		return
	if tool == "bulldoze":
		var o = obj_at(tx, ty)
		if o != null:
			draw_rect(Rect2(o.i % W * T, o.i / W * T, o.w * T, o.w * T), Color(1, 0.35, 0.43, 0.4))
		else:
			draw_rect(Rect2(tx * T, ty * T, T, T), Color(1, 1, 1, 0.2))
		return
	var d := D.def(tool)
	var w := D.size_of(tool)
	var r := can_place(tool, tx, ty)
	var rad: float = d.get("radius", d.get("sradius", 0))
	if rad > 0.0:
		var cx := tx + (w - 1) / 2.0
		var cy := ty + (w - 1) / 2.0
		var col := Color(0.7, 0.78, 1, 0.18) if d.has("sradius") else Color(1, 0.75, 0.86, 0.22)
		for y in range(int(floor(cy - rad)), int(cy + rad) + 1):
			for x in range(int(floor(cx - rad)), int(cx + rad) + 1):
				if in_map(x, y) and Vector2(x - cx, y - cy).length() <= rad:
					draw_rect(Rect2(x * T, y * T, T, T), col)
	draw_rect(Rect2(tx * T, ty * T, w * T, w * T), Color(0.5, 1, 0.63, 0.35) if r.ok else Color(1, 0.35, 0.43, 0.35))
	if tool != "path" and tool != "blvd" and tool != "road" and not d.has("terra"):
		var img: Texture2D = spr.tool_texture(tool)
		draw_texture(img, Vector2(tx * T + (w * T - img.get_width()) / 2, (ty + w) * T - img.get_height()), Color(1, 1, 1, 0.7))


func _draw_particles() -> void:
	for p in parts:
		if p.type == "firefly" or p.type == "rocket" or p.type == "spark":
			continue
		var a: float = minf(1.0, p.life / p.mx * 2.0)
		var pos := Vector2(roundi(p.x), roundi(p.y))
		var m := Color(1, 1, 1, a)
		match p.type:
			"heart":
				draw_texture(spr.small.heart, pos - Vector2(2, 2), m)
			"z":
				draw_texture(spr.small.z, pos, m)
			"sparkle":
				draw_texture(spr.small.sparkle, pos - Vector2(1, 1), m)
			"coin":
				draw_texture(spr.icons.coin, pos - Vector2(4, 4), m)
			"petal":
				draw_rect(Rect2(pos, Vector2(2, 1)), Color(0.8, 0.7, 0.96, a))
			"drop":
				draw_rect(Rect2(pos, Vector2(1, 2)), Color(0.75, 0.91, 0.96, a))
			"dust":
				draw_rect(Rect2(pos, Vector2(2, 2)), Color(0.94, 0.89, 0.81, a))
			"note":
				var nc := Color(p.col)
				nc.a = a
				draw_rect(Rect2(pos.x, pos.y + 3, 2, 2), nc)
				draw_rect(Rect2(pos.x + 1, pos.y, 1, 4), nc)
				draw_rect(Rect2(pos.x + 2, pos.y, 1, 1), nc)
			"balloon":
				var bc := Color(p.col)
				bc.a = a
				draw_rect(Rect2(pos.x - 1, pos.y - 4, 3, 4), bc)
				draw_rect(Rect2(pos.x, pos.y - 5, 1, 1), bc)
				draw_rect(Rect2(pos.x, pos.y, 1, 4), Color(INK, a * 0.6))
			"confetti":
				var cc := Color(p.col)
				cc.a = a
				draw_rect(Rect2(pos, Vector2(2 if int(p.life * 8.0) % 2 == 0 else 1, 1)), cc)
			"flash":
				draw_rect(Rect2(pos.x - 1, pos.y - 1, 3, 3), Color(1, 1, 1, a))
				draw_rect(Rect2(pos.x - 3, pos.y, 7, 1), Color(1, 1, 1, a * 0.6))
				draw_rect(Rect2(pos.x, pos.y - 3, 1, 7), Color(1, 1, 1, a * 0.6))
			"smoke":
				var r: float = 2.0 + (1.0 - p.life / p.mx) * 3.0
				draw_rect(Rect2(roundi(pos.x - r), roundi(pos.y - r), roundi(r * 2), roundi(r * 2)), Color(0.91, 0.9, 0.94, a * 0.7))
			"gull":
				var up := int(p.life * 5.0 + p.ph) % 2 == 1
				var gc := Color(1, 1, 1, a)
				draw_rect(Rect2(pos.x, pos.y, 1, 1), gc)
				draw_rect(Rect2(pos.x - 1, pos.y - (1 if up else 0), 1, 1), gc)
				draw_rect(Rect2(pos.x + 1, pos.y - (1 if up else 0), 1, 1), gc)
				draw_rect(Rect2(pos.x - 2, pos.y - (2 if up else 0), 1, 1), gc)
				draw_rect(Rect2(pos.x + 2, pos.y - (2 if up else 0), 1, 1), gc)
			"bfly":
				var col := Color(p.col)
				col.a = a
				var open := int(p.life * 8.0) % 2 == 1
				draw_rect(Rect2(pos.x - (2 if open else 1), pos.y, 2 if open else 1, 2), col)
				draw_rect(Rect2(pos.x + 1, pos.y, 2 if open else 1, 2), col)
				draw_rect(Rect2(pos.x, pos.y, 1, 2), INK)
