extends RefCounted
## Сохранение города: атомарная запись через .tmp, резервная копия .bak,
## проверка файла перед загрузкой и доводка старых версий формата.

const D = preload("res://scripts/defs.gd")
const W := D.W
const H := D.H
const T := D.T
const GRASS := D.GRASS
const WATER := D.WATER
const MEADOW := D.MEADOW
## Версия формата сохранения. Старые версии доводятся до неё через UPGRADES.
const SAVE_V := 5
## Обновления формата: версия -> функция, которая поднимает сохранение на версию выше.
## Чтобы поменять формат: увеличить SAVE_V и добавить сюда переход с прежней версии.
## Сохранения старше самой ранней версии отсюда игра не читает.
const UPGRADES := {}

var world: KotoWorld
## Файл сохранения. Переменная окружения KOTO_SAVE позволяет тестам не трогать город игрока.
var SAVE_PATH: String = OS.get_environment("KOTO_SAVE") if OS.has_environment("KOTO_SAVE") else "user://kotograd_save.json"
var save_error := ""             # почему не прочиталось последнее сохранение: "broken" или "newer"
var save_notice := ""            # что случилось с сохранением при запуске — показывается на титульном экране
var save_blocked := false        # файл из более новой версии игры: не перезаписываем его
var save_aside := ""             # имя, под которым отложен испорченный файл


func _init(w) -> void:
	world = w


# =====================================================================
#  Сохранение и загрузка
# =====================================================================

## Запись через временный файл: сначала .tmp, потом прежнее сохранение становится .bak,
## а .tmp — основным файлом. Оборванная запись не портит город.
func save_game() -> bool:
	if save_blocked:
		return false
	var text := serialize()
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _write_direct(text)
	var ok := f.store_string(text)
	f.close()
	if not ok or FileAccess.get_size(tmp) <= 0:
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(SAVE_PATH):
		var bak := SAVE_PATH + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(SAVE_PATH, bak)
	if DirAccess.rename_absolute(tmp, SAVE_PATH) != OK:
		# переименование не удалось (на всякий случай для веба) — пишем по-старому, прямо в файл
		DirAccess.remove_absolute(tmp)
		return _write_direct(text)
	return true


func _write_direct(text: String) -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var ok := f.store_string(text)
	f.close()
	return ok


func serialize() -> String:
	var mains := []
	for i in W * H:
		var o = world.objs[i]
		if o != null and o.i == i:
			var m := [i, o.t, o.v, snappedf(o.build, 0.1), int(o.get("lvl", 1)), -1]
			if o.has("stock") or o.has("out"):
				var st := {}
				for g in o.get("stock", {}):
					st[g] = snappedf(o.stock[g], 0.1)
				m.append({"s": st, "o": snappedf(o.get("out", 0.0), 0.1)})
			mains.append(m)
	var cat_list := []
	for c in world.cats:
		var k: Dictionary = c.duplicate()
		k["path"] = []
		k["dest"] = null
		k["plan"] = null
		# пауза после неудачного маршрута — временная, при загрузке всё равно сбрасывается
		k["fail_until"] = 0.0
		if c.state == "drive":
			k["state"] = "in"
			k["at"] = c.dest.b if c.dest != null and c.dest.has("b") and world.objs[c.dest.b] != null else c.home
			k["car_lot"] = -1
			k["car_tile"] = -1
		k["trip"] = null
		if c.state == "ride":
			var tp = c.get("trip")
			var to: int = tp.to if tp != null and world.objs[tp.to] != null else c.home
			k["state"] = "in" if to >= 0 and world.objs[to] != null else "idle"
			k["at"] = to
		if c.state == "walk":
			k["state"] = "idle"
			k["x"] = roundf(c.x)
			k["y"] = roundf(c.y)
		cat_list.append(k)
	var data := {
		"v": SAVE_V, "seed": world.map_seed, "island": world.mapgen.island, "terrain": Array(world.terrain), "objs": mains, "coins": world.coins, "food": world.food,
		"time": world.time, "day": world.day, "cats": cat_list, "max_cats": world.max_cats, "next_id": world.next_id, "speed": world.speed,
		"used_names": world.used_names, "cam": [world.cam.position.x, world.cam.position.y, world.zoom],
		"name": world.city_name, "goals": world.goals.done.keys(), "pets": world.pets_total, "events": world.events_seen, "rides": world.transit.rides,
		"deliveries": world.deliveries, "exported": world.exported,
	}
	return JSON.stringify(data)


## Загрузка при запуске. Испорченный файл не затирается: город берётся из .bak,
## а сам файл откладывается в сторону (.broken-<время>). Файл из более новой версии игры
## не трогаем вовсе и не сохраняемся поверх него, пока игрок сам не начнёт другой город.
func load_game() -> bool:
	save_notice = ""
	save_aside = ""
	save_blocked = false
	var bak := SAVE_PATH + ".bak"
	var has_main := FileAccess.file_exists(SAVE_PATH)
	if has_main:
		if deserialize(FileAccess.get_file_as_string(SAVE_PATH)):
			return true
		if save_error == "newer":
			save_blocked = true
			save_notice = "newer"
			return false
	if not FileAccess.file_exists(bak):
		if has_main:
			save_aside = _set_aside(SAVE_PATH, "broken")
			save_notice = "broken"
		return false
	if deserialize(FileAccess.get_file_as_string(bak)):
		# основного файла нет — запись оборвалась между переименованиями, это не поломка
		if has_main:
			save_aside = _set_aside(SAVE_PATH, "broken")
			save_notice = "restored"
		return true
	if save_error == "newer":
		save_blocked = true
		save_notice = "newer"
		return false
	save_aside = _set_aside(SAVE_PATH, "broken") if has_main else _set_aside(bak, "broken")
	if has_main:
		_set_aside(bak, "broken")
	save_notice = "broken"
	return false


## Откладывает файл сохранения в сторону рядом с ним; возвращает новое имя файла.
func _set_aside(path: String, tag: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var to := "%s.%s-%s" % [path, tag, Time.get_datetime_string_from_system().replace(":", "-")]
	if DirAccess.rename_absolute(path, to) != OK:
		DirAccess.copy_absolute(path, to)
		DirAccess.remove_absolute(path)
	return to.get_file()


## Игрок сам выбрал другой город (новый или импорт): файл из более новой версии игры
## откладываем в сторону и снова сохраняемся как обычно.
func release_save() -> void:
	if save_blocked:
		save_blocked = false
		_set_aside(SAVE_PATH, "newer")
		_set_aside(SAVE_PATH + ".bak", "newer")
	save_notice = ""


## Импорт сохранения из файла (меню настроек).
func import_save(text: String) -> bool:
	if not deserialize(text):
		return false
	release_save()
	world.cars = []
	world.info_target = null
	world._render_terrain_full()
	world.refresh_terrain()
	world.rebuild_maps()
	if not world._had_goals:
		world.goals.sync_silently()
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


## Разбирает сохранение. Состояние мира меняется, только если файл целиком прошёл проверку;
## иначе save_error говорит, что не так: "broken" (испорчен) или "newer" (из новой версии игры).
func deserialize(text: String) -> bool:
	save_error = "broken"
	var json := JSON.new()  # не JSON.parse_string: тот пишет испорченный файл в журнал ошибок
	if json.parse(text) != OK:
		return false
	var d = json.data
	if typeof(d) != TYPE_DICTIONARY or not _is_num(d.get("v")):
		return false
	var v := int(d.v)
	if v > SAVE_V:
		save_error = "newer"
		return false
	while v < SAVE_V:
		if not UPGRADES.has(v):
			return false
		call(UPGRADES[v], d)
		v += 1
	if not _check_save(d):
		return false
	save_error = ""
	_apply_save(d)
	return true


static func _is_num(x) -> bool:
	return typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT


## Проверка всех полей, которые читает _apply_save, — до того, как трогать город.
func _check_save(d: Dictionary) -> bool:
	for k in ["seed", "coins", "food", "time", "day", "max_cats", "next_id", "speed"]:
		if not _is_num(d.get(k)):
			return false
	for k in ["terrain", "objs", "cats", "used_names"]:
		if typeof(d.get(k)) != TYPE_ARRAY:
			return false
	if d.has("goals") and typeof(d.goals) != TYPE_ARRAY:
		return false
	if d.has("cam") and (typeof(d.cam) != TYPE_ARRAY or d.cam.size() < 3 or not d.cam.slice(0, 3).all(_is_num)):
		return false
	for m in d.objs:
		if typeof(m) != TYPE_ARRAY or m.size() < 4 or not (_is_num(m[0]) and _is_num(m[2]) and _is_num(m[3])):
			return false
		if m.size() > 4 and not _is_num(m[4]):
			return false
	for c in d.cats:
		if typeof(c) != TYPE_DICTIONARY or typeof(c.get("name")) != TYPE_STRING or typeof(c.get("color")) != TYPE_STRING:
			return false
		if typeof(c.get("state")) != TYPE_STRING or not _is_num(c.get("x")) or not _is_num(c.get("y")) or not _is_num(c.get("home")):
			return false
	# сохранение с прежней маленькой карты: город переезжает в центр большой
	if d.terrain.size() == D.OLD_W * D.OLD_H:
		_migrate_small(d)
	if d.terrain.size() != W * H or not d.terrain.all(func(t): return _is_num(t) and t >= GRASS and t <= MEADOW):
		return false
	for m in d.objs:
		var i := int(m[0])
		if i < 0 or i >= W * H:
			return false
		if D.DEFS.has(str(m[1])):
			var w := D.size_of(str(m[1]))
			if i % W + w > W or i / W + w > H:
				return false
	for c in d.cats:
		for k in ["home", "job", "at"]:
			if c.has(k) and (not _is_num(c[k]) or int(c[k]) < -1 or int(c[k]) >= W * H):
				return false
	return true


func _apply_save(d: Dictionary) -> void:
	world.map_seed = int(d.seed)
	world.mapgen.island = str(d.get("island", "sa"))
	world.terrain = PackedByteArray(d.terrain)
	world.objs = []
	world.objs.resize(W * H)
	for m in d.objs:
		if not D.DEFS.has(str(m[1])):
			continue
		var o := world.place_obj(int(m[0]), str(m[1]), int(m[2]), float(m[3]))
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
	world.coins = float(d.coins)
	world.food = float(d.food)
	world.time = float(d.time)
	world.day = int(d.day)
	world.max_cats = int(d.max_cats)
	world.next_id = int(d.next_id)
	world.speed = int(d.speed)
	world.used_names = d.used_names
	world.city_name = str(d.get("name", "Котоград"))
	world.pets_total = int(d.get("pets", 0))
	world.events_seen = int(d.get("events", 0))
	world.deliveries = int(d.get("deliveries", 0))
	world.exported = int(d.get("exported", 0))
	world.transit.rides = int(d.get("rides", 0))
	world.transit.trains = []
	world.transit.planes = []
	world.transit.helis = []
	world._had_goals = d.has("goals")
	world.goals.done = {}
	world.goals._m_cache = {}
	for g in d.get("goals", []):
		world.goals.done[str(g)] = true
	world.events.active = null
	world.events.visitors = []
	world.cats = []
	for c in d.cats:
		for k in ["id", "home", "job", "at", "casual", "dir", "lx", "ly", "pi", "car_lot", "car_tile"]:
			c[k] = int(c.get(k, -1))
		c["near_car"] = false
		c["path"] = []
		c["dest"] = null
		c["plan"] = null
		c["fail_until"] = 0.0
		c["trip"] = null
		world.cats.append(c)
	var cm: Array = d.get("cam", [W * T / 2.0, H * T / 2.0, 3])
	world.zoom = int(cm[2])
	world._apply_zoom()
	world.cam.position = Vector2(cm[0], cm[1])
	world.recalc()
