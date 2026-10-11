extends SceneTree
## Дымовой тест симуляции без окна:
##   godot --headless --path . -s res://tests/sim_test.gd
## Строит город из всех построек, какие удаётся поставить, и гоняет его несколько игровых дней
## на высокой скорости. Ловит ошибки скриптов, NaN в монетках и координатах, потерю котиков
## и проверяет, что большой город переживает сохранение и загрузку без изменений.

const DIR := "user://sim_test"
const PATH := DIR + "/save.json"
const DAYS := 2

var fails := 0
var errors: ErrorCatcher


## Считает ошибки движка и скриптов — в headless-режиме они только печатаются и не роняют тест.
class ErrorCatcher extends Logger:
	var count := 0
	var first := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1
		if first == "":
			first = "%s:%d %s: %s" % [file, line, function, rationale if rationale != "" else code]

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("KOTO_TEST", "1")
	OS.set_environment("KOTO_SAVE", PATH)
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	errors = ErrorCatcher.new()
	OS.add_logger(errors)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var w = main.world
	seed(12345)
	w.new_game()
	w.unlimited = true

	var kinds := _build_city(w)
	print("— построено видов построек: %d" % kinds.size())
	_check(kinds.size() >= 25, "в городе больше 25 видов построек")

	var t0 := Time.get_ticks_msec()
	w.speed = 10
	var day0: int = w.day
	var max_cats := 0
	# один вызов — 0,1 с реального времени, то есть 1 игровая секунда на скорости 10
	for k in int(w.DAY_LEN * DAYS):
		w._process(0.1)
		max_cats = maxi(max_cats, w.cats.size())
		if k % 60 == 0 and not _sane(w):
			break
	print("— прошло дней: %d, котиков: %d, машин: %d, за %.1f с" % [w.day - day0, w.cats.size(), w.cars.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	_check(w.day - day0 >= DAYS, "прошло %d игровых дня" % DAYS)
	_check(max_cats >= 10, "в город переехали котики")
	_check(w.cats.size() >= max_cats / 2, "котики не пропадают")
	_check(w.employed_count() > 0, "котики ходят на работу")
	_check(_sane(w), "монетки, еда и координаты — обычные числа")

	var text: String = w.saves.serialize()
	_check(w.saves.save_game(), "большой город сохраняется")
	_check(w.saves.import_save(text), "и загружается")
	var again: String = w.saves.serialize()
	if again != text:
		_diff(JSON.parse_string(text), JSON.parse_string(again), "")
	_check(again == text, "после загрузки город тот же")
	for k in 30:
		w._process(0.1)
	_check(_sane(w), "загруженный город живёт дальше")

	_check(errors.count == 0, "ошибок скриптов нет" + ("" if errors.count == 0 else " (%d, первая: %s)" % [errors.count, errors.first]))
	main.free()
	print("ИТОГ: %s" % ("всё в порядке" if fails == 0 else "ошибок: %d" % fails))
	quit(1 if fails > 0 else 0)


## Квартал у стартовой точки: суша, сетка дорог и по одной постройке каждого вида, что встанет.
func _build_city(w) -> Dictionary:
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


## Печатает первые расхождения двух сохранений — чтобы сразу видеть, какое поле теряется.
func _diff(a, b, path: String, budget := [8]) -> void:
	if budget[0] <= 0:
		return
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k):
				budget[0] -= 1
				print("  нет после загрузки: %s.%s" % [path, k])
			else:
				_diff(a[k], b[k], "%s.%s" % [path, k], budget)
		for k in b:
			if not a.has(k):
				budget[0] -= 1
				print("  лишнее после загрузки: %s.%s" % [path, k])
	elif a is Array and b is Array and a.size() == b.size():
		for n in a.size():
			_diff(a[n], b[n], "%s[%d]" % [path, n], budget)
	elif a != b:
		budget[0] -= 1
		print("  %s: %s → %s" % [path, str(a).left(80), str(b).left(80)])


func _sane(w) -> bool:
	if not (is_finite(w.coins) and is_finite(w.food)):
		print("  монетки или еда: %s / %s" % [w.coins, w.food])
		return false
	for c in w.cats:
		var p: Vector2 = w.cat_pos(c)
		if not (is_finite(p.x) and is_finite(p.y)) or not w.in_map(int(c.x), int(c.y)):
			print("  котик вне карты: %s %s" % [c.name, p])
			return false
	for car in w.cars:
		if not (is_finite(car.px) and is_finite(car.py)):
			print("  машина с NaN: %s" % car.kind)
			return false
	return true


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
