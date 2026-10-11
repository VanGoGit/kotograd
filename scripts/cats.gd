extends RefCounted
## Жизнь котиков: переезд в город, имена и профессии, распорядок дня,
## прогулки, досуг, поездки на машине и транспорте, поглаживания.

const D = preload("res://scripts/defs.gd")
const I18n = preload("res://scripts/i18n.gd")
const W := D.W
const T := D.T
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var world: KotoWorld


func _init(w) -> void:
	world = w


# =====================================================================
#  Котики
# =====================================================================

func _pick_name() -> String:
	var avail: Array = D.CAT_NAMES.filter(func(n): return not world.used_names.has(n))
	var nm: String
	if avail.size() > 0:
		nm = avail.pick_random()
	else:
		nm = "%s %d" % [D.CAT_NAMES.pick_random(), world.used_names.size() - D.CAT_NAMES.size() + 2]
	world.used_names.append(nm)
	return nm


func free_houses() -> Array:
	return world.stats.houses.filter(func(h): return world.residents.get(h, []).size() < world.stat(world.objs[h], "cap"))


func spawn_cat() -> void:
	if world.economy.homeless_count() > 0:
		return
	var houses := free_houses()
	if houses.is_empty():
		return
	houses.sort_custom(func(a, b): return world.stats.house_happy[a] > world.stats.house_happy[b])
	var h: int = houses[0]
	var wake := randf_range(6.2, 7.6)
	var c := {
		"id": world.next_id, "name": _pick_name(), "color": D.CAT_COLORS.keys().pick_random(), "casual": randi() % 6, "style": _city_style(),
		"home": h, "job": -1, "car": D.CAR_COLORS.pick_random() if randf() < 0.75 else "",
		"state": "in", "at": h, "x": float(h % W), "y": float(h / W), "path": [], "pi": 0, "dest": null,
		"timer": randf_range(0.5, 2.0), "dir": 1, "anim": randf() * 10.0, "pet": 0.0, "plan": null, "fail_until": 0.0,
		"wake": wake, "work_at": wake + randf_range(0.4, 1.2), "off": randf_range(16.5, 18.3), "bed": randf_range(20.6, 22.4),
		"lx": -1, "ly": -1, "car_lot": -1, "car_tile": -1, "car_dir": "r", "near_car": false,
	}
	world.next_id += 1
	world.cats.append(c)
	world.rebuild_maps()
	var prev := world.max_cats
	world.max_cats = maxi(world.max_cats, world.cats.size())
	var hc := world.center_of(h) * T + Vector2(8, 8)
	for k in 8:
		world.add_p({"type": "sparkle", "x": hc.x + randf_range(-8, 8), "y": hc.y + randf_range(-8, 4), "vx": randf_range(-6, 6), "vy": randf_range(-20, -8), "life": randf_range(0.6, 1.2)})
	world.ui.toast(tr("%s переезжает в %s!") % [I18n.cat(c.name), tr(world.city_name)], false, true)
	world.sound.play("mew", randf_range(0.9, 1.25))
	var opened := []
	for t in D.DEFS:
		var u := int(D.DEFS[t].get("unlock", 0))
		if u > prev and u <= world.max_cats:
			opened.append(tr(D.DEFS[t].name))
	if opened.size() > 0:
		world.ui.toast(tr("Открыто: %s!") % ", ".join(opened), true, true)
		world.ui.on_unlocked()
		world.sound.play("chime")
	world.ui.refresh_tools()


func outfit_key(c: Dictionary) -> String:
	if c.job >= 0 and world.objs[c.job] != null:
		return D.def(world.objs[c.job].t).get("job", "casual%d" % c.casual)
	if c.get("style", "") != "":
		return c.style
	return "casual%d" % c.casual


## Новые жители одеваются в стиле главных отраслей города:
## много офисов — больше котиков в пиджаках.
func _city_style() -> String:
	var weights := {}
	var total := 0.0
	for b in world.stats.workplaces:
		var j: String = D.def(world.objs[b].t).get("job", "")
		if j == "":
			continue
		var wgt := float(world.stat(world.objs[b], "jobs"))
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
	if c.job >= 0 and world.objs[c.job] != null:
		return tr(D.PROFESSIONS.get(D.def(world.objs[c.job].t).get("job", ""), ""))
	return tr("Ищет работу")


func _near(list: Array, c: Dictionary, dist: float) -> Array:
	var cc := world._cat_center(c)
	var out := []
	for b in list:
		var bc := world.center_of(b)
		if absf(bc.x - cc.x) + absf(bc.y - cc.y) < dist:
			out.append(b)
	return out


func _pick_leisure(c: Dictionary) -> int:
	var opts := _near(world.stats.leisure, c, 26.0)
	return opts.pick_random() if opts.size() > 0 else -1


func _pick_stroll(c: Dictionary):
	var opts := _near(world.stats.strolls, c, 22.0)
	if opts.is_empty():
		return null
	var b: int = opts.pick_random()
	var bc := world.center_of(b)
	return {"x": roundi(bc.x), "y": roundi(bc.y), "b": b}


func _desired(c: Dictionary) -> Dictionary:
	var h := world.hour()
	var ah := world.abs_hour()
	if ah < c.fail_until and c.fail_until - ah < 1.0:
		return {"kind": "wander"}
	var homeless: bool = c.home < 0
	if h >= c.bed or h < c.wake:
		return {"kind": "rest"} if homeless else _maybe_transit(c, {"kind": "home", "b": c.home})
	if c.job >= 0 and world.is_ready(c.job) and h >= c.work_at and h < c.off:
		return _maybe_transit(c, {"kind": "work", "b": c.job})
	var pl = c.plan
	if pl != null and ah < pl.until and pl.until - ah < 3.0 and (not pl.has("b") or world.is_ready(pl.b)):
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
	elif r < 0.76 and world.transit.hubs.size() >= 2:
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
	if world.transit.hubs.size() < 2 or not goal.has("b") or goal.b < 0 or world.objs[goal.b] == null:
		return null
	var from := world._cat_center(c)
	var to := world.center_of(goal.b)
	var direct := from.distance_to(to)
	var stuck: bool = world.abs_hour() < c.fail_until
	if direct <= 20.0 and not stuck and not any_distance:
		return null
	var best = null
	var best_d := 1e9
	for a in world.transit.hubs:
		if not world.is_ready(a):
			continue
		var da := world.center_of(a).distance_to(from)
		if da > 16.0:
			continue
		for b in world.transit.hubs:
			if not world.transit.connected(a, b):
				continue
			var db := world.center_of(b).distance_to(to)
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
	var opts: Array = world.stats.leisure + world.stats.strolls
	if opts.is_empty():
		return null
	for attempt in 4:
		var g: int = opts.pick_random()
		var t = _via_transit(c, {"kind": "visit", "b": g}, true)
		if t != null and world.center_of(t.to).distance_to(world._cat_center(c)) > 10.0:
			return t
	return null


func _door_of(b: int):
	for p in world.around(b):
		if world.foot_ok(p.y * W + p.x):
			return p
	for p in world.around(b):
		if world.walkable_idx(p.y * W + p.x):
			return p
	return null


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
	if c.car_lot >= 0 and (not world.is_ready(c.car_lot) or not D.def(world.objs[c.car_lot].t).has("parking")):
		c.car_lot = -1
	if c.car_tile >= 0 and not world.is_road(c.car_tile % W, c.car_tile / W):
		c.car_tile = -1


func lot_capacity(l: int) -> int:
	return int(world.stat(world.objs[l], "parking", 0))


func _find_lot(b: int) -> int:
	var bc := world.center_of(b)
	var best := -1
	var bd := 1e9
	for l in world.stats.lots:
		if world.lot_count.get(l, 0) >= lot_capacity(l) or world.paths.roads_around(l).is_empty():
			continue
		var dist := world.center_of(l).distance_to(bc)
		if dist <= 8.0 and dist < bd:
			bd = dist
			best = l
	return best


func _walk_to_car(c: Dictionary, d: Dictionary, goals: Dictionary) -> bool:
	var path = world.paths.walk_path(roundi(c.x), roundi(c.y), goals)
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
			starts = world.paths.roads_around(c.car_lot)
		else:
			return _walk_to_car(c, d, world.paths.goals_around(c.car_lot))
	elif c.state == "in" and c.at == c.home and world.is_ready(c.home):
		starts = world.paths.roads_around(c.home)
		if starts.is_empty():
			# дом не у самой дороги — сначала дойти до неё по тротуару
			var acc := world.paths.access_roads(c.home)
			if acc.is_empty():
				return false
			return _walk_to_car(c, d, _to_set(acc))
	elif c.near_car and _car_at_home(c) and c.home >= 0:
		var here := roundi(c.y) * W + roundi(c.x)
		starts = [here] if world.is_road(roundi(c.x), roundi(c.y)) else world.paths.access_roads(c.home)
	if starts.is_empty():
		return false
	var lot := -1
	if d.kind != "home":
		lot = _find_lot(d.b)
	var goal := _to_set(world.paths.access_roads(lot if lot >= 0 else d.b))
	var route = world.paths.road_route(starts, goal)
	if route == null and lot >= 0:
		lot = -1
		route = world.paths.road_route(starts, _to_set(world.paths.access_roads(d.b)))
	if route == null or route.size() < 2:
		return false
	c.car_tile = -1
	c.car_lot = -1
	c.near_car = false
	c.state = "drive"
	c.at = -1
	c.dest = d
	var car := world._make_car(world.car_model(c), c.car, route, c, d.b, -1)
	car["mode"] = "home" if d.kind == "home" else ("lot" if lot >= 0 else "street")
	car["lot"] = lot
	world.cars.append(car)
	world.rebuild_maps()
	return true


func _go_to(c: Dictionary, d: Dictionary, allow_car := true) -> void:
	var ah := world.abs_hour()
	var kind: String = d.kind
	var trip := kind == "home" or kind == "work" or kind == "visit"
	var can_car: bool = allow_car and trip and c.car != "" and world.is_ready(d.b)
	if can_car:
		_validate_car(c)
	if c.state == "in":
		var from: int = c.at
		if can_car and _car_at_home(c) and from == c.home and _try_drive(c, d):
			return
		var door = _door_of(from) if world.objs[from] != null else null
		if door == null:
			c.timer = 4.0
			if world.objs[from] == null:
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
	if can_car and _car_at_home(c) and not c.near_car and c.home >= 0 and world.is_ready(c.home) and kind != "home":
		var cp := Vector2(c.x, c.y)
		var to_goal := cp.distance_to(world.center_of(d.b))
		if to_goal > 14.0 and cp.distance_to(world.center_of(c.home)) < to_goal * 0.6:
			var acc := world.paths.access_roads(c.home)
			if not acc.is_empty() and _walk_to_car(c, d, _to_set(acc)):
				return
	var sx := roundi(c.x)
	var sy := roundi(c.y)
	var path = null
	if kind == "stroll":
		var g := {}
		for y in range(d.ty - 1, d.ty + 2):
			for x in range(d.tx - 1, d.tx + 2):
				if world.in_map(x, y) and world.walkable_idx(y * W + x):
					g[y * W + x] = true
		if world.objs[d.sb] != null:
			g.merge(world.paths.goals_around(d.sb))
		path = world.paths.walk_path(sx, sy, g) if g.size() > 0 else null
	elif d.has("b") and d.b >= 0 and world.objs[d.b] != null:
		path = world.paths.walk_path(sx, sy, world.paths.goals_around(d.b))
	if path == null:
		c.fail_until = ah + 0.6
		c.state = "idle"
		c.timer = 0.5
		# домой пешком не дойти — после пары попыток котик вызывает такси, а не спит на улице
		if kind == "home" and world.is_ready(d.b):
			c["home_fails"] = int(c.get("home_fails", 0)) + 1
			if c.home_fails >= 2:
				c.home_fails = 0
				world.float_text(cat_pos(c) + Vector2(0, -14), tr("Такси!"), Color("c8a020"))
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
		if world.in_map(nx, ny) and world.foot_ok(ny * W + nx):
			opts.append(Vector2i(nx, ny))
	if opts.is_empty():
		# стоим на дороге (вышли из машины) — сходим на ближайшую клетку
		for dv in DIRS:
			var nx: int = cx + dv.x
			var ny: int = cy + dv.y
			if world.in_map(nx, ny) and world.walkable_idx(ny * W + nx):
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
		var ob = world.obj_at(o.x, o.y)
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
	for o in world.cats:
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
	if d != null and d.kind == "trip" and world.is_ready(d.b):
		_enter(c, d.b)
		c["trip"] = {"to": d.to, "goal": d.goal, "wait": 0.0}
		return
	if d != null and (d.kind == "home" or d.kind == "work" or d.kind == "visit"):
		if world.is_ready(d.b) and (d.kind != "home" or c.home == d.b):
			_enter(c, d.b)
			return
	var o = world.obj_at(roundi(c.x), roundi(c.y))
	c.state = "idle"
	var daytime := world.hour() >= 9.0 and world.hour() < 18.0
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
			if world.objs[c.at] == null:
				c.state = "idle"
				c.timer = 0.2
				c.at = -1
				c["trip"] = null
				return
			var tp = c.get("trip")
			if tp != null:
				# ждёт поезд или самолёт; если долго нет — идёт по своим делам
				tp.wait += dt
				if tp.wait > 45.0 or not world.transit.connected(c.at, tp.to):
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
				world.add_p({"type": "z", "x": c.x * T + 10, "y": c.y * T + 2, "vx": randf_range(2, 6), "vy": -8.0, "life": 1.6})
			if c.timer <= 0.0:
				c.state = "idle"
				c.timer = 0.2
		"idle":
			c.timer -= dt
			if c.timer > 0.0:
				return
			var d := _desired(c)
			if d.kind == "wander":
				_wander_step(c, world.anchor_of(c), 7.0)
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
			if world.is_rail(tgt.x, tgt.y) and not world.is_rail(roundi(c.x), roundi(c.y)) and world.transit.train_near(tgt):
				return
			var dx: float = tgt.x - c.x
			var dy: float = tgt.y - c.y
			var dist := sqrt(dx * dx + dy * dy)
			var o = world.obj_at(tgt.x, tgt.y)
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
			if world.happy > 70.0 and randf() < dt * 0.01:
				world.hearts_at(Vector2(c.x * T + 8, c.y * T + 2), 1)


func pet_cat(c: Dictionary) -> void:
	c.pet = 1.4
	var p := cat_pos(c)
	world.hearts_at(p + Vector2(0, -12), 5)
	world.float_text(p + Vector2(0, -16), tr("мрр... zZ") if c.state == "sleep" else [tr("Мурр!"), tr("Мяу!"), tr("Мрр~")].pick_random(), Color("ff6b8b"))
	world.sound.play("mew", randf_range(0.95, 1.3))
	world.pet_bonus = minf(10.0, world.pet_bonus + 1.5)
	world.pets_total += 1
	if c.state == "idle":
		c.timer = maxf(c.timer, 1.5)


func cat_pos(c: Dictionary) -> Vector2:
	if c.state == "ride":
		var vp = world.transit.cat_vehicle_pos(c)
		if vp != null:
			return vp
	if c.state == "drive":
		for car in world.cars:
			if car.cat == c:
				return Vector2(car.px, car.py)
	if c.state == "in" and c.at >= 0 and world.objs[c.at] != null:
		return world.center_of(c.at) * T + Vector2(8, 8)
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
				return tr("в «%s»") % world.bname(dd.b)
		return tr("гулять")
	match c.state:
		"ride":
			return tr("летит на самолёте") if world.transit.vehicle_kind(c) == "air" else tr("едет на поезде")
		"drive":
			return tr("едет %s на машине") % where.call(d)
		"walk":
			return tr("идёт %s") % where.call(d) if d != null and d.kind != "wander" else tr("гуляет")
		"in":
			if c.get("trip") != null:
				return tr("ждёт %s в «%s»") % [tr("самолёт") if world.transit.hubs.get(c.at, {}).get("kind", "") == "air" else tr("поезд"), world.bname(c.at)]
			if c.at == c.home:
				return tr("спит дома") if world.is_night() else tr("отдыхает дома")
			if c.at == c.job:
				return tr("работает")
			return tr("в «%s»") % world.bname(c.at)
		"sleep":
			return tr("дремлет под открытым небом") if c.home < 0 else tr("дремлет")
	return tr("ждёт новый дом") if c.home < 0 else tr("отдыхает на улице")
