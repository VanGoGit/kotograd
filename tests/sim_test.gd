extends SceneTree
## Дымовой тест симуляции без окна:
##   godot --headless --path . -s res://tests/sim_test.gd
## Строит город из всех построек, какие удаётся поставить, и гоняет его несколько игровых дней
## на высокой скорости. Ловит ошибки скриптов, NaN в монетках и координатах, потерю котиков
## и проверяет, что большой город переживает сохранение и загрузку без изменений.

const DIR := "user://sim_test"
const PATH := DIR + "/save.json"
const DAYS := 2
const City = preload("res://tests/city.gd")

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
	seed(int(OS.get_environment("KOTO_SEED")) if OS.has_environment("KOTO_SEED") else 12345)
	w.new_game()
	w.unlimited = true

	var kinds := City.build(w)
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
	_check(w.economy.employed_count() > 0, "котики ходят на работу")
	_check(_sane(w), "монетки, еда и координаты — обычные числа")

	var text: String = w.saves.serialize()
	_check(w.saves.save_game(), "большой город сохраняется")
	_check(w.saves.import_save(text), "и загружается")
	var again: String = w.saves.serialize()
	if _norm(again) != _norm(text):
		_diff(JSON.parse_string(text), JSON.parse_string(again), "")
		_text_diff(_norm(text), _norm(again))
	_check(_norm(again) == _norm(text), "после загрузки город тот же")
	for k in 30:
		w._process(0.1)
	_check(_sane(w), "загруженный город живёт дальше")

	_check(errors.count == 0, "ошибок скриптов нет" + ("" if errors.count == 0 else " (%d, первая: %s)" % [errors.count, errors.first]))
	main.free()
	print("ИТОГ: %s" % ("всё в порядке" if fails == 0 else "ошибок: %d" % fails))
	quit(1 if fails > 0 else 0)


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
	elif a is Array and b is Array:
		if a.size() != b.size():
			budget[0] -= 1
			print("  %s: длина %d → %d" % [path, a.size(), b.size()])
		for n in mini(a.size(), b.size()):
			_diff(a[n], b[n], "%s[%d]" % [path, n], budget)
	elif a != b:
		budget[0] -= 1
		print("  %s: %s → %s" % [path, str(a).left(80), str(b).left(80)])


## Дробные числа — с точностью до 6 знаков: JSON может по-разному записать 1e-15.
## Целые и дробные при этом различаются: 1 и 1.0 — разные записи.
func _norm(text: String) -> String:
	var re := RegEx.create_from_string("-?[0-9]+[.][0-9]+(?:[eE][-+]?[0-9]+)?")
	var out := ""
	var at := 0
	for m in re.search_all(text):
		out += text.substr(at, m.get_start() - at) + ("%.6f" % m.get_string().to_float())
		at = m.get_end()
	return out + text.substr(at)


## Значения равны, а текст нет — обычно целое число стало дробным (1 → 1.0). Показываем место.
func _text_diff(a: String, b: String) -> void:
	var n := 0
	while n < mini(a.length(), b.length()) and a[n] == b[n]:
		n += 1
	print("  текст расходится: …%s… → …%s…" % [a.substr(maxi(0, n - 60), 90), b.substr(maxi(0, n - 60), 90)])


func _sane(w) -> bool:
	if not (is_finite(w.coins) and is_finite(w.food)):
		print("  монетки или еда: %s / %s" % [w.coins, w.food])
		return false
	for c in w.cats:
		var p: Vector2 = w.cats_ai.cat_pos(c)
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
