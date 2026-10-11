extends RefCounted
## Тестовый город для sim_test и замера кадра.


## Квартал у стартовой точки: суша, сетка дорог и по одной постройке каждого вида, что встанет.
static func build(w) -> Dictionary:
	var st: Vector2 = w.mapgen.start_spot()
	var x0 := clampi(int(st.x) - 16, 1, w.W - 34)
	var y0 := clampi(int(st.y) - 14, 1, w.H - 26)
	var x1 := x0 + 32
	var y1 := y0 + 24
	w.tool = "t_grass"
	for y in range(y0, y1):
		for x in range(x0, x1):
			w.apply_tool(x, y, true)
	w.tool = "road"
	for y in range(y0, y1):
		for x in range(x0, x1):
			if (x - x0) % 7 == 0 or (y - y0) % 6 == 0:
				w.apply_tool(x, y, true)
	# у кромки квартала — вода для причалов и спасателей
	w.tool = "t_water"
	for x in range(x0, x1):
		w.apply_tool(x, y1, true)

	var types := []
	for t in w.D.DEFS:
		var d: Dictionary = w.D.DEFS[t]
		if not d.has("cost") or d.has("terra") or d.get("paint", false) or t == "crossing":
			continue
		types.append(t)
	# сначала жильё, потом всё остальное — так котики переедут раньше
	types.sort_custom(func(a, b): return int(w.D.DEFS[a].has("cap")) > int(w.D.DEFS[b].has("cap")))
	var built := {}
	var spots := []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1):
			spots.append(Vector2i(x, y))
	for t in types:
		var copies := 4 if w.D.DEFS[t].has("cap") else 1
		for s in spots:
			if copies == 0:
				break
			if w.can_place(t, s.x, s.y).ok:
				w.tool = t
				w.apply_tool(s.x, s.y, true)
				built[t] = true
				copies -= 1
	w.tool = "hand"
	return built
