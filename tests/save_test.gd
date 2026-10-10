extends SceneTree
## Проверка сохранений без окна:
##   godot --headless --path . -s res://tests/save_test.gd
## Каждый «запуск игры» — новая сцена main.tscn, как при настоящем старте.
## Сохранения пишутся в отдельную папку (KOTO_SAVE), город игрока не трогаем.

const DIR := "user://save_test"
const PATH := DIR + "/save.json"

var main: Node
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("KOTO_TEST", "1")
	OS.set_environment("KOTO_SAVE", PATH)

	print("— 1. Сохранить и загрузить — тот же город")
	_clean()
	var w = _launch()
	_check(w.save_notice == "", "без файла нет предупреждений")
	_build_city(w)
	_check(w.save_game(), "сохранение записано")
	_check(w.save_game(), "второе сохранение записано")
	_check(FileAccess.file_exists(PATH + ".bak"), "есть резервная копия .bak")
	_check(not FileAccess.file_exists(PATH + ".tmp"), "временный .tmp убран")
	var city: String = w.serialize()
	w = _launch()
	_check(w.serialize() == city, "после загрузки город тот же")
	_check(w.cats.size() > 0 and w.city_name == "Тестоград", "котики и название на месте")

	print("— 2. Обрезанный файл восстанавливается из .bak и не затирается")
	var cut := city.substr(0, city.length() / 2)
	_write(PATH, cut)
	w = _launch()
	_check(w.save_notice == "restored", "сообщение о восстановлении")
	_check(w.serialize() == city, "город восстановлен из .bak")
	var aside := _find_aside("save.json.broken-")
	_check(aside != "" and FileAccess.get_file_as_string(DIR + "/" + aside) == cut, "испорченный файл отложен как есть")
	_check(w.save_game() and FileAccess.get_file_as_string(PATH) == city, "следующее сохранение снова целое")

	print("— 3. Обрезанный файл без .bak: новый город, старый файл цел")
	_clean()
	_write(PATH, cut)
	w = _launch()
	_check(w.save_notice == "broken" and w.save_aside != "", "сообщение о повреждении")
	_check(w.city_name != "Тестоград", "начат новый город")
	_check(FileAccess.get_file_as_string(DIR + "/" + w.save_aside) == cut, "испорченный файл отложен как есть")
	w.save_game()
	_check(FileAccess.get_file_as_string(DIR + "/" + w.save_aside) == cut, "автосохранение его не тронуло")

	print("— 4. Файл из новой версии игры (v=99) не затирается")
	_clean()
	var d = JSON.parse_string(city)
	d.v = 99
	var future := JSON.stringify(d)
	_write(PATH, future)
	w = _launch()
	_check(w.save_notice == "newer" and w.save_blocked, "сообщение о новой версии")
	_check(not w.save_game(), "сохранение поверх не пишется")
	w._save_t = 1000.0
	for k in 5:
		await process_frame
	_check(FileAccess.get_file_as_string(PATH) == future, "файл не изменился и после автосохранения")
	_check(not FileAccess.file_exists(PATH + ".bak"), ".bak не появился")
	_check(not w.import_save(future) and w.save_error == "newer", "импорт такого файла отклоняется")
	w.release_save()
	_check(w.save_game() and _find_aside("save.json.newer-") != "", "новый город сохраняется, файл новой версии отложен")
	_check(FileAccess.get_file_as_string(DIR + "/" + _find_aside("save.json.newer-")) == future, "отложенный файл цел")

	print("— 5. Испорченный импорт не трогает город")
	_clean()
	_write(PATH, city)
	w = _launch()
	var before: String = w.serialize()
	var bad = JSON.parse_string(city)
	bad.objs.append([999999, "house", 1, 0.0, 1, -1])
	_check(not w.import_save(JSON.stringify(bad)), "постройка за краем карты — отказ")
	bad = JSON.parse_string(city)
	bad.cats[0].erase("name")
	_check(not w.import_save(JSON.stringify(bad)), "котик без имени — отказ")
	bad = JSON.parse_string(city)
	bad.erase("coins")
	_check(not w.import_save(JSON.stringify(bad)), "нет монеток — отказ")
	_check(not w.import_save(cut), "обрезанный файл — отказ")
	_check(not w.import_save("[1, 2]"), "не словарь — отказ")
	_check(w.serialize() == before, "город после неудачных импортов прежний")
	_check(w.import_save(city), "целый файл импортируется")

	_clean()
	main.free()
	print("ИТОГ: %s" % ("всё в порядке" if fails == 0 else "ошибок: %d" % fails))
	quit(1 if fails > 0 else 0)


## Новый «запуск игры»: прежняя сцена убирается, новая загружает сохранение в _ready.
func _launch():
	if main != null:
		main.free()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	return main.world


## Маленький город: домик у старта, дорога, котик, свои монетки и название.
func _build_city(w) -> void:
	var st: Vector2 = w.start_spot()
	var x := int(st.x)
	var y := int(st.y)
	w.terrain[y * w.W + x] = w.GRASS
	w.terrain[(y + 1) * w.W + x] = w.GRASS
	w.place_obj(y * w.W + x, "house", 7, 0.0)
	w.place_obj((y + 1) * w.W + x, "road", 3, 0.0)
	w.recalc()
	w.rebuild_maps()
	w.spawn_cat()
	w.coins = 1234.5
	w.city_name = "Тестоград"


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _find_aside(prefix: String) -> String:
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with(prefix):
			return f
	return ""


func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
