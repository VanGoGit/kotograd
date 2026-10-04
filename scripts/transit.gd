extends RefCounted
## Поезда и самолёты. Котики приходят на вокзал или в аэропорт, ждут внутри,
## садятся и едут до другой станции (или летят в другой аэропорт), а там выходят и гуляют.

const D = preload("res://scripts/defs.gd")
const W := D.W
const H := D.H
const T := D.T
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const TRAIN_LEN := 4         # локомотив и три вагона
const GAP := 13.0            # расстояние между вагонами, пикселей
const PLANE_SPEED := 70.0

var world
var trains: Array = []
var planes: Array = []
var hubs := {}               # здание -> {"kind": "rail"/"air", "net": номер сети, "stop": клетка рельсов}
var rail_net := {}           # клетка рельсов -> номер сети
var closed := {}             # закрытые переезды
var rides := 0
var _spawn_t := 0.0
var _air_cool := {}


func _init(w) -> void:
	world = w


func is_rail_tile(i: int) -> bool:
	var o = world.objs[i]
	return o != null and (o.t == "rail" or o.t == "crossing")


# ---------- сети ----------

func rebuild() -> void:
	rail_net = {}
	var net := 0
	for i in W * H:
		if not is_rail_tile(i) or rail_net.has(i):
			continue
		var q := [i]
		rail_net[i] = net
		var head := 0
		while head < q.size():
			var u: int = q[head]
			head += 1
			for dv in DIRS:
				var nx: int = u % W + dv.x
				var ny: int = u / W + dv.y
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var n := ny * W + nx
				if not rail_net.has(n) and is_rail_tile(n):
					rail_net[n] = net
					q.append(n)
		net += 1
	hubs = {}
	for b in world.stats.get("hubs", []):
		var d := D.def(world.objs[b].t)
		if d.hub == "air":
			hubs[b] = {"kind": "air", "net": -2, "stop": -1}
			continue
		var stop := -1
		for p in world.around(b):
			var i: int = p.y * W + p.x
			if rail_net.has(i):
				stop = i
				break
		hubs[b] = {"kind": "rail", "net": rail_net.get(stop, -1), "stop": stop}
	# поезда, чьи сети изменились, пересобираем
	var k := trains.size() - 1
	while k >= 0:
		var tr: Dictionary = trains[k]
		var stops := _stops_of(tr.net)
		if stops.size() < 2 or not _route_ok(tr):
			_drop_all(tr.passengers)
			trains.remove_at(k)
		else:
			tr.stops = stops
			tr.si = mini(tr.si, stops.size() - 1)
		k -= 1


func _stops_of(net: int) -> Array:
	var out: Array = []
	if net < 0:
		return out
	for b in hubs:
		if hubs[b].kind == "rail" and hubs[b].net == net and world.is_ready(b):
			out.append(b)
	out.sort()
	return out


func airports() -> Array:
	var out: Array = []
	for b in hubs:
		if hubs[b].kind == "air" and world.is_ready(b):
			out.append(b)
	return out


## Можно ли доехать от одного узла до другого.
func connected(a: int, b: int) -> bool:
	if a == b or not hubs.has(a) or not hubs.has(b):
		return false
	var ha: Dictionary = hubs[a]
	var hb: Dictionary = hubs[b]
	if ha.kind != hb.kind:
		return false
	if ha.kind == "air":
		return true
	return ha.net >= 0 and ha.net == hb.net


func _route_ok(tr: Dictionary) -> bool:
	if tr.mode != "move":
		return true
	for p in tr.route:
		if not is_rail_tile(p.y * W + p.x):
			return false
	return true


func rail_route(from: int, to: int):
	if from < 0 or to < 0:
		return null
	var prev := {from: -1}
	var q := [from]
	var head := 0
	while head < q.size():
		var u: int = q[head]
		head += 1
		if u == to:
			var out: Array = []
			var k := u
			while k != -1:
				out.append(Vector2i(k % W, k / W))
				k = prev[k]
			out.reverse()
			return out
		for dv in DIRS:
			var nx: int = u % W + dv.x
			var ny: int = u / W + dv.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var n := ny * W + nx
			if not prev.has(n) and is_rail_tile(n):
				prev[n] = u
				q.append(n)
	return null


# ---------- пассажиры ----------

func _waiting_at(b: int) -> Array:
	var out: Array = []
	for c in world.cats:
		if c.state == "in" and c.at == b and c.get("trip") != null:
			out.append(c)
	return out


func _board(c: Dictionary) -> void:
	c.state = "ride"
	c.at = -1


func _alight(c: Dictionary, b: int) -> void:
	var trip = c.get("trip")
	c.state = "in"
	c.at = b
	c.timer = randf_range(0.3, 1.0)
	c.path = []
	c.dest = null
	c["trip"] = null
	rides += 1
	if trip != null and trip.goal != null:
		var g: Dictionary = trip.goal.duplicate()
		g["until"] = world.abs_hour() + 1.5
		c.plan = g
	world.hearts_at(world.center_of(b) * T + Vector2(8, 0), 1)


## Вокзал снесли или путь разобрали — пассажиры выходят там, куда ехали (или дома).
func _drop_all(list: Array) -> void:
	for c in list:
		var trip = c.get("trip")
		var to: int = trip.to if trip != null else -1
		if to >= 0 and world.objs[to] != null:
			_alight(c, to)
		elif c.home >= 0 and world.objs[c.home] != null:
			_alight(c, c.home)
		else:
			c.state = "idle"
			c["trip"] = null
			c.timer = 0.5


func cat_vehicle_pos(c: Dictionary):
	for tr in trains:
		if tr.passengers.has(c):
			return Vector2(tr.hx, tr.hy)
	for pl in planes:
		if pl.passengers.has(c):
			return plane_pos(pl)
	return null


func vehicle_kind(c: Dictionary) -> String:
	for pl in planes:
		if pl.passengers.has(c):
			return "air"
	return "rail"


# ---------- обновление ----------

func update(dt: float) -> void:
	_spawn_t -= dt
	if _spawn_t <= 0.0:
		_spawn_t = 1.5
		_spawn_trains()
		_dispatch_planes()
	for tr in trains:
		_update_train(tr, dt)
	for b in _air_cool:
		_air_cool[b] -= dt
	var k := planes.size() - 1
	while k >= 0:
		var pl: Dictionary = planes[k]
		pl.t += dt
		if pl.t >= pl.dur:
			for c in pl.passengers:
				if world.objs[pl.to] != null:
					_alight(c, pl.to)
				else:
					_drop_all([c])
			planes.remove_at(k)
		k -= 1
	_update_crossings()


func _spawn_trains() -> void:
	var nets := {}
	for b in hubs:
		if hubs[b].kind == "rail" and hubs[b].net >= 0:
			nets[hubs[b].net] = true
	for net in nets:
		var stops := _stops_of(net)
		if stops.size() < 2:
			continue
		var have := 0
		for tr in trains:
			if tr.net == net:
				have += 1
		if have >= (2 if stops.size() >= 4 else 1):
			continue
		var si := have * (stops.size() / 2)
		var st: int = hubs[stops[si]].stop
		var p := Vector2(st % W * T + 8.0, st / W * T + 8.0)
		var trail := _initial_trail(st)
		trains.append({"net": net, "stops": stops, "si": si, "route": [Vector2i(st % W, st / W)], "k": 0, "prog": 0.0,
			"mode": "dwell", "dwell": 2.0, "passengers": [], "trail": trail, "hx": p.x, "hy": p.y, "arrived": false})


## Новый поезд сразу стоит вытянутым вдоль рельсов, а не «гармошкой».
func _initial_trail(st: int) -> Array:
	var tiles: Array = [st]
	var seen := {st: true}
	var cur := st
	for step in 4:
		var nxt := -1
		for dv in DIRS:
			var nx: int = cur % W + dv.x
			var ny: int = cur / W + dv.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var n := ny * W + nx
			if not seen.has(n) and is_rail_tile(n):
				nxt = n
				break
		if nxt < 0:
			break
		seen[nxt] = true
		tiles.append(nxt)
		cur = nxt
	tiles.reverse()
	var trail: Array = []
	for k in tiles.size():
		var a := Vector2(tiles[k] % W * T + 8.0, tiles[k] / W * T + 8.0)
		if k + 1 < tiles.size():
			var b := Vector2(tiles[k + 1] % W * T + 8.0, tiles[k + 1] / W * T + 8.0)
			for j in 16:
				trail.append(a.lerp(b, j / 16.0))
		else:
			trail.append(a)
	return trail


func _update_train(tr: Dictionary, dt: float) -> void:
	if tr.mode == "dwell":
		if not tr.arrived:
			tr.arrived = true
			_arrive(tr)
		tr.dwell -= dt
		if tr.dwell > 0.0:
			return
		# поезд стоит, пока в него не сядет котик (или пока котик не ждёт на другой станции)
		var here: int = tr.stops[tr.si]
		_board_waiting(tr, here)
		var target := _next_target(tr, here)
		if target < 0:
			tr.dwell = 0.5
			return
		var cur: Vector2i = tr.route[tr.route.size() - 1]
		var r = rail_route(cur.y * W + cur.x, hubs[target].stop)
		if r != null and r.size() >= 2:
			tr.si = tr.stops.find(target)
			tr.route = r
			tr.k = 0
			tr.prog = 0.0
			tr.mode = "move"
			tr.arrived = false
			if world.on_screen(Vector2(tr.hx, tr.hy)):
				world.sound.play("horn", 1.0, -10.0)
			return
		tr.dwell = 2.0
		return
	var route: Array = tr.route
	# впереди переезд, а на нём машина — поезд ждёт, пока она проедет
	for ahead in range(1, 3):
		var ti: int = tr.k + ahead
		if ti >= route.size():
			break
		var at: Vector2i = route[ti]
		var ai: int = at.y * W + at.x
		if world.crossings.has(ai) and _car_on(at):
			return
	var pos: float = tr.k + tr.prog
	var remaining: float = route.size() - 1 - pos
	# плавный разгон и торможение у платформ
	var f := clampf(minf(remaining, pos + 0.3) / 1.3, 0.22, 1.0)
	tr.prog += 3.2 * dt * f
	while tr.prog >= 1.0 and tr.k < route.size() - 1:
		tr.prog -= 1.0
		tr.k += 1
	if tr.k >= route.size() - 1:
		tr.k = route.size() - 1
		tr.prog = 0.0
		tr.mode = "dwell"
		tr.dwell = 3.0
	var a: Vector2i = route[tr.k]
	var b: Vector2i = route[mini(tr.k + 1, route.size() - 1)]
	var hp := Vector2(a.x + (b.x - a.x) * tr.prog, a.y + (b.y - a.y) * tr.prog) * T + Vector2(8, 8)
	tr.hx = hp.x
	tr.hy = hp.y
	var last: Vector2 = tr.trail[tr.trail.size() - 1]
	if last.distance_to(hp) >= 1.0:
		tr.trail.append(hp)
		if tr.trail.size() > 90:
			tr.trail.remove_at(0)


func _arrive(tr: Dictionary) -> void:
	var b: int = tr.stops[tr.si]
	var keep: Array = []
	for c in tr.passengers:
		var trip = c.get("trip")
		if trip == null or trip.to == b or not tr.stops.has(trip.to):
			_alight(c, b)
		else:
			keep.append(c)
	tr.passengers = keep
	for c in _waiting_at(b):
		if tr.stops.has(c.trip.to) and c.trip.to != b and tr.passengers.size() < 24:
			_board(c)
			tr.passengers.append(c)


func _board_waiting(tr: Dictionary, b: int) -> void:
	for c in _waiting_at(b):
		if tr.stops.has(c.trip.to) and c.trip.to != b and tr.passengers.size() < 24:
			_board(c)
			tr.passengers.append(c)


## Куда ехать: туда, куда нужно первому пассажиру, или за котиком на другую станцию.
func _next_target(tr: Dictionary, here: int) -> int:
	for c in tr.passengers:
		var trip = c.get("trip")
		if trip != null and tr.stops.has(trip.to) and trip.to != here:
			return trip.to
	for b in tr.stops:
		if b == here:
			continue
		for c in _waiting_at(b):
			if tr.stops.has(c.trip.to) and c.trip.to != b:
				return b
	return -1


func _dispatch_planes() -> void:
	var ap := airports()
	if ap.size() < 2:
		return
	for a in ap:
		if _air_cool.get(a, 0.0) > 0.0:
			continue
		var by_dest := {}
		for c in _waiting_at(a):
			if ap.has(c.trip.to) and c.trip.to != a:
				if not by_dest.has(c.trip.to):
					by_dest[c.trip.to] = []
				by_dest[c.trip.to].append(c)
		if by_dest.is_empty():
			continue
		var best = null
		for dst in by_dest:
			if best == null or by_dest[dst].size() > by_dest[best].size():
				best = dst
		var riders: Array = by_dest[best].slice(0, 16)
		for c in riders:
			_board(c)
		var pa: Vector2 = world.center_of(a) * T + Vector2(8, 8)
		var pb: Vector2 = world.center_of(best) * T + Vector2(8, 8)
		planes.append({"from": a, "to": best, "passengers": riders, "t": 0.0, "dur": pa.distance_to(pb) / PLANE_SPEED + 4.0, "a": pa, "b": pb})
		_air_cool[a] = 6.0
		if world.on_screen(pa):
			world.sound.play("whoosh", 1.0, -8.0)


func plane_pos(pl: Dictionary) -> Vector2:
	var k: float = clampf(pl.t / pl.dur, 0.0, 1.0)
	return pl.a.lerp(pl.b, k * k * (3.0 - 2.0 * k))


## Высота полёта 0..1: разбег, набор высоты, посадка.
func plane_alt(pl: Dictionary) -> float:
	var k: float = clampf(pl.t / pl.dur, 0.0, 1.0)
	return clampf(minf(k, 1.0 - k) * 5.0, 0.0, 1.0)


# ---------- переезды ----------

func train_segments(tr: Dictionary) -> Array:
	var out: Array = []
	var trail: Array = tr.trail
	var need := 0.0
	var acc := 0.0
	var idx := trail.size() - 1
	var p: Vector2 = trail[idx]
	for s in TRAIN_LEN:
		need = s * GAP
		while idx > 0 and acc + p.distance_to(trail[idx - 1]) < need:
			acc += p.distance_to(trail[idx - 1])
			idx -= 1
			p = trail[idx]
		var pos := p
		var dirv := Vector2.RIGHT
		if idx > 0:
			var q: Vector2 = trail[idx - 1]
			var rest := need - acc
			var seg := p.distance_to(q)
			if seg > 0.001:
				pos = p.lerp(q, clampf(rest / seg, 0.0, 1.0))
				dirv = (p - q).normalized()
		elif trail.size() > 1:
			dirv = ((trail[1] as Vector2) - (trail[0] as Vector2)).normalized()
		out.append([pos, absf(dirv.x) >= absf(dirv.y), s == 0])
	return out


## Машина уже въехала на переезд (а не ждёт перед шлагбаумом).
func _car_on(t: Vector2i) -> bool:
	for car in world.cars:
		var r: Array = car.route
		if car.k < r.size() and r[car.k] == t:
			return true
	return false


## Поезд рядом с клеткой — котикам на рельсы пока нельзя.
func train_near(t: Vector2i) -> bool:
	var cpos := Vector2(t.x * T + 8.0, t.y * T + 8.0)
	for tr in trains:
		if Vector2(tr.hx, tr.hy).distance_to(cpos) > 90.0:
			continue
		for sg in train_segments(tr):
			if (sg[0] as Vector2).distance_to(cpos) < 30.0:
				return true
	return false


func _update_crossings() -> void:
	var was := closed
	closed = {}
	for i in world.crossings:
		var cpos := Vector2(i % W * T + 8.0, i / W * T + 8.0)
		for tr in trains:
			if Vector2(tr.hx, tr.hy).distance_to(cpos) > 90.0:
				continue
			for sg in train_segments(tr):
				# шлагбаум закрывается заранее, пока поезд ещё на подходе
				if (sg[0] as Vector2).distance_to(cpos) < 48.0:
					closed[i] = true
					break
			if closed.has(i):
				break
		if closed.has(i) and not was.has(i) and world.on_screen(cpos):
			world.sound.play("ding", 1.0, -14.0)


# ---------- рисование ----------

const SILVER := Color("e8eef4")
const BLUE := Color("3d5a98")
const GLASS := Color("9fd3e6")
const INK := Color("3b2a3a")


func draw_items(list: Array) -> void:
	for tr in trains:
		for sg in train_segments(tr):
			list.append([sg[0].y + 5.0, 4, [sg, tr]])


func draw_segment(item: Array) -> void:
	var sg: Array = item[0]
	var pos: Vector2 = (sg[0] as Vector2).round()
	var horiz: bool = sg[1]
	var loco: bool = sg[2]
	var w = world
	var lit: bool = w.dark > 0.1
	if horiz:
		var r := Rect2(pos.x - 6, pos.y - 7, 13, 8)
		w.draw_rect(Rect2(r.position.x + 1, r.end.y, 12, 1), Color(0.157, 0.118, 0.196, 0.25))
		w.draw_rect(r.grow(1), INK)
		w.draw_rect(r, SILVER)
		w.draw_rect(Rect2(r.position.x, r.position.y + 5, 13, 2), BLUE)
		for k in range(1, 12, 3):
			w.draw_rect(Rect2(r.position.x + k, r.position.y + 2, 2, 2), Color("ffe9a8") if lit else GLASS)
		if loco:
			w.draw_rect(Rect2(r.position.x, r.position.y, 13, 1), Color("ffd23f"))
	else:
		var r := Rect2(pos.x - 4, pos.y - 9, 8, 13)
		w.draw_rect(Rect2(r.position.x + 1, r.end.y, 7, 1), Color(0.157, 0.118, 0.196, 0.25))
		w.draw_rect(r.grow(1), INK)
		w.draw_rect(r, SILVER)
		w.draw_rect(Rect2(r.position.x + 5, r.position.y, 2, 13), BLUE)
		for k in range(1, 12, 3):
			w.draw_rect(Rect2(r.position.x + 2, r.position.y + k, 2, 2), Color("ffe9a8") if lit else GLASS)
		if loco:
			w.draw_rect(Rect2(r.position.x, r.position.y, 8, 1), Color("ffd23f"))
	if loco and lit:
		w.lights.append(Vector3(pos.x, pos.y - 2, 12))


func draw_planes() -> void:
	var w = world
	for pl in planes:
		var p := plane_pos(pl)
		var alt := plane_alt(pl)
		var ang: float = (pl.b - pl.a).angle()
		var sc := 0.8 + alt * 0.5
		# тень на земле
		w.draw_set_transform(p + Vector2(alt * 8.0, 2.0), ang, Vector2(sc, sc) * 0.9)
		_plane_shape(Color(0.157, 0.118, 0.196, 0.22), Color(0, 0, 0, 0))
		w.draw_set_transform(p - Vector2(0, alt * 34.0), ang, Vector2(sc, sc))
		_plane_shape(Color("f4f7fb"), BLUE)
		w.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if w.dark > 0.1 and int(w.anim_time * 2.0) % 2 == 0:
			w.lights.append(Vector3(p.x, p.y - alt * 34.0, 8))


func _plane_shape(body: Color, stripe: Color) -> void:
	var w = world
	# фюзеляж, крылья, хвост — нос смотрит вправо
	w.draw_colored_polygon(PackedVector2Array([Vector2(-11, -2), Vector2(9, -2), Vector2(12, 0), Vector2(9, 2), Vector2(-11, 2)]), body)
	w.draw_colored_polygon(PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(-3, -11), Vector2(-6, -11)]), body)
	w.draw_colored_polygon(PackedVector2Array([Vector2(-2, 2), Vector2(2, 2), Vector2(-3, 11), Vector2(-6, 11)]), body)
	w.draw_colored_polygon(PackedVector2Array([Vector2(-11, -1), Vector2(-8, -1), Vector2(-11, -5), Vector2(-13, -5)]), body)
	w.draw_colored_polygon(PackedVector2Array([Vector2(-11, 1), Vector2(-8, 1), Vector2(-11, 5), Vector2(-13, 5)]), body)
	if stripe.a > 0.0:
		w.draw_rect(Rect2(-10, -0.5, 19, 1), stripe)
		w.draw_rect(Rect2(8, -1, 2, 2), Color("9fd3e6"))
