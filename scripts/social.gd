extends RefCounted
## Характер, желания и дружба котиков — маленькие истории, как в «Симс».
## Всё считается раз в игровую секунду (tick из мира), а не каждый кадр.
##
## У котика:
##   traits  — две черты из D.TRAITS;
##   wish    — желание или null: {"k": вид, "t": тип постройки, "b": клетка, "f": id друга, "until": час};
##   wish_next — абсолютный час, раньше которого новое желание не появится;
##   friends — id другого котика -> очки дружбы.

const D = preload("res://scripts/defs.gd")
const I18n = preload("res://scripts/i18n.gd")
const T := D.T

const FRIEND := 30.0             # очков, чтобы стать друзьями (≈ два похода в кафе вместе)
const BEST := 120.0              # лучшие друзья
const MAX_FRIENDS := 6
const MAX_KNOWN := 12            # сколько знакомых помним (лишних с малыми очками забываем)
const WISH_HOURS := 4.0          # сколько игровых часов желание ждёт, потом котик о нём просто забывает
const WISH_SHARE := 8            # не больше одного желания на столько котиков: игра не должна торопить
const WISH_REWARD := 15

var world: KotoWorld
var _news_ms := -100000          # чтобы новости о дружбе не сыпались пачкой


func _init(w) -> void:
	world = w


# ---------- характер ----------

## Две черты, которые не спорят друг с другом. Соня встаёт позже и ложится раньше.
func give_traits(c: Dictionary) -> void:
	var keys: Array = D.TRAITS.keys()
	var a: String = keys.pick_random()
	var b := a
	while b == a or _clash(a, b):
		b = keys.pick_random()
	c["traits"] = [a, b]
	if has_trait(c, "sleepy"):
		c.wake = minf(c.wake + 1.0, 9.0)
		c.work_at = maxf(c.work_at, c.wake + 0.3)
		c.bed = maxf(c.bed - 1.0, 19.5)


func _clash(a: String, b: String) -> bool:
	for p in D.TRAIT_CLASH:
		if p.has(a) and p.has(b):
			return true
	return false


func has_trait(c: Dictionary, t: String) -> bool:
	return c.get("traits", []).has(t)


## Типы построек, которые котик любит (досуг или прогулки) — по его чертам.
func liked(c: Dictionary, key: String) -> Array:
	var out := []
	for t in c.get("traits", []):
		out.append_array(D.TRAITS.get(t, {}).get(key, []))
	return out


## Сколько черты добавляют к желанию посидеть дома или погулять.
func lean(c: Dictionary, key: String) -> float:
	var v := 0.0
	for t in c.get("traits", []):
		v += float(D.TRAITS.get(t, {}).get(key, 0.0))
	return v


func traits_text(c: Dictionary) -> String:
	var names := []
	for t in c.get("traits", []):
		if D.TRAITS.has(t):
			names.append(tr(D.TRAITS[t].name))
	return ", ".join(names)


# ---------- раз в игровую секунду ----------

func tick() -> void:
	var ah := world.abs_hour()
	var h := world.hour()
	var ready_types := {}
	for i in world.objs.size():
		var o = world.objs[i]
		if o != null and o.i == i and o.build <= 0.0:
			ready_types[o.t] = true
	var by_id := {}
	var wishing := 0
	for c in world.cats:
		by_id[c.id] = c
		if c.get("wish") != null:
			wishing += 1
	var cap := maxi(2, world.cats.size() / WISH_SHARE)
	for c in world.cats:
		var w = c.get("wish")
		if w != null:
			if ah > w.until or (h >= c.bed or h < c.wake) or not _wish_valid(c, w, by_id):
				_drop_wish(c)
			elif w.k == "build" and ready_types.has(w.t):
				fulfill(c)
		elif wishing < cap and ah >= c.get("wish_next", 0.0) and h >= c.wake and h < c.bed - 1.0 and c.home >= 0:
			_make_wish(c, ready_types, by_id)
			if c.get("wish") != null:
				wishing += 1
	_meet_up(by_id)


func _wish_valid(c: Dictionary, w: Dictionary, by_id: Dictionary) -> bool:
	match w.k:
		"visit", "stroll":
			var o = world.objs[w.b] if w.b >= 0 and w.b < world.objs.size() else null
			return o != null and o.i == w.b and o.t == w.t
		"meet":
			return by_id.has(w.f)
	return true


func _drop_wish(c: Dictionary) -> void:
	c["wish"] = null
	c["wish_next"] = world.abs_hour() + randf_range(10.0, 20.0)


# ---------- желания ----------

func _make_wish(c: Dictionary, ready_types: Dictionary, by_id: Dictionary) -> void:
	# не все сразу: каждую секунду мечтать начинает лишь малая часть котиков
	if randf() > 0.05:
		return
	var ah := world.abs_hour()
	var w = null
	var r := randf()
	if r < 0.45:
		w = _wish_place(c, "visit")
	elif r < 0.62:
		w = _wish_place(c, "stroll")
	elif r < 0.75:
		w = {"k": "pet"}
	elif r < 0.87:
		w = _wish_build(c, ready_types)
	else:
		w = _wish_meet(c, by_id)
	if w == null:
		w = _wish_place(c, "visit")
	if w == null:
		w = {"k": "pet"}
	w["until"] = ah + WISH_HOURS
	c["wish"] = w


## Сходить в любимое место (а если такого рядом нет — в любое).
func _wish_place(c: Dictionary, kind: String):
	var list: Array = world.stats.leisure if kind == "visit" else world.stats.strolls
	var near: Array = world.cats_ai._near(list, c, 26.0)
	if near.is_empty():
		return null
	var likes := liked(c, "likes" if kind == "visit" else "strolls")
	var fav := near.filter(func(b): return likes.has(world.objs[b].t))
	var b: int = (fav if fav.size() > 0 and randf() < 0.8 else near).pick_random()
	return {"k": kind, "t": world.objs[b].t, "b": b}


## Мечта о постройке, которой в городе ещё нет, но которую уже можно поставить.
func _wish_build(c: Dictionary, ready_types: Dictionary):
	var opts := []
	for t in liked(c, "likes") + liked(c, "strolls"):
		var d := D.def(t)
		if not d.is_empty() and not ready_types.has(t) and int(d.get("unlock", 0)) <= world.max_cats and not d.get("wonder", false):
			opts.append(t)
	if opts.is_empty():
		return null
	return {"k": "build", "t": opts.pick_random()}


func _wish_meet(c: Dictionary, by_id: Dictionary):
	var fr := friends_of(c, by_id)
	if fr.is_empty():
		return null
	return {"k": "meet", "f": fr.pick_random().id}


## Куда котик сейчас хочет пойти ради желания (для _desired) или null.
func wish_goal(c: Dictionary):
	var w = c.get("wish")
	if w == null:
		return null
	match w.k:
		"visit":
			return {"kind": "visit", "b": w.b}
		"stroll":
			var bc := world.center_of(w.b)
			return {"kind": "stroll", "tx": roundi(bc.x), "ty": roundi(bc.y), "sb": w.b}
		"meet":
			for f in world.cats:
				if f.id == w.f:
					# друг в гостях, на прогулке в кафе или дома — идём к нему
					if f.state == "in" and f.at >= 0 and f.at != f.get("job", -1) and world.is_ready(f.at):
						return {"kind": "visit", "b": f.at}
					if f.home >= 0 and world.is_ready(f.home):
						return {"kind": "visit", "b": f.home}
	return null


## Котик зашёл в здание: может, он об этом и мечтал (или здесь его друг).
func on_enter(c: Dictionary, b: int) -> void:
	var w = c.get("wish")
	if w != null and w.k == "visit" and world.objs[b] != null and world.objs[b].t == w.t:
		fulfill(c)
		return
	for f in world.cats:
		if f == c or f.state != "in" or f.at != b:
			continue
		if w != null and w.k == "meet" and w.f == f.id:
			fulfill(c)
			w = null
		var fw = f.get("wish")
		if fw != null and fw.k == "meet" and fw.f == c.id:
			fulfill(f)


func on_stroll(c: Dictionary, b: int) -> void:
	var w = c.get("wish")
	if w != null and w.k == "stroll" and b >= 0 and world.objs[b] != null and world.objs[b].t == w.t:
		fulfill(c)


func on_pet(c: Dictionary) -> void:
	var w = c.get("wish")
	if w != null and w.k == "pet":
		fulfill(c)


func fulfill(c: Dictionary) -> void:
	var w = c.get("wish")
	if w == null:
		return
	_drop_wish(c)
	world.wishes_done += 1
	world.coins += WISH_REWARD
	world.pet_bonus = minf(10.0, world.pet_bonus + 2.0)
	var p: Vector2 = world.cats_ai.cat_pos(c)
	world.hearts_at(p + Vector2(0, -12), 6)
	world.float_text(p + Vector2(0, -20), tr("Мечта сбылась! +%d") % WISH_REWARD, Color("e0508a"))
	world.sound.play("chime", randf_range(1.1, 1.3), -8.0)
	if w.k == "build":
		world.ui.toast(tr("Мечта сбылась: %s радуется — «%s»!") % [I18n.cat(c.name), tr(D.def(w.t).name)], false, true)


func wish_text(c: Dictionary) -> String:
	var w = c.get("wish")
	if w == null:
		return ""
	match w.k:
		"visit":
			return tr("Хочу сходить в «%s»!") % tr(D.def(w.t).name)
		"stroll":
			return tr("Хочу погулять у «%s»!") % tr(D.def(w.t).name)
		"build":
			return tr("Вот бы в городе появилось: «%s»!") % tr(D.def(w.t).name)
		"meet":
			for f in world.cats:
				if f.id == w.f:
					return tr("Хочу погулять вместе: %s!") % I18n.cat(f.name)
	return tr("Погладь меня!")


# ---------- дружба ----------

## Котики, которые сидят в одном здании или гуляют рядом, понемногу дружатся:
## в кафе и на прогулке — быстрее, коллеги — примерно за рабочий день, соседи по дому — за несколько дней.
func _meet_up(by_id: Dictionary) -> void:
	var groups := {}
	for c in world.cats:
		var key
		var pts := 1.0
		match c.state:
			"in":
				key = c.at
				var o = world.objs[c.at]
				if o == null:
					continue
				var d := D.def(o.t)
				pts = 0.1 if d.has("cap") else (0.2 if c.at == c.job else 1.5)
			"idle", "sleep", "walk":
				key = "%d,%d" % [int(c.x) / 3, int(c.y) / 3]
			_:
				continue
		if not groups.has(key):
			groups[key] = [pts]
		if groups[key].size() <= 6:
			groups[key].append(c)
	for g in groups.values():
		for i in range(1, g.size()):
			for j in range(i + 1, g.size()):
				_bond(g[i], g[j], g[0])


func _bond(a: Dictionary, b: Dictionary, pts: float) -> void:
	if has_trait(a, "social") or has_trait(b, "social"):
		pts *= 2.0
	var before := _points(a, b.id)
	_add(a, b.id, pts)
	_add(b, a.id, pts)
	var now := _points(a, b.id)
	if before < FRIEND and now >= FRIEND:
		world.friendships += 1
		_hearts_between(a, b)
		_news(tr("%s и %s подружились!") % [I18n.cat(a.name), I18n.cat(b.name)])
	elif before < BEST and now >= BEST:
		_hearts_between(a, b)
		_news(tr("%s и %s теперь лучшие друзья!") % [I18n.cat(a.name), I18n.cat(b.name)])


func _add(c: Dictionary, id: int, pts: float) -> void:
	if not c.has("friends"):
		c["friends"] = {}
	var fr: Dictionary = c.friends
	if not fr.has(id):
		# друзей и так много — новые знакомства не завязываются
		var n := 0
		for k in fr:
			if fr[k] >= FRIEND:
				n += 1
		if n >= MAX_FRIENDS:
			return
		if fr.size() >= MAX_KNOWN:
			var weakest = null
			for k in fr:
				if fr[k] < FRIEND and (weakest == null or fr[k] < fr[weakest]):
					weakest = k
			if weakest == null:
				return
			fr.erase(weakest)
	fr[id] = minf(fr.get(id, 0.0) + pts, BEST * 2.0)


func _points(c: Dictionary, id: int) -> float:
	return c.get("friends", {}).get(id, 0.0)


func friends_of(c: Dictionary, by_id = null) -> Array:
	var out := []
	for id in c.get("friends", {}):
		if c.friends[id] < FRIEND:
			continue
		if by_id != null:
			if by_id.has(id):
				out.append(by_id[id])
		else:
			for f in world.cats:
				if f.id == id:
					out.append(f)
					break
	out.sort_custom(func(x, y): return _points(c, x.id) > _points(c, y.id))
	return out


func is_best(c: Dictionary, f: Dictionary) -> bool:
	return _points(c, f.id) >= BEST


## Друг сейчас отдыхает в кафе или магазине — можно зайти к нему (для _desired).
func friend_spot(c: Dictionary) -> int:
	for f in friends_of(c):
		if f.state == "in" and f.at >= 0 and f.at != f.home and f.at != f.job and world.stats.leisure.has(f.at):
			return f.at
	return -1


func _hearts_between(a: Dictionary, b: Dictionary) -> void:
	world.hearts_at(world.cats_ai.cat_pos(a) + Vector2(0, -12), 3)
	world.hearts_at(world.cats_ai.cat_pos(b) + Vector2(0, -12), 3)


func _news(text: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _news_ms < 60000:
		return
	_news_ms = now
	world.ui.toast(text, false, true)
