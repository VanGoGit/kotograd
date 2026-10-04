extends Node2D
## Мир Котограда: карта, постройки, котики, машины, экономика и отрисовка.

const D = preload("res://scripts/defs.gd")
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
var _ambient_t := 0.0
var _save_t := 0.0
var _pan_active := false
var _pan_moved := false
var _pan_button := 0
var _pan_start := Vector2.ZERO
var _pan_cam := Vector2.ZERO
var _painting := false
var _last_paint := -1
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
	var loaded := load_game()
	if not loaded:
		new_game()
	_render_terrain_full()
	terrain_tex = ImageTexture.create_from_image(terrain_img)
	rebuild_maps()
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
	_gen_map(map_seed)
	zoom = 3
	_apply_zoom()
	center_cam(W / 2.0, H / 2.0)
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
			mains.append([i, o.t, o.v, snappedf(o.build, 0.1), int(o.get("lvl", 1))])
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
		if c.state == "walk":
			k["state"] = "idle"
			k["x"] = roundf(c.x)
			k["y"] = roundf(c.y)
		cat_list.append(k)
	var data := {
		"v": 5, "seed": map_seed, "terrain": Array(terrain), "objs": mains, "coins": coins, "food": food,
		"time": time, "day": day, "cats": cat_list, "max_cats": max_cats, "next_id": next_id, "speed": speed,
		"used_names": used_names, "cam": [cam.position.x, cam.position.y, zoom],
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
	save_game()
	return true


func deserialize(text: String) -> bool:
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY or int(d.get("v", 0)) != 5:
		return false
	if not d.has("terrain") or d.terrain.size() != W * H:
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
	coins = float(d.coins)
	food = float(d.food)
	time = float(d.time)
	day = int(d.day)
	max_cats = int(d.max_cats)
	next_id = int(d.next_id)
	speed = int(d.speed)
	used_names = d.used_names
	cats = []
	for c in d.cats:
		for k in ["id", "home", "job", "at", "casual", "dir", "lx", "ly", "pi", "car_lot", "car_tile"]:
			c[k] = int(c.get(k, -1))
		c["near_car"] = false
		c["path"] = []
		c["dest"] = null
		c["plan"] = null
		c["fail_until"] = 0.0
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


func _gen_map(s: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	terrain = PackedByteArray()
	terrain.resize(W * H)
	terrain.fill(WATER)
	objs = []
	objs.resize(W * H)
	var sm := s % 100000
	var cx := W / 2.0
	var cy := H / 2.0
	# маленький островок посреди океана — дальше остров расширяет сам игрок
	for y in H:
		for x in W:
			var d := pow((x + 0.5 - cx) / 12.5, 2.0) + pow((y + 0.5 - cy) / 8.5, 2.0)
			d += (hashf(x, y, sm) - 0.5) * 0.25
			if d < 1.0:
				terrain[y * W + x] = SAND if d > 0.7 else GRASS
				var hd := pow((x + 0.5 - cx - 6.0) / 3.2, 2.0) + pow((y + 0.5 - cy + 2.5) / 2.2, 2.0)
				if hd < 1.0 and d < 0.5:
					terrain[y * W + x] = HILL
	var spots := []
	for y in H:
		for x in W:
			if terrain[y * W + x] != WATER and Vector2(x + 0.5 - cx, y + 0.5 - cy).length() > 5.5:
				spots.append(Vector2i(x, y))
	spots.shuffle()
	var n := 0
	for p in spots:
		if n >= 18:
			break
		var t := "wildpalm" if n < 12 else ("agave" if n < 16 else "rock")
		if t == "rock" and terrain[p.y * W + p.x] != SAND:
			continue
		place_obj(p.y * W + p.x, t, rng.randi() % 3, 0.0)
		n += 1


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
	return o != null and o.t == "road"


## Любая проезжая часть: дорога или магистраль.
func is_drivable(x: int, y: int) -> bool:
	var o = obj_at(x, y)
	return o != null and (o.t == "road" or o.t == "highway")


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
	var ups: Array = D.def(o.t).get("up", [])
	var lvl := int(o.get("lvl", 1))
	if lvl - 1 >= ups.size():
		return -1
	return int(ups[lvl - 1])


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
	o["lvl"] = int(o.get("lvl", 1)) + 1
	var cp := center_of(b) * T + Vector2(8, 0)
	for k in 16:
		add_p({"type": "sparkle", "x": cp.x + randf_range(-12, 12), "y": cp.y + randf_range(-16, 8), "vx": randf_range(-25, 25), "vy": randf_range(-40, -10), "life": randf_range(0.7, 1.4)})
	float_text(cp + Vector2(0, -14), "%s — уровень %d!" % [D.def(o.t).name, o.lvl], Color("c08a1a"))
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
	if o != null and o.t == "road":
		return false
	return walkable_idx(i)


func bname(b: int) -> String:
	if b >= 0 and b < W * H and objs[b] != null:
		return D.def(objs[b].t).get("name", "—")
	return "—"


# =====================================================================
#  Экономика
# =====================================================================

func recalc() -> void:
	var st := {
		"cap": 0, "jobs": 0, "houses": [], "workplaces": [], "leisure": [], "strolls": [], "vehicle_bases": [],
		"constructing": [], "builder_yards": [], "house_happy": {}, "food_prod": stats.get("food_prod", 0.0), "wonders": [], "lots": [], "tourists": [],
		"coin_cap": 3000.0, "food_cap": 150.0,
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
		if _next_to(h, "path"):
			v += 5.0
		st.house_happy[h] = minf(100.0, v)
	stats = st


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
		ui.toast("%s нашёл новый дом!" % c.name)


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
		if d.has("food"):
			fp += float(stat(o, "food")) + float(stat(o, "food_per", 0.0)) * nw
		if d.has("shop") and nw > 0:
			shop_income += float(stat(o, "shop")) * (0.6 + 0.4 * nw / float(stat(o, "jobs")))
	stats.food_prod = fp
	eat_rate = n * 0.04
	food = clampf(food + (fp - eat_rate) * dt, 0.0, maxf(stats.food_cap, food))
	hungry = food <= 0.01 and eat_rate > fp
	pet_bonus = maxf(0.0, pet_bonus - dt * 0.05)
	happy = town_happiness()
	var mult := (0.5 + happy / 100.0) * 0.75
	income = (employed * 0.35 + (n - employed) * 0.08 + shop_income + tourism) * mult
	if coins < stats.coin_cap:
		coins = minf(stats.coin_cap, coins + income * dt)
	if n < stats.cap and happy >= 20.0:
		spawn_t += dt * (0.4 + happy / 100.0)
		if spawn_t >= 11.0:
			spawn_t = 0.0
			spawn_cat()


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
			float_text(p + Vector2(0, -18), "%s: %s!" % [c.name, D.PROFESSIONS[D.def(objs[best].t).job].to_lower()], Color("5b6bb0"))


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
	ui.toast("%s переезжает в Котоград!" % c.name)
	sound.play("mew", randf_range(0.9, 1.25))
	var opened := []
	for t in D.DEFS:
		var u := int(D.DEFS[t].get("unlock", 0))
		if u > prev and u <= max_cats:
			opened.append(D.DEFS[t].name)
	if opened.size() > 0:
		ui.toast("Открыто: %s!" % ", ".join(opened), true)
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
		return D.PROFESSIONS.get(D.def(objs[c.job].t).get("job", ""), "")
	return "Ищет работу"


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
		return {"kind": "rest"} if homeless else {"kind": "home", "b": c.home}
	if c.job >= 0 and is_ready(c.job) and h >= c.work_at and h < c.off:
		return {"kind": "work", "b": c.job}
	var pl = c.plan
	if pl != null and ah < pl.until and pl.until - ah < 2.0 and (not pl.has("b") or is_ready(pl.b)):
		return pl
	var p = null
	var r := randf()
	if r < 0.35:
		var l := _pick_leisure(c)
		if l >= 0:
			p = {"kind": "visit", "b": l}
	elif r < 0.6:
		var s = _pick_stroll(c)
		if s != null:
			p = {"kind": "stroll", "tx": s.x, "ty": s.y, "sb": s.b}
	elif r < 0.8 and not homeless:
		p = {"kind": "home", "b": c.home}
	if p == null:
		p = {"kind": "wander"}
	p["until"] = ah + randf_range(0.6, 1.6)
	c.plan = p
	return p


# --- поиск пути ---

func _tile_cost(i: int) -> float:
	var o = objs[i]
	if o != null:
		if o.t == "path":
			return 1.0
		if o.t == "road":
			# по проезжей части котики не гуляют — только переходят её поперёк
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


## Путь по дорогам (поиск в ширину).
func road_route(starts: Array, goals: Dictionary):
	if starts.is_empty() or goals.is_empty():
		return null
	var prev := PackedInt32Array()
	prev.resize(W * H)
	prev.fill(-2)
	var q := []
	for s in starts:
		prev[s] = -1
		q.append(s)
	var head := 0
	while head < q.size():
		var u: int = q[head]
		head += 1
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
		for dv in DIRS:
			var nx: int = ux + dv.x
			var ny: int = uy + dv.y
			if not is_drivable(nx, ny):
				continue
			var n := ny * W + nx
			if prev[n] != -2:
				continue
			prev[n] = u
			q.append(n)
	return null


func roads_around(b: int) -> Array:
	var out := []
	for p in around(b):
		if is_road(p.x, p.y):
			out.append(p.y * W + p.x)
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
		return false
	var lot := -1
	if d.kind != "home":
		lot = _find_lot(d.b)
	var goal := _to_set(roads_around(lot if lot >= 0 else d.b))
	var route = road_route(starts, goal)
	if route == null and lot >= 0:
		lot = -1
		route = road_route(starts, _to_set(roads_around(d.b)))
	if route == null or route.size() < 2:
		return false
	c.car_tile = -1
	c.car_lot = -1
	c.near_car = false
	c.state = "drive"
	c.at = -1
	c.dest = d
	var car := _make_car("car", c.car, route, c, d.b, -1)
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
	if can_car and not _car_at_home(c) and _try_drive(c, d):
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
		if is_night():
			c.state = "sleep"
			c.timer = randf_range(10, 20)
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
		if ob != null and ob.t == "path":
			w *= 4.0
		if ob != null and ob.t == "road":
			w *= 0.6
		if c.lx == o.x and c.ly == o.y:
			w *= 0.25
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
	if d != null and (d.kind == "home" or d.kind == "work" or d.kind == "visit"):
		if is_ready(d.b) and (d.kind != "home" or c.home == d.b):
			_enter(c, d.b)
			return
	var o = obj_at(roundi(c.x), roundi(c.y))
	c.state = "idle"
	if o != null and o.t == "cushion" and randf() < 0.6:
		c.state = "sleep"
		c.timer = randf_range(8, 16)
		return
	if o != null and o.t == "bench" and randf() < 0.6:
		c.timer = randf_range(4, 9)
		return
	c.timer = randf_range(1.2, 3.5) if randf() < 0.22 else 0.0


func _update_cat(c: Dictionary, dt: float) -> void:
	c.anim += dt
	if c.pet > 0.0:
		c.pet -= dt
	match c.state:
		"drive":
			return
		"in":
			if objs[c.at] == null:
				c.state = "idle"
				c.timer = 0.2
				c.at = -1
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
			var dx: float = tgt.x - c.x
			var dy: float = tgt.y - c.y
			var dist := sqrt(dx * dx + dy * dy)
			var o = obj_at(tgt.x, tgt.y)
			var sp := dt * (1.7 if o != null and o.t == "path" else (1.4 if o != null and o.t == "road" else 1.1))
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
	float_text(p + Vector2(0, -16), "мрр... zZ" if c.state == "sleep" else ["Мурр!", "Мяу!", "Мрр~"].pick_random(), Color("ff6b8b"))
	sound.play("mew", randf_range(0.95, 1.3))
	pet_bonus = minf(10.0, pet_bonus + 1.5)
	if c.state == "idle":
		c.timer = maxf(c.timer, 1.5)


func cat_pos(c: Dictionary) -> Vector2:
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
				return "домой"
			"work":
				return "на работу"
			"visit":
				return "в «%s»" % bname(dd.b)
		return "гулять"
	match c.state:
		"drive":
			return "едет %s на машине" % where.call(d)
		"walk":
			return "идёт %s" % where.call(d) if d != null and d.kind != "wander" else "гуляет"
		"in":
			if c.at == c.home:
				return "спит дома" if is_night() else "отдыхает дома"
			if c.at == c.job:
				return "работает"
			return "в «%s»" % bname(c.at)
		"sleep":
			return "дремлет под открытым небом" if c.home < 0 else "дремлет"
	return "ждёт новый дом" if c.home < 0 else "отдыхает на улице"


# =====================================================================
#  Машины
# =====================================================================

const LANE := {"r": Vector2(0, 3), "l": Vector2(0, -3), "d": Vector2(-3, 0), "u": Vector2(3, 0)}
const DIR_VEC := {"r": Vector2(1, 0), "l": Vector2(-1, 0), "d": Vector2(0, 1), "u": Vector2(0, -1)}


## Впереди машина в том же направлении (стоим) или припаркованная на дороге (объезжаем медленно)?
func _traffic(car: Dictionary) -> int:
	var fwd_v: Vector2 = DIR_VEC[car.dir]
	var me := Vector2(car.bx, car.by)
	var hw: bool = car.get("hw", false)
	for o in cars:
		if is_same(o, car) or o.dir != car.dir:
			continue
		# на магистрали мешает только машина в своей полосе
		if hw and o.get("hw", false) and o.get("lane", 0) != car.get("lane", 0):
			continue
		var rel := Vector2(o.bx, o.by) - me
		var fwd := rel.dot(fwd_v)
		var side := absf(rel.dot(Vector2(fwd_v.y, fwd_v.x)))
		if fwd > 0.5 and fwd < 12.0 and side < 4.0:
			if hw and _lane_free(car, 1 - int(car.get("lane", 0))):
				car["lane"] = 1 - int(car.get("lane", 0))
				return 0
			return 2
	for c in street_parked:
		var pp := Vector2(c.car_tile % W * T + 8.0, c.car_tile / W * T + 8.0)
		var rel := pp - me
		var fwd := rel.dot(fwd_v)
		var side := absf(rel.dot(Vector2(fwd_v.y, fwd_v.x)))
		if fwd > -8.0 and fwd < 14.0 and side < 4.0:
			return 1
	return 0


## Свободна ли соседняя полоса магистрали для обгона.
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


func _make_car(kind: String, color: String, route: Array, cat, target: int, return_to: int) -> Dictionary:
	var car := {"kind": kind, "color": color, "route": route, "k": 0, "prog": 0.0, "cat": cat, "target": target,
		"return_to": return_to, "px": 0.0, "py": 0.0, "bx": 0.0, "by": 0.0, "dir": "r", "speed": 3.0 if kind == "car" else 2.6,
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
	car.px = car.bx + off.x
	car.py = car.by + off.y


func _update_cars(dt: float) -> void:
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
		var tr := _traffic(car)
		car["passing"] = tr == 1
		if tr == 2 and car.get("wait", 0.0) < 6.0:
			car["wait"] = car.get("wait", 0.0) + dt
			if car.wait > 1.5 and randf() < dt * 0.25:
				float_text(Vector2(car.px, car.py - 10), "Би-бип!", Color("6a6478"))
			_car_pos(car)
			continue
		car["wait"] = 0.0
		car.prog += car.speed * dt * (0.3 if tr == 1 else (1.9 if car.get("hw", false) else 1.0))
		while car.prog >= 1.0 and car.k < route.size() - 1:
			car.prog -= 1.0
			car.k += 1
		if car.k >= route.size() - 1:
			car.k = route.size() - 1
			car.prog = 0.0
			if car.return_to >= 0 and is_ready(car.return_to):
				var e: Vector2i = route[route.size() - 1]
				var back = road_route([e.y * W + e.x], _to_set(roads_around(car.return_to)))
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
				_enter(c, car.target)
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
		return {"ok": false, "reason": "Пока закрыто"}
	if d.has("terra"):
		var i := y * W + x
		var o = objs[i]
		if terrain[i] == d.terra:
			return {"ok": false}
		if o != null and o.t != "road" and o.t != "path":
			return {"ok": false, "reason": "Сначала уберите постройку"}
		return {"ok": true, "cost": 0}
	if d.get("wonder", false) and wonder_built(t):
		return {"ok": false, "reason": "Это чудо уже есть в городе"}
	var w := D.size_of(t)
	var water := 0
	var cost: int = d.cost
	for yy in range(y, y + w):
		for xx in range(x, x + w):
			if not in_map(xx, yy):
				return {"ok": false, "reason": "Не помещается"}
			var i := yy * W + xx
			if objs[i] != null:
				return {"ok": false, "reason": "Здесь занято"}
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
		return {"ok": false, "reason": "Строится только на холмах и в горах"}
	if mount > 0 and not (d.has("cap") or t in ["road", "highway", "path", "parking"] or (d.has("happy") and not d.has("jobs")) or d.get("wonder", false)):
		return {"ok": false, "reason": "Слишком круто: в горах — только жильё и дороги"}
	if water > 0:
		if t == "road":
			cost = 8
		elif t == "highway":
			cost = 14
		elif t == "path":
			cost = 6
		else:
			return {"ok": false, "reason": "Нельзя на воде"}
	if d.get("need_water", false):
		var near := false
		for dv in DIRS:
			if in_map(x + dv.x, y + dv.y) and terrain[(y + dv.y) * W + x + dv.x] == WATER:
				near = true
		if not near:
			return {"ok": false, "reason": "Нужна вода рядом"}
	if unlimited:
		cost = 0
	if coins < cost:
		return {"ok": false, "reason": "Не хватает монеток", "cost": cost}
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
				float_text(Vector2(x * T + 8, y * T), "Нужно 2 монетки", Color("c24a5a"))
			return
		coins -= 2.0
	else:
		var on_water: bool = terrain[o.i] == WATER
		var refund: int = 3 if (o.t == "road" or o.t == "path") and on_water else int(d.cost / 2)
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
			ui.toast("%s остался без дома и ждёт новый" % c.name)
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
			float_text(cp + Vector2(0, -10), "%s — готово!" % D.def(o.t).name, Color("4f8a4f"))
			sound.play("pop")
			if D.def(o.t).get("wonder", false):
				ui.toast("Чудо света построено: %s! Туристы уже едут." % D.def(o.t).name, true)
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
			parts.remove_at(k)
			k -= 1
			continue
		if p.has("g"):
			p.vy += p.g * dt
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
		ui.toast("Доброе утро! Начинается день %d" % day)
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
		if car.get("wait", 0.0) > 1.0 or car.get("passing", false):
			jammed += 1
	_spawn_service_vehicles(gdt)


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
		if c.state == "in" or c.state == "drive":
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
			KEY_SPACE:
				cycle_speed()
			_:
				if k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9:
					ui.select_tab_tool(k.physical_keycode - KEY_1)
		get_viewport().set_input_as_handled()


func _update_cursor() -> void:
	var shape := Input.CURSOR_CROSS
	if tool == "hand":
		shape = Input.CURSOR_DRAG if _pan_moved else Input.CURSOR_ARROW
		var o = obj_at(mouse_tile.x, mouse_tile.y)
		if cat_at(get_global_mouse_position()) != null or (o != null and o.t != "path" and o.t != "road"):
			shape = Input.CURSOR_POINTING_HAND
	Input.set_default_cursor_shape(shape)


func _click(wp: Vector2) -> void:
	var c = cat_at(wp)
	if c != null:
		pet_cat(c)
		info_target = {"cat": c}
		return
	var o = obj_at(mouse_tile.x, mouse_tile.y)
	if o != null and o.t != "path" and o.t != "road":
		info_target = {"tile": o.i}
	else:
		info_target = null


func select_tool(t: String) -> void:
	var d := D.def(t)
	if not d.is_empty() and not unlimited and max_cats < d.get("unlock", 0):
		ui.toast("«%s» откроется, когда в городе будет %d котиков" % [d.name, d.unlock])
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
	for y in range(y0 - 1, y0 + w + 1):
		for x in range(x0 - 1, x0 + w + 1):
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
	if horiz or not vert:
		_r(px, py, 0, 7, 16, 1, "ffd23f"); _r(px, py, 0, 8, 16, 1, "ffd23f")
		_r(px, py, 1, 4, 5, 1, "ffffff"); _r(px, py, 9, 4, 5, 1, "ffffff")
		_r(px, py, 1, 11, 5, 1, "ffffff"); _r(px, py, 9, 11, 5, 1, "ffffff")
		_r(px, py, 0, 0, 16, 1, "c9c4d6" if not water else "c08f5f"); _r(px, py, 0, 15, 16, 1, "c9c4d6" if not water else "c08f5f")
	else:
		_r(px, py, 7, 0, 1, 16, "ffd23f"); _r(px, py, 8, 0, 1, 16, "ffd23f")
		_r(px, py, 4, 1, 1, 5, "ffffff"); _r(px, py, 4, 9, 1, 5, "ffffff")
		_r(px, py, 11, 1, 1, 5, "ffffff"); _r(px, py, 11, 9, 1, 5, "ffffff")
		_r(px, py, 0, 0, 1, 16, "c9c4d6" if not water else "c08f5f"); _r(px, py, 15, 0, 1, 16, "c9c4d6" if not water else "c08f5f")


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


func _path_conn(x: int, y: int) -> bool:
	var n = obj_at(x, y)
	if n == null:
		return false
	if n.t == "path" or n.t == "road":
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
			if o != null and o.i == i and o.t != "path" and o.t != "road":
				list.append([(y + o.w) * T, 0, o, x, y])
	for c in cats:
		if c.state == "in" or c.state == "drive":
			continue
		if c.x < v[0] - 1 or c.x > v[2] + 1 or c.y < v[1] - 1 or c.y > v[3] + 1:
			continue
		list.append([c.y * T + 14.0, 1, c])
	for car in cars:
		list.append([car.py + 4.0, 2, car])
	for c in street_parked:
		var tx: int = c.car_tile % W
		var ty: int = c.car_tile / W
		if tx < v[0] or tx > v[2] or ty < v[1] or ty > v[3]:
			continue
		var off: Vector2 = LANE.get(c.car_dir, Vector2.ZERO)
		var pc := {"kind": "car", "color": c.car, "px": tx * T + 8.0 + off.x, "py": ty * T + 8.0 + off.y, "dir": c.car_dir, "cat": null, "parked": true}
		list.append([pc.py + 4.0, 2, pc])
	list.sort_custom(func(a, b): return a[0] < b[0])

	for it in list:
		match it[1]:
			0:
				_draw_obj(it[2], it[3], it[4], h)
			1:
				_draw_cat(it[2])
			2:
				_draw_car(it[2])

	_draw_ghost()
	_draw_particles()


func _draw_obj(o: Dictionary, x: int, y: int, h: float) -> void:
	if o.build > 0.0:
		_draw_construction(o, x, y)
		return
	var tx: Texture2D = spr.obj_texture(o)
	if tx == null:
		return
	var sx: int = x * T + (o.w * T - tx.get_width()) / 2
	var sy: int = (y + o.w) * T - tx.get_height()
	draw_texture(tx, Vector2(sx, sy))
	if o.t == "parking" or o.t == "garage":
		var slots: Array = spr.PARKING_SLOTS if o.t == "parking" else spr.GARAGE_SLOTS
		var cols: Array = lot_colors.get(o.i, [])
		for k in mini(cols.size(), slots.size()):
			var sl: Vector2i = slots[k]
			var big: bool = o.t == "parking"
			draw_rect(Rect2(sx + sl.x, sy + sl.y, 5 if big else 4, 3 if big else 2), Color(cols[k]))
			draw_rect(Rect2(sx + sl.x + 1, sy + sl.y, 2, 1), Color("bfe6f7"))
	var wins: Array = spr.windows_for(o)
	if wins.size() > 0 and dark > 0.08:
		var d := D.def(o.t)
		var lit: bool
		if o.t == "lantern":
			lit = true
		elif d.get("leisure", false) or d.get("wonder", false):
			lit = (h >= 17.0 and h < 23.5) or inside_count.get(o.i, 0) > 0
		else:
			lit = inside_count.get(o.i, 0) > 0
		if lit:
			# горят не все окна — у каждого здания свой рисунок света
			var few: bool = wins.size() <= 2 or o.t == "lantern"
			for k in wins.size():
				if not few and hashf(o.i, k, 77) > 0.6:
					continue
				var wr: Rect2i = wins[k]
				var glow := Color("ffd36e") if hashf(o.i, k, 78) < 0.7 else Color("ffe9a8")
				draw_rect(Rect2(sx + wr.position.x, sy + wr.position.y, wr.size.x, wr.size.y), glow)
			var r := 48.0 if o.t == "lantern" else (34.0 if o.w == 2 else 18.0)
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
	if tool != "path" and tool != "road" and not d.has("terra"):
		var img: Texture2D = spr.tool_texture(tool)
		draw_texture(img, Vector2(tx * T + (w * T - img.get_width()) / 2, (ty + w) * T - img.get_height()), Color(1, 1, 1, 0.7))


func _draw_particles() -> void:
	for p in parts:
		if p.type == "firefly":
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
