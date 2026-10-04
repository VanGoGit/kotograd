extends RefCounted
## Яхты и лодки: стоят у яхт-клубов и пристаней, а днём выходят покататься по заливу.

const D = preload("res://scripts/defs.gd")
const W := D.W
const H := D.H
const T := D.T
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const INK := Color("3b2a3a")
const HULL_COLORS := ["e45b6b", "5b8de4", "ffd23f", "5fae73", "ff9f43", "9b7ad1"]

var world
var boats: Array = []
var _sync_t := 0.0


func _init(w) -> void:
	world = w


func _water(i: int) -> bool:
	if world.terrain[i] != world.WATER:
		return false
	var o = world.objs[i]
	# под мостами проплывают
	return o == null or o.t == "road" or o.t == "highway" or o.t == "rail"


## Причальные клетки здания: вода прямо рядом с ним.
func _docks(b: int) -> Array:
	var out: Array = []
	for p in world.around(b):
		var i: int = p.y * W + p.x
		if _water(i) and world.objs[i] == null:
			out.append(p)
	return out


## Лодки появляются у готовых пристаней и исчезают, если пристань снесли.
func rebuild() -> void:
	var want := {}
	for i in W * H:
		var o = world.objs[i]
		if o == null or o.i != i or o.build > 0.0:
			continue
		var n := int(D.def(o.t).get("boats", 0))
		if n > 0:
			want[i] = n
	var keep: Array = []
	var have := {}
	for bt in boats:
		if want.has(bt.home) and have.get(bt.home, 0) < want[bt.home]:
			keep.append(bt)
			have[bt.home] = have.get(bt.home, 0) + 1
	boats = keep
	for b in want:
		var docks := _docks(b)
		if docks.is_empty():
			continue
		while have.get(b, 0) < want[b]:
			var k: int = have.get(b, 0)
			var dock: Vector2i = docks[k % docks.size()]
			var kind: String = D.def(world.objs[b].t).get("boat", "yacht")
			boats.append({
				"home": b, "kind": kind, "dock": dock, "slot": k / docks.size(), "path": [], "k": 0, "prog": 0.0,
				"state": "dock", "timer": randf_range(2.0, 20.0), "dir": "r" if k % 2 == 0 else "l",
				"col": HULL_COLORS[(b + k * 3) % HULL_COLORS.size()], "cat": false,
			})
			have[b] = k + 1


func update(dt: float) -> void:
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync_t = 2.0
		rebuild()
	var h: float = world.hour()
	var day := h >= 7.5 and h < 19.5
	for bt in boats:
		match bt.state:
			"dock":
				bt.timer -= dt
				if bt.timer <= 0.0:
					bt.timer = randf_range(6.0, 14.0)
					if day:
						_set_sail(bt)
			"out", "back":
				var sp := 0.9 if bt.kind == "yacht" else 1.5
				bt.prog += sp * dt
				while bt.prog >= 1.0 and bt.k < bt.path.size() - 1:
					bt.prog -= 1.0
					bt.k += 1
				if bt.k >= bt.path.size() - 1:
					bt.k = bt.path.size() - 1
					bt.prog = 0.0
					if bt.state == "out":
						bt.state = "rest"
						bt.timer = randf_range(3.0, 8.0)
					else:
						bt.state = "dock"
						bt.timer = randf_range(15.0, 45.0)
						bt.cat = false
				else:
					_face(bt)
			"rest":
				bt.timer -= dt
				if bt.timer <= 0.0:
					var back: Array = bt.path.duplicate()
					back.reverse()
					bt.path = back
					bt.k = 0
					bt.prog = 0.0
					bt.state = "back"


## Выходим в залив: случайная точка на воде в нескольких клетках от пристани.
func _set_sail(bt: Dictionary) -> void:
	var start: int = bt.dock.y * W + bt.dock.x
	var prev := {start: -1}
	var dist := {start: 0}
	var q: Array = [start]
	var head := 0
	var far: Array = []
	var maxd := 14 if bt.kind == "yacht" else 10
	while head < q.size():
		var u: int = q[head]
		head += 1
		if dist[u] >= 6:
			far.append(u)
		if dist[u] >= maxd:
			continue
		for dv in DIRS:
			var nx: int = u % W + dv.x
			var ny: int = u / W + dv.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var n := ny * W + nx
			if prev.has(n) or not _water(n):
				continue
			prev[n] = u
			dist[n] = dist[u] + 1
			q.append(n)
	if far.is_empty():
		return
	var goal: int = far.pick_random()
	var path: Array = []
	var k := goal
	while k != -1:
		path.append(Vector2i(k % W, k / W))
		k = prev[k]
	path.reverse()
	bt.path = path
	bt.k = 0
	bt.prog = 0.0
	bt.state = "out"
	bt.cat = world.inside_count.get(bt.home, 0) > 0 or randf() < 0.6
	_face(bt)


func _face(bt: Dictionary) -> void:
	var a: Vector2i = bt.path[bt.k]
	var b: Vector2i = bt.path[mini(bt.k + 1, bt.path.size() - 1)]
	if b.x > a.x:
		bt.dir = "r"
	elif b.x < a.x:
		bt.dir = "l"
	elif b.y > a.y:
		bt.dir = "d"
	elif b.y < a.y:
		bt.dir = "u"


func boat_pos(bt: Dictionary) -> Vector2:
	if bt.state == "dock" or bt.path.is_empty():
		var off := Vector2(0, 0)
		if bt.slot > 0:
			off = Vector2(5 * (1 if bt.slot % 2 == 1 else -1), 3)
		return Vector2(bt.dock.x * T + 8, bt.dock.y * T + 9) + off
	var a: Vector2i = bt.path[bt.k]
	var b: Vector2i = bt.path[mini(bt.k + 1, bt.path.size() - 1)]
	return (Vector2(a) + (Vector2(b) - Vector2(a)) * bt.prog) * T + Vector2(8, 8)


# ---------- отрисовка ----------

func draw_items(list: Array) -> void:
	for bt in boats:
		list.append([boat_pos(bt).y + 3.0, 6, bt])


func draw_boat(bt: Dictionary) -> void:
	var w = world
	var p := boat_pos(bt).round()
	var moving: bool = bt.state == "out" or bt.state == "back"
	var side: bool = bt.dir == "r" or bt.dir == "l"
	var s := -1.0 if bt.dir == "l" else 1.0
	# след на воде
	if moving:
		var back: Vector2 = {"r": Vector2(-1, 0), "l": Vector2(1, 0), "d": Vector2(0, -1), "u": Vector2(0, 1)}[bt.dir]
		var ph := int(w.anim_time * 6.0) % 2
		var foam := Color(1, 1, 1, 0.7)
		if side:
			w.draw_rect(Rect2(p.x + back.x * (12 + ph), p.y + 1, 3, 1), foam)
			w.draw_rect(Rect2(p.x + back.x * (16 + ph), p.y - 1 + ph * 3, 2, 1), Color(1, 1, 1, 0.45))
		else:
			w.draw_rect(Rect2(p.x - 1, p.y + back.y * (10 + ph), 1, 2), foam)
			w.draw_rect(Rect2(p.x + 1, p.y + back.y * (13 + ph), 1, 2), Color(1, 1, 1, 0.45))
	else:
		# у причала покачиваемся
		p.y += roundf(sin(w.anim_time * 1.8 + bt.home) * 0.6)
	if bt.kind == "yacht":
		_draw_yacht(p, side, s, bt)
	else:
		_draw_motorboat(p, side, s, bt)


func _fur(bt: Dictionary) -> Color:
	var keys: Array = D.CAT_COLORS.keys()
	return Color(D.CAT_COLORS[keys[bt.home % keys.size()]].a)


func _cat_on(p: Vector2, bt: Dictionary) -> void:
	var w = world
	var fc := _fur(bt)
	w.draw_rect(Rect2(p.x, p.y, 3, 3), fc)
	w.draw_rect(Rect2(p.x, p.y - 1, 1, 1), fc)
	w.draw_rect(Rect2(p.x + 2, p.y - 1, 1, 1), fc)
	w.draw_rect(Rect2(p.x + 1, p.y + 1, 1, 1), INK)


func _draw_yacht(p: Vector2, side: bool, s: float, bt: Dictionary) -> void:
	var w = world
	var white := Color("f8f9fc")
	var hull := Color(bt.col)
	var glass := Color("9fd3e6")
	if side:
		w.draw_rect(Rect2(p.x - 9, p.y + 3, 18, 1), Color(0.157, 0.118, 0.196, 0.25))
		# корпус с острым носом по ходу
		var hp := PackedVector2Array([Vector2(-10, -2), Vector2(10, -2), Vector2(7, 3), Vector2(-9, 3)])
		var hi := PackedVector2Array([Vector2(-9, -1), Vector2(8, -1), Vector2(6, 2), Vector2(-8, 2)])
		for k in 4:
			hp[k] = p + Vector2(hp[k].x * s, hp[k].y)
			hi[k] = p + Vector2(hi[k].x * s, hi[k].y)
		w.draw_colored_polygon(hp, INK)
		w.draw_colored_polygon(hi, white)
		w.draw_rect(Rect2(p.x - 8, p.y + 1, 15, 1), hull)
		# рубка
		var cx := p.x - s * 4.0 - 3.0
		w.draw_rect(Rect2(cx - 1, p.y - 5, 8, 4), INK)
		w.draw_rect(Rect2(cx, p.y - 4, 6, 3), white)
		w.draw_rect(Rect2(cx + 1, p.y - 4, 4, 1), glass)
		# мачта, грот и стаксель
		w.draw_rect(Rect2(p.x, p.y - 21, 1, 19), Color("6a6478"))
		w.draw_colored_polygon(PackedVector2Array([p + Vector2(s * 1.0, -20), p + Vector2(s * 1.0, -6), p + Vector2(s * 10.0, -6)]), white)
		w.draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 1.0, -18), p + Vector2(-s * 1.0, -6), p + Vector2(-s * 7.0, -6)]), Color("e4e9f2"))
		w.draw_rect(Rect2(p.x + (1 if s > 0 else -9), p.y - 7, 8, 1), hull)
		if bt.cat:
			_cat_on(Vector2(p.x + s * 5.0 - 1.0, p.y - 4), bt)
	else:
		w.draw_rect(Rect2(p.x - 4, p.y + 8, 8, 1), Color(0.157, 0.118, 0.196, 0.25))
		var nose := -1.0 if bt.dir == "u" else 1.0
		var hp := PackedVector2Array([Vector2(-4, -8), Vector2(4, -8), Vector2(4, 6), Vector2(0, 9), Vector2(-4, 6)])
		var hi := PackedVector2Array([Vector2(-3, -7), Vector2(3, -7), Vector2(3, 5), Vector2(0, 8), Vector2(-3, 5)])
		for k in 5:
			hp[k] = p + Vector2(hp[k].x, hp[k].y * nose)
			hi[k] = p + Vector2(hi[k].x, hi[k].y * nose)
		w.draw_colored_polygon(hp, INK)
		w.draw_colored_polygon(hi, white)
		w.draw_rect(Rect2(p.x - 2, p.y - 3, 4, 4), glass)
		w.draw_rect(Rect2(p.x - 3, p.y - 7 if nose > 0 else p.y + 5, 6, 1), hull)
		w.draw_rect(Rect2(p.x, p.y - 22, 1, 20), Color("6a6478"))
		w.draw_rect(Rect2(p.x - 4, p.y - 20, 4, 14), white)
		w.draw_rect(Rect2(p.x + 1, p.y - 18, 3, 12), Color("e4e9f2"))
		w.draw_rect(Rect2(p.x - 4, p.y - 10, 4, 1), hull)
		if bt.cat:
			_cat_on(Vector2(p.x - 1, p.y + (2 if nose > 0 else -6)), bt)
	if w.dark > 0.1:
		w.lights.append(Vector3(p.x, p.y - 21, 6))


func _draw_motorboat(p: Vector2, side: bool, s: float, bt: Dictionary) -> void:
	var w = world
	var hull := Color(bt.col)
	var white := Color("f8f9fc")
	if side:
		w.draw_rect(Rect2(p.x - 6, p.y + 3, 12, 1), Color(0.157, 0.118, 0.196, 0.25))
		var hp := PackedVector2Array([Vector2(-7, -2), Vector2(8, -2), Vector2(5, 3), Vector2(-7, 3)])
		var hi := PackedVector2Array([Vector2(-6, -1), Vector2(6, -1), Vector2(4, 2), Vector2(-6, 2)])
		for k in 4:
			hp[k] = p + Vector2(hp[k].x * s, hp[k].y)
			hi[k] = p + Vector2(hi[k].x * s, hi[k].y)
		w.draw_colored_polygon(hp, INK)
		w.draw_colored_polygon(hi, hull)
		w.draw_rect(Rect2(p.x - 6, p.y - 1, 12, 1), white)
		# лобовое стекло и мотор
		w.draw_rect(Rect2(p.x + s * 2.0 - (2 if s < 0 else 0), p.y - 4, 2, 3), Color("9fd3e6"))
		w.draw_rect(Rect2(p.x - s * 7.0 - (2 if s > 0 else 0), p.y - 3, 2, 5), Color("3b3b4a"))
		if bt.cat:
			_cat_on(Vector2(p.x - s * 2.0 - 1.0, p.y - 4), bt)
	else:
		w.draw_rect(Rect2(p.x - 3, p.y + 6, 6, 1), Color(0.157, 0.118, 0.196, 0.25))
		var nose := -1.0 if bt.dir == "u" else 1.0
		var hp := PackedVector2Array([Vector2(-4, -6), Vector2(4, -6), Vector2(4, 4), Vector2(0, 7), Vector2(-4, 4)])
		var hi := PackedVector2Array([Vector2(-3, -5), Vector2(3, -5), Vector2(3, 3), Vector2(0, 6), Vector2(-3, 3)])
		for k in 5:
			hp[k] = p + Vector2(hp[k].x, hp[k].y * nose)
			hi[k] = p + Vector2(hi[k].x, hi[k].y * nose)
		w.draw_colored_polygon(hp, INK)
		w.draw_colored_polygon(hi, hull)
		w.draw_rect(Rect2(p.x - 2, p.y + 1 * nose - 1, 4, 1), Color("9fd3e6"))
		if bt.cat:
			_cat_on(Vector2(p.x - 1, p.y - 3 * nose - 1), bt)
	if w.dark > 0.1 and bt.state != "dock":
		w.lights.append(Vector3(p.x, p.y - 2, 8))
