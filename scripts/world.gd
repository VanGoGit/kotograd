class_name KotoWorld
extends Node2D
## Мир Котограда: карта, постройки, котики, машины, экономика и отрисовка.

const D = preload("res://scripts/defs.gd")
const Goals = preload("res://scripts/goals.gd")
const Events = preload("res://scripts/events.gd")
const Transit = preload("res://scripts/transit.gd")
const Boats = preload("res://scripts/boats.gd")
const Saves = preload("res://scripts/saves.gd")
const Mapgen = preload("res://scripts/mapgen.gd")
const Economy = preload("res://scripts/economy.gd")
const Ground = preload("res://scripts/ground.gd")
const Drawer = preload("res://scripts/drawer.gd")
const Paths = preload("res://scripts/paths.gd")
const CatsAI = preload("res://scripts/cats.gd")
const I18n = preload("res://scripts/i18n.gd")
const W := D.W
const H := D.H
const T := D.T
const GRASS := D.GRASS
const WATER := D.WATER
const HILL := D.HILL
const MOUNTAIN := D.MOUNTAIN
const MEADOW := D.MEADOW
const DAY_LEN := D.DAY_LEN
# массив своим литералом: константа-массив из другого скрипта (D.DIRS) в горячих циклах в 5 раз медленнее
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const ZOOM_MIN := 1
const ZOOM_MAX := 6

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
var saves = Saves.new(self)
var mapgen = Mapgen.new(self)
var economy = Economy.new(self)
var ground = Ground.new(self)
var drawer = Drawer.new(self)
var paths = Paths.new(self)
var cats_ai = CatsAI.new(self)
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
var tool := "hand"
var terrain_img: Image
var terrain_tex: Array = []     # земля кусками по 16×16 клеток: при стройке обновляем только свой кусок
const CHUNK := 16
const CW := (W + CHUNK - 1) / CHUNK
var dirty_tiles := {}
## Растёт при любой стройке и сносе — по нему отрисовка понимает, что кэш построек устарел.
var objs_version := 0
var cars: Array = []
var parts: Array = []
var floats: Array = []
var info_target = null
var anim_time := 0.0
var dark := 0.0
var zoom := 3

var _job_t := 0.0
var _service_t := 0.0
var _ambient_t := 0.0
var _save_t := 0.0
var _maps_t := 0.0
var _econ_dt := 0.0
var wind := 0.0                  # лёгкий бриз: -1…1 (влево/вправо), 0 — штиль
var _wind_to := 0.0
var _wind_t := 8.0
var mobile := false              # телефон или планшет в браузере: 30 кадров и реже тяжёлые расчёты
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
	# телефон в браузере: 30 кадров в секунду хватает для уютной игры и бережёт батарею
	mobile = OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")
	if mobile:
		Engine.max_fps = 30
	goals = Goals.new(self)
	events = Events.new(self)
	transit = Transit.new(self)
	boats = Boats.new(self)
	var loaded := saves.load_game()
	if not loaded:
		new_game()
	ground._render_terrain_full()
	ground.refresh_terrain()
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
	goals._m_cache = {}
	events.active = null
	events.visitors = []
	events.cool = 4.0
	transit.trains = []
	transit.planes = []
	transit.helis = []
	transit.rides = 0
	mapgen._gen_map(map_seed)
	zoom = 3
	_apply_zoom()
	var st := mapgen.start_spot()
	center_cam(st.x, st.y)
	recalc()
	rebuild_maps()
	if not terrain_tex.is_empty():
		ground._render_terrain_full()
		ground.refresh_terrain()


# =====================================================================
#  Генерация карты
# =====================================================================

static func hashf(x: int, y: int, s: int = 0) -> float:
	var h: int = (x * 374761393 + y * 668265263 + s * 982451653) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h) / 4294967296.0


# рамка острова на карте (в клетках)


const ISLANDS := [
	["sa", "Сан-Андреас", "Большой остров: горы на севере, пустыня, озеро и солнечный Лос-Сантос на юге."],
	["bay", "Бухта Мурлибу", "Широкая бухта с длинными пляжами, холмы вдоль берега и маленький остров вдали."],
	["isles", "Острова Каталины", "Уютный остров с холмом посередине и бухточками, а рядом ещё три островка."],
]


# =====================================================================
#  Объекты на карте
# =====================================================================

static func in_map(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func obj_at(x: int, y: int):
	return objs[y * W + x] if in_map(x, y) else null


func place_obj(i: int, t: String, v: int, build: float) -> Dictionary:
	objs_version += 1
	var w := D.size_of(t)
	var o := {"t": t, "v": v, "i": i, "w": w, "build": build, "lvl": 1}
	var x0 := i % W
	var y0 := i / W
	for y in range(y0, y0 + w):
		for x in range(x0, x0 + w):
			objs[y * W + x] = o
	ground.mark_dirty(x0, y0, w)
	return o


func remove_obj(o: Dictionary) -> void:
	objs_version += 1
	var x0: int = o.i % W
	var y0: int = o.i / W
	for y in range(y0, y0 + o.w):
		for x in range(x0, x0 + o.w):
			objs[y * W + x] = null
	ground.mark_dirty(x0, y0, o.w)


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
		ground.mark_dirty(mate % W, mate / W, 1)
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
	objs_version += 1
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
		for g in economy.needs_of(o.t):
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
		cats_ai._validate_car(c)
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
		var fh := cats_ai.free_houses()
		if fh.is_empty():
			return
		var cp := Vector2(c.x, c.y)
		fh.sort_custom(func(a, b): return center_of(a).distance_to(cp) < center_of(b).distance_to(cp))
		c.home = fh[0]
		rebuild_maps()
		hearts_at(cats_ai.cat_pos(c) + Vector2(0, -12), 3)
		ui.toast(tr("%s нашёл новый дом!") % I18n.cat(c.name), false, true)


# =====================================================================
#  Производственные цепочки и грузовики
# =====================================================================


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
			var p := cats_ai.cat_pos(c)
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


# --- поиск пути ---


# --- поведение ---


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
	var nr = paths.road_route([cur.y * W + cur.x], {e.y * W + e.x: true}, {nxt.y * W + nxt.x: true})
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
				economy._deliver(car)
			if car.return_to >= 0 and is_ready(car.return_to):
				var e: Vector2i = route[route.size() - 1]
				var back = paths.road_route([e.y * W + e.x], cats_ai._to_set(paths.access_roads(car.return_to)))
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
				if paths.roads_around(car.target).has(end.y * W + end.x):
					cats_ai._enter(c, car.target)
				else:
					# машина уехала в гараж, а котик идёт от дороги до двери
					cats_ai._go_to(c, d, false)
		"lot":
			if is_ready(car.lot):
				c.car_lot = car.lot
				var door = cats_ai._door_of(car.lot)
				if door != null:
					c.x = float(door.x)
					c.y = float(door.y)
			else:
				c.car_tile = end.y * W + end.x
				c.car_dir = car.dir
			cats_ai._go_to(c, d, false)
		"street":
			# парковки рядом нет — машина остаётся прямо на дороге
			c.car_tile = end.y * W + end.x
			c.car_dir = car.dir
			cats_ai._go_to(c, d, false)
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
	var starts := paths.roads_around(b)
	if starts.is_empty():
		return
	var seen := cats_ai._to_set(starts)
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
	var route = paths.road_route(starts, {far.pick_random(): true})
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
	ground.mark_dirty(x, y, 1)
	ground.compute_shore()
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
	var w := D.size_of(tool)
	# большое здание — тёплое арпеджио, мелочь — привычный «поп»
	sound.play("build" if w >= 2 else "pop", 1.0, -6.0 if w >= 2 else -4.0)
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
	_update_wind(dt)
	dark = darkness(hour())
	if not dirty_tiles.is_empty():
		var chunks := {}
		for key in dirty_tiles:
			ground._draw_tile(key % W, key / W)
			chunks[(key / W) / CHUNK * CW + (key % W) / CHUNK] = true
		dirty_tiles.clear()
		ground.refresh_terrain(chunks.keys())
	_goal_t += dt
	if _goal_t > 3.0:
		_goal_t = 0.0
		var got: Array = goals.check()
		if not got.is_empty():
			ui.goals_done(got)
	_amb_t += dt
	if _amb_t > 0.5:
		_amb_t = 0.0
		_update_ambience()
	_save_t += dt
	if _save_t > (30.0 if OS.has_feature("web") else 10.0):
		_save_t = 0.0
		saves.save_game()
	queue_redraw()


## Вкладку свернули или закрыли — сохраняемся сразу (в браузере автосохранение редкое).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if not terrain_tex.is_empty() and OS.get_environment("KOTO_TEST") == "":
			saves.save_game()


func _step(gdt: float) -> void:
	var was_night := is_night()
	time += gdt / DAY_LEN
	if time >= 1.0:
		time -= 1.0
		day += 1
		ui.toast(tr("Доброе утро! Начинается день %d") % day, false, true)
	if was_night != is_night():
		sound.night = is_night()
	# карты жильцов и работников и экономику пересчитываем 4 раза в секунду, а не каждый кадр
	_maps_t -= gdt
	_econ_dt += gdt
	_job_t -= gdt
	if _maps_t <= 0.0 or _job_t <= 0.0:
		_maps_t = 0.25
		rebuild_maps()
		economy._update_economy(_econ_dt)
		_econ_dt = 0.0
	if _job_t <= 0.0:
		_job_t = 1.0
		_assign_homes()
		_assign_jobs()
	_update_construction(gdt)
	for c in cats:
		cats_ai._update_cat(c, gdt)
	_update_cars(gdt)
	jammed = 0
	for car in cars:
		if car.get("wait", 0.0) > 4.0 or car.get("passing", false):
			jammed += 1
	_spawn_service_vehicles(gdt)
	economy._update_freight(gdt)
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
		cats_ai.pet_cat(c)
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


var shore: Array = []


# =====================================================================
#  Отрисовка мира
# =====================================================================


## Бриз сам меняется: то слабый ветерок в одну сторону, то в другую, то штиль.
func _update_wind(dt: float) -> void:
	_wind_t -= dt
	if _wind_t <= 0.0:
		_wind_t = randf_range(20.0, 60.0)
		_wind_to = 0.0 if randf() < 0.3 else randf_range(0.4, 1.0) * (1.0 if randf() < 0.5 else -1.0)
	wind = move_toward(wind, _wind_to, dt * 0.08)


# ---------- сценки у построек ----------


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


func _draw() -> void:
	drawer.draw_world()
