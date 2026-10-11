extends RefCounted
## Экономика города: монетки, еда, счастье, производство и склады,
## грузовики между зданиями и экспорт через грузовой порт.

const D = preload("res://scripts/defs.gd")
const T := D.T
const OUT_CAP := 16.0
const IN_CAP := 16.0
const USE_CAP := 10.0
const DEPOT_CAP := 40.0
const MAKE_RATE := 0.1           # единиц товара в секунду при полном штате
const USE_RATE := 0.02           # сколько товара расходует магазин или кафе в секунду
const TRUCK_LOAD := 8

var world: KotoWorld
var hungry := false
var income := 0.0
var tourism := 0.0
var eat_rate := 0.0
var _freight_t := 0.0


func _init(w) -> void:
	world = w


# =====================================================================
#  Экономика и грузовики
# =====================================================================

func town_happiness() -> float:
	var sum := 0.0
	var w := 0.0
	for h in world.stats.houses:
		var n: int = world.residents.get(h, []).size()
		var ww := float(n) if n > 0 else 0.3
		sum += world.stats.house_happy[h] * ww
		w += ww
	var v := sum / w if w > 0.0 else 50.0
	v -= minf(20.0, homeless_count() * 3.0)
	v -= minf(10.0, world.street_parked.size() * 0.5 + world.jammed * 0.5)
	if hungry:
		v -= 25.0
	v += world.pet_bonus
	v += world.events.happy_bonus()
	return clampf(v, 0.0, 100.0)


func homeless_count() -> int:
	var n := 0
	for c in world.cats:
		if c.home < 0:
			n += 1
	return n


func employed_count() -> int:
	var n := 0
	for c in world.cats:
		if c.job >= 0:
			n += 1
	return n


func _update_economy(dt: float) -> void:
	var n := world.cats.size()
	var fp := 0.0
	var shop_income := 0.0
	var employed := 0
	tourism = 0.0
	for b in world.stats.tourists:
		tourism += float(world.stat(world.objs[b], "tourism"))
	for b in world.stats.workplaces:
		var o = world.objs[b]
		var d := D.def(o.t)
		var nw: int = world.workers.get(b, []).size()
		employed += nw
		var boost := _produce(o, nw, dt)
		if d.has("food"):
			fp += (float(world.stat(o, "food")) + float(world.stat(o, "food_per", 0.0)) * nw) * (1.0 + (boost - 1.0) * 0.8)
		if d.has("shop") and nw > 0:
			shop_income += float(world.stat(o, "shop")) * (0.6 + 0.4 * nw / float(world.stat(o, "jobs"))) * boost
		elif boost > 1.0 and nw > 0:
			# стройконтора, архитекторы и другие без магазина: материалы — это премия работникам
			shop_income += nw * 0.3 * (boost - 1.0)
	world.stats.food_prod = fp
	eat_rate = n * 0.04
	world.food = clampf(world.food + (fp - eat_rate) * dt, 0.0, maxf(world.stats.food_cap, world.food))
	hungry = world.food <= 0.01 and eat_rate > fp
	world.pet_bonus = maxf(0.0, world.pet_bonus - dt * 0.05)
	world.happy = town_happiness()
	var mult: float = (0.5 + world.happy / 100.0) * 0.75 * (1.0 + world.events.income_bonus())
	income = (employed * 0.35 + (n - employed) * 0.08 + shop_income + tourism) * mult
	if world.coins < world.stats.coin_cap:
		world.coins = minf(world.stats.coin_cap, world.coins + income * dt)
	if n < world.stats.cap and world.happy >= 20.0:
		world.spawn_t += dt * (0.4 + world.happy / 100.0)
		if world.spawn_t >= 11.0:
			world.spawn_t = 0.0
			world.spawn_cat()


## Какие товары здание принимает: сырьё для переработки или товары для продажи.
func needs_of(t: String) -> Array:
	var out: Array = D.USES.get(t, []).duplicate()
	if D.MAKES.has(t):
		for g in D.MAKES[t][1]:
			if not out.has(g):
				out.append(g)
	return out


func stock_of(o, g: String) -> float:
	return float(o.get("stock", {}).get(g, 0.0))


func _cap_for(o, g: String) -> float:
	var d := D.def(o.t)
	if d.get("depot", false):
		return DEPOT_CAP * (1.0 + 0.5 * (int(o.get("lvl", 1)) - 1))
	if D.MAKES.has(o.t) and D.MAKES[o.t][1].has(g):
		return IN_CAP
	return USE_CAP


## Производство и расход товаров у одного здания. Возвращает множитель дохода (1 — как обычно).
func _produce(o: Dictionary, nw: int, dt: float) -> float:
	if nw <= 0:
		o.erase("busy")
		return 1.0
	var boost := 1.0
	var mk = D.MAKES.get(o.t)
	if mk != null:
		var f := float(nw) / float(world.stat(o, "jobs")) * (1.0 + 0.35 * (int(o.get("lvl", 1)) - 1))
		var r := MAKE_RATE * f * dt
		var out: float = o.get("out", 0.0)
		var busy := false
		if out < OUT_CAP:
			var ok := true
			for g in mk[1]:
				if stock_of(o, g) < r:
					ok = false
			if ok:
				for g in mk[1]:
					o.stock[g] = stock_of(o, g) - r
				o["out"] = minf(OUT_CAP, out + r)
				busy = true
		else:
			busy = not (mk[1] as Array).is_empty()
		if busy:
			o["busy"] = true
		else:
			o.erase("busy")
		if busy and not (mk[1] as Array).is_empty():
			boost = 1.5
	var uses: Array = D.USES.get(o.t, [])
	if not uses.is_empty():
		if not o.has("stock"):
			o["stock"] = {}
		var have := 0
		for g in uses:
			var v := stock_of(o, g)
			if v > 0.0:
				have += 1
				o.stock[g] = maxf(0.0, v - USE_RATE * dt)
		boost *= 1.0 + 0.6 * have / float(uses.size())
	return boost


func _truck_limit(b: int) -> int:
	var o = world.objs[b]
	return (2 if D.def(o.t).get("depot", false) else 1) + int(o.get("lvl", 1)) - 1


## Раз в секунду грузовики развозят готовые товары: сначала тем, кому они нужны, потом на склад или в порт.
func _update_freight(dt: float) -> void:
	_freight_t -= dt
	if _freight_t > 0.0:
		return
	_freight_t = 1.0
	var inc := {}
	var trucks := {}
	for car in world.cars:
		if not car.has("cargo"):
			continue
		trucks[car.base] = trucks.get(car.base, 0) + 1
		if not car.get("dropped", false):
			if not inc.has(car.target):
				inc[car.target] = {}
			inc[car.target][car.cargo] = inc[car.target].get(car.cargo, 0) + int(car.n)
	var sources: Array = []
	for b in world.stats.workplaces:
		var o = world.objs[b]
		if o == null or world.workers.get(b, []).is_empty() or trucks.get(b, 0) >= _truck_limit(b):
			continue
		if float(o.get("out", 0.0)) >= 4.0:
			sources.append(b)
		elif D.def(o.t).get("depot", false):
			for g in o.get("stock", {}):
				if o.stock[g] >= 4.0:
					sources.append(b)
					break
	sources.shuffle()
	var tries := 0
	for b in sources:
		if tries >= 3:
			break
		tries += 1
		_dispatch(b, inc)


func _dispatch(b: int, inc: Dictionary) -> void:
	var o = world.objs[b]
	var depot: bool = D.def(o.t).get("depot", false)
	var offers: Array = []
	if depot:
		for g in o.get("stock", {}):
			if o.stock[g] >= 4.0:
				offers.append([g, o.stock[g]])
		offers.shuffle()
	else:
		offers.append([D.MAKES[o.t][0], float(o.get("out", 0.0))])
	var starts := world.access_roads(b)
	if starts.is_empty():
		return
	var bc := world.center_of(b)
	for of in offers:
		var g: String = of[0]
		var have: float = of[1]
		var cands: Array = []
		for s in world.stats.sinks.get(g, []):
			if s == b or not world.is_ready(s):
				continue
			var space: float = _cap_for(world.objs[s], g) - stock_of(world.objs[s], g) - inc.get(s, {}).get(g, 0)
			if space >= 3.0:
				var sc := world.center_of(s)
				cands.append([absf(sc.x - bc.x) + absf(sc.y - bc.y), s, space])
		# лишнее — на склад, а если и он полон или его нет — в порт на экспорт (когда своё хранилище почти полно)
		if not depot and have >= OUT_CAP - 4.0:
			for s in world.stats.depots:
				var space: float = _cap_for(world.objs[s], g) - stock_of(world.objs[s], g) - inc.get(s, {}).get(g, 0)
				if world.is_ready(s) and space >= 3.0:
					var sc := world.center_of(s)
					cands.append([1000.0 + absf(sc.x - bc.x) + absf(sc.y - bc.y), s, space])
			for s in world.stats.ports:
				if world.is_ready(s):
					var sc := world.center_of(s)
					cands.append([2000.0 + absf(sc.x - bc.x) + absf(sc.y - bc.y), s, 99.0])
		cands.sort_custom(func(x, y): return x[0] < y[0])
		for k in mini(3, cands.size()):
			var s: int = cands[k][1]
			var route = world.road_route(starts, world._to_set(world.access_roads(s)))
			if route == null:
				continue
			var n := mini(TRUCK_LOAD, int(minf(have, cands[k][2])))
			if n < 3:
				continue
			if depot:
				o.stock[g] -= n
			else:
				o.out = float(o.out) - n
			if route.size() < 2:
				# соседи у одной дороги — товар просто переносят через улицу
				_deliver({"target": s, "cargo": g, "n": n})
				return
			var car := world._make_car("cargo", D.GOODS[g].col, route, null, s, b)
			car.base = b
			car["cargo"] = g
			car["n"] = n
			world.cars.append(car)
			if not inc.has(s):
				inc[s] = {}
			inc[s][g] = inc[s].get(g, 0) + n
			return


## Грузовик доехал: товар — в здание, а в порту — монетки за экспорт.
func _deliver(car: Dictionary) -> void:
	car["dropped"] = true
	var s: int = car.target
	if not world.is_ready(s):
		return
	var o = world.objs[s]
	var g: String = car.cargo
	world.deliveries += 1
	if D.def(o.t).get("export", false):
		var price := 2 if D.GOODS[g].get("raw", false) else 5
		var got: int = car.n * price
		if world.coins < world.stats.coin_cap:
			world.coins = minf(world.stats.coin_cap, world.coins + got)
		world.exported += int(car.n)
		world.float_text(world.center_of(s) * T + Vector2(8, -10), "+%d" % got, Color("c08a1a"))
		return
	if not o.has("stock"):
		o["stock"] = {}
	o.stock[g] = minf(_cap_for(o, g), stock_of(o, g) + car.n)
