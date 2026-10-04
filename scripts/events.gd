extends RefCounted
## Живые события: праздники, на которые собираются гости, — без стресса, просто разнообразие.

const D = preload("res://scripts/defs.gd")
const W := D.W
const H := D.H
const T := D.T

# h — часы, когда событие может начаться; dur — длительность в игровых часах
const KINDS := {
	"beach": {"name": "Фестиваль на пляже", "desc": "Музыка, мороженое и серфинг — все на пляж!", "h": [10.0, 16.0], "dur": 3.0, "n": 12, "happy": 8.0, "income": 0.1,
		"outfits": ["surfer", "lifeguard", "icecream", "casual0", "casual1", "casual2", "casual3", "casual4", "casual5"]},
	"fireworks": {"name": "Салют над океаном", "desc": "Сегодня вечером праздничный салют — посмотрите на небо!", "h": [20.5, 23.0], "dur": 1.8, "n": 10, "happy": 10.0, "income": 0.0,
		"outfits": ["casual0", "casual1", "casual2", "casual3", "casual4", "casual5", "fan"]},
	"market": {"name": "Фермерская ярмарка", "desc": "Овощи, мёд и кошачья мята прямо с грядки.", "h": [9.0, 14.0], "dur": 3.0, "n": 12, "happy": 4.0, "income": 0.25,
		"outfits": ["farmer", "baker", "casual0", "casual1", "casual2", "casual3", "casual4", "casual5"]},
	"premiere": {"name": "Кинопремьера", "desc": "Красная дорожка, звёзды в тёмных очках и вспышки камер!", "h": [18.5, 22.0], "dur": 2.5, "n": 10, "happy": 6.0, "income": 0.15,
		"outfits": ["actor", "actor", "blogger", "usher", "tourist"]},
	"game": {"name": "Матч «Котоджерс»", "desc": "Бейсбол, хот-доги и волна на трибунах!", "h": [12.0, 16.0], "dur": 2.5, "n": 14, "happy": 6.0, "income": 0.2,
		"outfits": ["fan"]},
	"tourists": {"name": "Автобус туристов", "desc": "Туристы приехали посмотреть на чудо света и привезли монетки.", "h": [9.0, 16.0], "dur": 2.5, "n": 10, "happy": 3.0, "income": 0.0, "coins": 150,
		"outfits": ["tourist"]},
}
const FW_COLORS := ["ff6b8b", "ffd75e", "7fc4e8", "c8a8ff", "9ed8c8", "ffffff", "ffb07a"]

var world
var active = null            # текущее событие или null
var visitors: Array = []
var cool := 4.0              # игровых часов до следующей попытки
var _last_abs := -1.0
var _spawn_t := 0.0
var _fx_t := 0.0


func _init(w) -> void:
	world = w


func happy_bonus() -> float:
	return KINDS[active.kind].happy if active != null else 0.0


func income_bonus() -> float:
	return KINDS[active.kind].income if active != null else 0.0


func update(dt: float) -> void:
	var ah: float = world.abs_hour()
	if _last_abs < 0.0 or ah < _last_abs:
		_last_abs = ah
	# скачки времени (загрузка, перемотка) не должны обрывать праздник
	var dh := clampf(ah - _last_abs, 0.0, 0.25)
	_last_abs = ah
	_update_visitors(dt)
	if active != null:
		active.left -= dh
		_event_fx(dt)
		if active.left <= 0.0:
			_finish()
		return
	cool -= dh
	if cool <= 0.0:
		cool = 1.0
		if world.cats.size() >= 6:
			_try_start("")


## Запустить событие (kind = "" — случайное подходящее). force — не смотреть на время суток.
func _try_start(kind: String, force := false) -> bool:
	var h: float = world.hour()
	var options: Array = []
	for k in KINDS:
		if kind != "" and k != kind:
			continue
		var r: Array = KINDS[k].h
		if not force and (h < r[0] or h > r[1]):
			continue
		var place = _find_place(k)
		if place != null:
			options.append([k, place])
	if options.is_empty():
		return false
	var pick: Array = options.pick_random()
	_start(pick[0], pick[1])
	return true


func force(kind: String) -> bool:
	if active != null:
		return false
	return _try_start(kind, true)


func _start(kind: String, place: Dictionary) -> void:
	var k: Dictionary = KINDS[kind]
	active = {"kind": kind, "name": k.name, "pos": place.pos, "area": place.area, "b": place.get("b", -1), "left": k.dur, "spawned": 0}
	world.events_seen += 1
	if k.has("coins") and not world.unlimited:
		world.coins = minf(world.stats.coin_cap, world.coins + k.coins)
	world.sound.play("cheer" if kind != "fireworks" else "fanfare", 1.0, -8.0)
	world.ui.event_started(active, k.desc)


func _finish() -> void:
	for v in visitors:
		v.leaving = true
	world.ui.event_finished(active)
	active = null
	cool = randf_range(10.0, 22.0)


func _find_place(kind: String):
	var b := -1
	match kind:
		"beach":
			var sand: Array = []
			for i in W * H:
				if world.terrain[i] == 2 and world.objs[i] == null and _near_water(i):
					sand.append(i)
			if sand.size() < 6:
				return null
			var i: int = sand.pick_random()
			return _place_at(Vector2(i % W, i / W), -1)
		"fireworks":
			for w in world.stats.wonders:
				if world.objs[w].t == "pier_wheel":
					b = w
			if b < 0:
				var coast: Array = []
				for i in W * H:
					if world.terrain[i] != 1 and world.foot_ok(i) and _near_water(i):
						coast.append(i)
				if coast.is_empty():
					return null
				var i: int = coast.pick_random()
				return _place_at(Vector2(i % W, i / W), -1)
		"market":
			var opts: Array = world.stats.strolls + world.stats.leisure
			if opts.is_empty():
				return null
			b = opts.pick_random()
		"premiere":
			var opts: Array = []
			for w in world.stats.workplaces:
				if ["cinema", "studio", "theater"].has(world.objs[w].t):
					opts.append(w)
			if opts.is_empty():
				return null
			b = opts.pick_random()
		"game":
			for w in world.stats.wonders:
				if world.objs[w].t == "stadium":
					b = w
		"tourists":
			if world.stats.wonders.is_empty():
				return null
			b = world.stats.wonders.pick_random()
	if b < 0:
		return null
	return _place_at(world.center_of(b), b)


func _place_at(pos: Vector2, b: int):
	var area: Array = []
	var cx := roundi(pos.x)
	var cy := roundi(pos.y)
	for y in range(cy - 4, cy + 5):
		for x in range(cx - 4, cx + 5):
			if x < 1 or y < 1 or x >= W - 1 or y >= H - 1:
				continue
			var i := y * W + x
			if world.objs[i] == null and world.terrain[i] != 1 and Vector2(x, y).distance_to(pos) <= 4.5:
				area.append(Vector2i(x, y))
	if area.size() < 5:
		return null
	return {"pos": pos, "area": area, "b": b}


func _near_water(i: int) -> bool:
	var x := i % W
	var y := i / W
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + dv.x
		var ny: int = y + dv.y
		if nx >= 0 and ny >= 0 and nx < W and ny < H and world.terrain[ny * W + nx] == 1:
			return true
	return false


# ---------- гости ----------

func _update_visitors(dt: float) -> void:
	if active != null and active.spawned < KINDS[active.kind].n:
		_spawn_t -= dt
		if _spawn_t <= 0.0:
			_spawn_t = 0.5
			_spawn_visitor()
	var k := visitors.size() - 1
	while k >= 0:
		var v: Dictionary = visitors[k]
		v.anim += dt
		if v.leaving:
			v.fade -= dt * 0.8
			if v.fade <= 0.0:
				visitors.remove_at(k)
			k -= 1
			continue
		v.fade = minf(1.0, v.fade + dt * 1.5)
		if v.wait > 0.0:
			v.wait -= dt
		else:
			_step_visitor(v, dt)
		k -= 1


func _spawn_visitor() -> void:
	var area: Array = active.area
	var t: Vector2i = area.pick_random()
	var outfits: Array = KINDS[active.kind].outfits
	visitors.append({
		"x": float(t.x), "y": float(t.y), "nx": t.x, "ny": t.y, "goal": area.pick_random(), "dir": 1 if randf() < 0.5 else -1,
		"anim": randf() * 3.0, "color": D.CAT_COLORS.keys().pick_random(), "outfit": outfits.pick_random(),
		"wait": randf_range(0.0, 2.0), "fade": 0.0, "leaving": false, "walking": false,
	})
	active.spawned += 1
	world._dust(t.x, t.y)


func _step_visitor(v: Dictionary, dt: float) -> void:
	var target := Vector2(v.nx, v.ny)
	var pos := Vector2(v.x, v.y)
	if pos.distance_to(target) > 0.01:
		v.walking = true
		var np := pos.move_toward(target, dt * 1.1)
		if absf(np.x - pos.x) > 0.001:
			v.dir = 1 if np.x > pos.x else -1
		v.x = np.x
		v.y = np.y
		return
	v.walking = false
	var cur := Vector2i(v.nx, v.ny)
	var goal: Vector2i = v.goal
	if cur == goal or randf() < 0.08:
		# постоять, посмотреть по сторонам
		v.goal = (active.area if active != null else [cur]).pick_random()
		v.wait = randf_range(1.0, 4.0)
		return
	var best: Array = []
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cur + dv
		var i: int = n.y * W + n.x
		if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H or not world.foot_ok(i) or world.objs[i] != null:
			continue
		if Vector2(n).distance_to(Vector2(goal)) < Vector2(cur).distance_to(Vector2(goal)):
			best.append(n)
	if best.is_empty():
		v.goal = cur
		return
	var nxt: Vector2i = best.pick_random()
	v.nx = nxt.x
	v.ny = nxt.y


# ---------- эффекты ----------

func _event_fx(dt: float) -> void:
	_fx_t -= dt
	if _fx_t > 0.0:
		return
	var p: Vector2 = active.pos * T + Vector2(8, 0)
	var area: Array = active.area
	var spot: Vector2i = area.pick_random()
	var sp := Vector2(spot.x * T + 8, spot.y * T)
	match active.kind:
		"beach":
			_fx_t = 0.5
			world.add_p({"type": "note", "x": sp.x, "y": sp.y, "vx": randf_range(-6, 6), "vy": -14.0, "life": 1.8, "col": ["ff6b8b", "7fc4e8", "ffd75e"].pick_random()})
			if randf() < 0.3:
				world.add_p({"type": "balloon", "x": sp.x, "y": sp.y, "vx": randf_range(-3, 3), "vy": -10.0, "life": 5.0, "col": FW_COLORS.pick_random(), "ph": randf() * 6.0})
		"market":
			_fx_t = 0.6
			world.add_p({"type": "coin", "x": sp.x, "y": sp.y - 6, "vx": 0.0, "vy": -12.0, "life": 1.2})
		"premiere", "tourists":
			_fx_t = 0.35
			world.add_p({"type": "flash", "x": sp.x + randf_range(-4, 4), "y": sp.y - 4, "vx": 0.0, "vy": 0.0, "life": 0.25})
		"game":
			_fx_t = 0.25
			world.add_p({"type": "confetti", "x": p.x + randf_range(-24, 24), "y": p.y - 30, "vx": randf_range(-10, 10), "vy": randf_range(-20, -5), "g": 30.0, "life": 2.5, "col": FW_COLORS.pick_random(), "ph": randf() * 6.0})
			if randf() < 0.04:
				world.float_text(p + Vector2(0, -20), ["Ура!", "Хоум-ран!", "Мяу-у!"].pick_random(), Color("e45b6b"))
				world.sound.play("cheer", randf_range(0.9, 1.1), -14.0)
		"fireworks":
			_fx_t = randf_range(0.4, 1.0)
			launch_rocket(p + Vector2(randf_range(-30, 30), 0))


func launch_rocket(from: Vector2) -> void:
	world.add_p({"type": "rocket", "x": from.x, "y": from.y, "vx": randf_range(-6, 6), "vy": randf_range(-95, -75), "life": randf_range(0.9, 1.2), "col": FW_COLORS.pick_random()})


## Ракета догорела — рассыпается искрами.
func burst(p: Dictionary) -> void:
	var n := 26
	for k in n:
		var a := TAU * k / n + randf() * 0.2
		var sp := randf_range(26, 40)
		world.add_p({"type": "spark", "x": p.x, "y": p.y, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 18.0, "life": randf_range(1.0, 1.5), "col": p.col})
	if world.on_screen(Vector2(p.x, p.y)):
		world.sound.play("boom", randf_range(0.8, 1.2), -12.0)
