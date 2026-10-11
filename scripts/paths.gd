extends RefCounted
## Поиск путей: пешком по клеткам (A* с кучей) и на машине по дорогам,
## с объездом пробок; подъезды к зданиям.

const D = preload("res://scripts/defs.gd")
const W := D.W
const H := D.H
const HILL := D.HILL
const MOUNTAIN := D.MOUNTAIN
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var world: KotoWorld


func _init(w) -> void:
	world = w


# =====================================================================
#  Поиск путей
# =====================================================================

func _tile_cost(i: int) -> float:
	var o = world.objs[i]
	if o != null:
		if o.t == "path" or o.t == "blvd":
			return 1.0
		if o.t == "road":
			# по проезжей части котики не гуляют — только переходят её, лучше по зебре
			return 4.0 if world.crosswalks.has(i) else 30.0
		if o.t == "rail" or o.t == "crossing":
			return 30.0
		return 1.6
	match world.terrain[i]:
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
			if not world.in_map(nx, ny):
				continue
			var n := ny * W + nx
			if not world.walkable_idx(n):
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
	for p in world.around(b):
		if world.foot_ok(p.y * W + p.x):
			g[p.y * W + p.x] = true
	if g.is_empty():
		for p in world.around(b):
			if world.walkable_idx(p.y * W + p.x):
				g[p.y * W + p.x] = true
	return g


## Сколько «стоит» въехать на клетку: магистраль быстрее, светофоры и пробки — дольше.
func _step_cost(n: int) -> int:
	var o = world.objs[n]
	var c := 2 if o.t == "highway" else (6 if o.t == "crossing" else 4)
	if world.junctions.has(n):
		c += 3
	return c + mini(3, world._cong.get(n, 0)) * 5


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
				if not world.is_drivable(nx, ny):
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
	for p in world.around(b):
		if world.is_road(p.x, p.y):
			out.append(p.y * W + p.x)
	return out


## Дорога, до которой от здания можно дойти: вплотную или в паре шагов по тротуару и траве.
func access_roads(b: int) -> Array:
	var near := roads_around(b)
	if not near.is_empty():
		return near
	var seen := {}
	var front: Array = []
	for p in world.around(b):
		var i: int = p.y * W + p.x
		if world.foot_ok(i):
			seen[i] = true
			front.append(i)
	var out: Array = []
	for depth in 3:
		var nxt: Array = []
		for i in front:
			for dv in DIRS:
				var nx: int = i % W + dv.x
				var ny: int = i / W + dv.y
				if not world.in_map(nx, ny):
					continue
				var n := ny * W + nx
				if seen.has(n):
					continue
				seen[n] = true
				if world.is_road(nx, ny):
					out.append(n)
				elif world.foot_ok(n):
					nxt.append(n)
		if not out.is_empty():
			return out
		front = nxt
	return out
