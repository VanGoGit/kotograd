extends RefCounted
## Цели и достижения: мягкие задания, которые ведут игрока от первого домика до всех чудес света.

const D = preload("res://scripts/defs.gd")

# m — показатель города (см. metrics), n — сколько нужно, r — награда в монетках
const QUESTS := [
	{"id": "home", "name": "Первый домик", "desc": "Постройте Домик во вкладке «Жильё»", "m": "houses", "n": 1, "r": 50},
	{"id": "cat", "name": "Новосёлы", "desc": "Дождитесь первого жителя", "m": "cats", "n": 1, "r": 50},
	{"id": "road", "name": "Дорога домой", "desc": "Проложите 10 клеток дороги", "m": "roads", "n": 10, "r": 80},
	{"id": "food", "name": "Рыбный день", "desc": "Еды должно производиться больше, чем съедается: поставьте причал или ферму", "m": "food_ok", "n": 1, "r": 100},
	{"id": "work", "name": "Первая смена", "desc": "Устройте на работу 5 котиков", "m": "employed", "n": 5, "r": 120},
	{"id": "cats10", "name": "Дружная улица", "desc": "Поселите 10 котиков", "m": "cats", "n": 10, "r": 150},
	{"id": "shops", "name": "Шопинг", "desc": "Откройте 3 магазина или кафе", "m": "shops", "n": 3, "r": 150},
	{"id": "decor", "name": "Зелёный район", "desc": "Поставьте 10 украшений: пальмы, клумбы, скамейки, фонтаны…", "m": "decor", "n": 10, "r": 150},
	{"id": "parking", "name": "Где припарковаться?", "desc": "Постройте парковку или паркинг", "m": "lots", "n": 1, "r": 100},
	{"id": "services", "name": "Городские службы", "desc": "Постройте 2 городские службы: школу, больницу, полицию…", "m": "services", "n": 2, "r": 200},
	{"id": "happy", "name": "Счастливый город", "desc": "Поднимите счастье города до 65%", "m": "happy", "n": 65, "r": 250},
	{"id": "cats30", "name": "Городок", "desc": "Поселите 30 котиков", "m": "cats", "n": 30, "r": 300},
	{"id": "lvl2", "name": "Капремонт", "desc": "Улучшите любое здание: нажмите на него и выберите «Улучшить»", "m": "lvl2", "n": 1, "r": 200},
	{"id": "hill", "name": "Дом с видом", "desc": "Постройте жильё на холме или в горах", "m": "hill_home", "n": 1, "r": 200},
	{"id": "jobs", "name": "Деловой квартал", "desc": "Создайте 60 рабочих мест", "m": "jobs", "n": 60, "r": 400},
	{"id": "highway", "name": "Фривей", "desc": "Проложите 15 клеток магистрали", "m": "highway", "n": 15, "r": 300},
	{"id": "wonder", "name": "Чудо света", "desc": "Постройте первое чудо из вкладки «Чудеса»", "m": "wonders", "n": 1, "r": 500},
	{"id": "cats60", "name": "Настоящий город", "desc": "Поселите 60 котиков", "m": "cats", "n": 60, "r": 600},
	{"id": "lvl3", "name": "Шедевр архитектуры", "desc": "Улучшите здание до 3 уровня", "m": "lvl3", "n": 1, "r": 400},
	{"id": "tourism", "name": "Туристическая мекка", "desc": "Привлеките туристов: доход от туризма 10 в секунду", "m": "tourism", "n": 10, "r": 800},
	{"id": "cats100", "name": "Мегаполис", "desc": "Поселите 100 котиков", "m": "cats", "n": 100, "r": 1000},
	{"id": "legend", "name": "Город-легенда", "desc": "Постройте все 11 чудес света", "m": "wonders", "n": 11, "r": 2000},
]
const ACHIEVEMENTS := [
	{"id": "pet10", "name": "Мур-мур", "desc": "Погладьте 10 котиков", "m": "pets", "n": 10},
	{"id": "pet100", "name": "Главный по почесушкам", "desc": "Погладьте 100 котиков", "m": "pets", "n": 100},
	{"id": "week", "name": "Неделя у океана", "desc": "Проживите в городе 7 дней", "m": "day", "n": 7},
	{"id": "month", "name": "Старожил", "desc": "Проживите в городе 30 дней", "m": "day", "n": 30},
	{"id": "land", "name": "Архипелаг", "desc": "Расширьте сушу до 700 клеток", "m": "land", "n": 700},
	{"id": "jam", "name": "Пробка на 405-й", "desc": "Соберите настоящую пробку из 6 машин", "m": "jam", "n": 6},
	{"id": "rich", "name": "Котокапиталист", "desc": "Накопите 10 000 монеток", "m": "coins", "n": 10000},
	{"id": "kinds25", "name": "Всего понемногу", "desc": "Постройте 25 разных видов зданий", "m": "kinds", "n": 25},
	{"id": "kinds60", "name": "Город всего на свете", "desc": "Постройте 60 разных видов зданий", "m": "kinds", "n": 60},
	{"id": "event1", "name": "Праздник!", "desc": "Проведите первое городское событие", "m": "events", "n": 1},
	{"id": "event10", "name": "Душа компании", "desc": "Проведите 10 городских событий", "m": "events", "n": 10},
	{"id": "shine", "name": "Сияющий город", "desc": "Улучшите 10 зданий до 3 уровня", "m": "lvl3", "n": 10},
	{"id": "bliss", "name": "На седьмом небе", "desc": "Счастье города 90%", "m": "happy", "n": 90},
	{"id": "train", "name": "Чух-чух!", "desc": "Соедините рельсами две станции, чтобы пошёл поезд", "m": "rail_links", "n": 1},
	{"id": "fly", "name": "Рейс по расписанию", "desc": "Постройте два аэропорта", "m": "airports", "n": 2},
	{"id": "rides50", "name": "Час пик", "desc": "Котики совершили 50 поездок на поезде и самолёте", "m": "rides", "n": 50},
	{"id": "cats200", "name": "Котополис", "desc": "Поселите 200 котиков", "m": "cats", "n": 200},
]
const DECOR := ["palm", "flowers", "jacaranda", "statue", "umbrella", "bench", "cushion", "lantern", "cattree", "fountain", "billboard", "watertower"]
const NATURAL := ["wildpalm", "agave", "rock"]

var world
var done := {}


func _init(w) -> void:
	world = w


func quest() -> Dictionary:
	for q in QUESTS:
		if not done.has(q.id):
			return q
	return {}


func all_quests_done() -> bool:
	return quest().is_empty()


func metrics() -> Dictionary:
	var st: Dictionary = world.stats
	var m := {
		"houses": st.houses.size(), "cats": world.cats.size(), "employed": world.employed_count(),
		"food_ok": 1 if world.cats.size() > 0 and st.food_prod > world.eat_rate else 0,
		"lots": st.lots.size(), "happy": int(world.happy), "jobs": st.jobs, "wonders": st.wonders.size(),
		"tourism": int(world.tourism), "pets": world.pets_total, "day": world.day, "coins": int(world.coins),
		"jam": world.jammed, "events": world.events_seen, "rides": world.transit.rides,
		"rail_links": 0, "airports": world.transit.airports().size(),
		"roads": 0, "highway": 0, "shops": 0, "decor": 0, "services": 0, "lvl2": 0, "lvl3": 0, "hill_home": 0, "land": 0, "kinds": 0,
	}
	var kinds := {}
	for i in world.objs.size():
		if world.terrain[i] != 1:
			m.land += 1
		var o = world.objs[i]
		if o == null or o.i != i:
			continue
		if o.t == "road":
			m.roads += 1
			continue
		if o.t == "highway":
			m.highway += 1
			continue
		if o.build > 0.0 or o.t == "path" or NATURAL.has(o.t):
			continue
		var d := D.def(o.t)
		kinds[o.t] = true
		if d.has("shop"):
			m.shops += 1
		if d.has("service"):
			m.services += 1
		if DECOR.has(o.t):
			m.decor += 1
		var lvl := int(o.get("lvl", 1))
		if lvl >= 2:
			m.lvl2 += 1
		if lvl >= 3:
			m.lvl3 += 1
		if d.has("cap") and world.terrain[i] >= 3 and world.terrain[i] <= 4:
			m.hill_home += 1
	m.kinds = kinds.size()
	var nets := {}
	for b in world.transit.hubs:
		var hb: Dictionary = world.transit.hubs[b]
		if hb.kind == "rail" and hb.net >= 0:
			nets[hb.net] = nets.get(hb.net, 0) + 1
	for n in nets:
		if nets[n] >= 2:
			m.rail_links += 1
	return m


func progress(g: Dictionary, m: Dictionary) -> int:
	return mini(int(m.get(g.m, 0)), int(g.n))


## Проверяет цели; возвращает только что выполненные.
func check() -> Array:
	var m := metrics()
	var out: Array = []
	var q := quest()
	# задания — по очереди, достижения — в любом порядке
	while not q.is_empty() and progress(q, m) >= int(q.n):
		done[q.id] = true
		out.append(q)
		q = quest()
	for a in ACHIEVEMENTS:
		if not done.has(a.id) and progress(a, m) >= int(a.n):
			done[a.id] = true
			out.append(a)
	return out


## Для старых сохранений: отметить уже выполненное без наград и уведомлений.
func sync_silently() -> void:
	check()
